-- A1.4 — Hierarchy lifecycle (directive §5.1)
--
-- Void, restore, delete and fetch stop treating a work order as a single row
-- and start treating the job as a tree.
--
-- WHAT THIS CHANGES
--   1. work_orders gains void_cascade_source_id — the cascade marker.
--   2. work_order_agreements gains void_cascade_source_id + void_cascade_prior_status.
--   3. void_work_order / restore_work_order / delete_work_order become
--      hierarchy-aware; fetch_work_order is DELIBERATELY UNCHANGED and a new
--      fetch_work_order_tree serves the tree.
--   4. 15 child functions stop ASSUMING their level and start ENFORCING it.
--
-- THE CASCADE MARKER, AND WHY A TIMESTAMP WOULD NOT DO
--   voided_at alone cannot distinguish "voided because its master was" from
--   "voided deliberately on its own". Matching timestamps are not a substitute:
--   now() is transaction-constant, so two unrelated voids in one transaction
--   collide, and two related voids in separate transactions do not match at
--   all. The marker is therefore an explicit column:
--
--     voided_at IS NULL                              -> live
--     voided_at NOT NULL, marker IS NULL             -> voided in its own right
--     voided_at NOT NULL, marker = <master id>       -> voided by that cascade
--
--   void on a master marks ONLY the trades that were live at the time.
--   restore on a master clears ONLY rows carrying its marker.
--   A trade voided on Monday therefore survives a master voided on Tuesday and
--   restored on Wednesday: the Tuesday cascade never touched it (it was already
--   voided, so the `voided_at is null` filter skipped it), so it carries no
--   marker, so Wednesday's restore does not match it.
--
-- DELETE OF A MASTER WITH CHILDREN IS REFUSED, NOT CASCADED
--   Decision, controller, 2026-08-19 (§10). §5.1 permits either. Delete is
--   irreversible and void is the reversible path that already cascades; a
--   delete cascade would let one call destroy a job's entire production record.
--   The refusal names the child count and points at void.
--
-- NO ACTIVE AGREEMENT IS ORPHANED
--   An agreement for a voided master is not active by definition ("active" is
--   status <> 'voided', per create_work_order_agreement and
--   fetch_work_order_agreement). Voiding a master voids its active agreements
--   in the same statement, marked with the same cascade discipline and with the
--   status they held preserved. RESTORE DOES REACTIVATE THEM, to exactly the
--   status they had — but only ones this cascade voided, and only when the work
--   order has no active agreement already (a change order voids and replaces;
--   reactivating a superseded agreement would produce two active documents).
--
-- assert_work_order_level() USAGE
--   None of the four lifecycle functions use it. Its contract is "raise unless
--   kind = X", which is precisely wrong for functions that must accept BOTH
--   kinds and branch. They read `kind` and branch instead. The 15 child
--   functions below DO use it — they are single-level by nature, and it is what
--   turns their ASSUMES into an ENFORCES.

-- ---------------------------------------------------------------------------
-- 1 · CASCADE MARKERS
-- ---------------------------------------------------------------------------

alter table public.work_orders
  add column void_cascade_source_id uuid references public.work_orders(id);

comment on column public.work_orders.void_cascade_source_id is
  'A1.4 cascade marker. NULL = live, or voided in its own right. Non-NULL = voided by that master work order''s cascade, and restoring that master restores this row. restore_work_order clears only rows carrying its own id, so a deliberate void is never silently reversed.';

alter table public.work_orders
  add constraint work_orders_void_cascade_requires_void
  check (void_cascade_source_id is null or voided_at is not null);

alter table public.work_order_agreements
  add column void_cascade_source_id uuid references public.work_orders(id),
  add column void_cascade_prior_status text;

comment on column public.work_order_agreements.void_cascade_source_id is
  'A1.4 cascade marker, same rule as work_orders.void_cascade_source_id. An agreement voided by a change order (void-and-replace) carries NULL here and is never reactivated by a master restore.';
comment on column public.work_order_agreements.void_cascade_prior_status is
  'The status this agreement held when a master void cascaded onto it. Restore puts this back rather than guessing ''pending''.';

alter table public.work_order_agreements
  add constraint work_order_agreements_void_cascade_consistent
  check (
    (void_cascade_source_id is null and void_cascade_prior_status is null)
    or (void_cascade_source_id is not null
        and void_cascade_prior_status is not null
        and status = 'voided')
  );

-- ---------------------------------------------------------------------------
-- 2 · fetch_work_order_tree — the hierarchy the page renders
-- ---------------------------------------------------------------------------
-- fetch_work_order itself is left exactly as it is. Its `returns setof
-- work_orders` shape is what the CURRENTLY DEPLOYED coordination and field
-- pages read; narrowing or re-typing it would have broken both in production
-- between this migration and the Vercel deploy (CLAUDE.md rule 5b). It does
-- become hierarchy-aware for free: void_cascade_source_id is part of the
-- work_orders row type, so every existing caller now receives it.
--
-- What it cannot carry is the tree — a master's trade list, or a trade's
-- master. That is this function, and it replaces two ad-hoc job-scoped table
-- queries plus a second round trip in the page.

create or replace function public.fetch_work_order_tree(p_work_order_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_kind text;
  v_job_id uuid;
  v_voided_at timestamptz;
  v_cascade_source uuid;
  v_master_id uuid;
  v_master_sign_off timestamptz;
  v_trades jsonb;
  v_job_materials int;
  v_job_schedule int;
begin
  select w.org_id, w.kind, w.job_id, w.voided_at, w.void_cascade_source_id
  into v_org_id, v_kind, v_job_id, v_voided_at, v_cascade_source
  from public.work_orders w
  where w.id = p_work_order_id;

  -- Null rather than a raise: this mirrors fetch_work_order, which returns zero
  -- rows for an inaccessible id. The page redirects on a falsy result.
  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    return null;
  end if;

  select m.id, m.sign_off_at
  into v_master_id, v_master_sign_off
  from public.work_orders m
  where m.job_id = v_job_id and m.kind = 'master';

  with node as (
    select
      t.id, t.trade, t.assignee_type, t.assignee_ref, t.predecessor_id,
      t.voided_at, t.void_cascade_source_id, t.created_at,
      (select count(*) from public.material_items mi where mi.work_order_id = t.id)::int as material_count,
      (select count(*) from public.schedule_blocks sb where sb.work_order_id = t.id)::int as schedule_count
    from public.work_orders t
    where t.job_id = v_job_id and t.kind = 'trade'
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', node.id,
        'trade', node.trade,
        'assignee_type', node.assignee_type,
        'assignee_ref', node.assignee_ref,
        'predecessor_id', node.predecessor_id,
        'voided_at', node.voided_at,
        'voided_by_cascade', node.void_cascade_source_id is not null,
        'material_count', node.material_count,
        'schedule_count', node.schedule_count
      ) order by node.created_at
    ), '[]'::jsonb)
  into v_trades
  from node;

  -- Job-wide counts span every work order on the job, master included: a
  -- pre-A1.3b master can still hold rows, and the master's roll-up line must
  -- not under-report them.
  select
    (select count(*) from public.material_items mi
       join public.work_orders w2 on w2.id = mi.work_order_id
      where w2.job_id = v_job_id)::int,
    (select count(*) from public.schedule_blocks sb
       join public.work_orders w2 on w2.id = sb.work_order_id
      where w2.job_id = v_job_id)::int
  into v_job_materials, v_job_schedule;

  return jsonb_build_object(
    'work_order_id', p_work_order_id,
    'level', v_kind,
    'job_id', v_job_id,
    'master_id', v_master_id,
    'master_sign_off_at', v_master_sign_off,
    'voided_at', v_voided_at,
    'voided_by_cascade', v_cascade_source is not null,
    'trades', v_trades,
    'job_material_count', v_job_materials,
    'job_schedule_count', v_job_schedule
  );
end;
$function$;

-- Keeps the §6.9 anon EXECUTE surface from growing by one more function.
revoke execute on function public.fetch_work_order_tree(uuid) from public, anon;
grant execute on function public.fetch_work_order_tree(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3 · void_work_order — cascades down from a master
-- ---------------------------------------------------------------------------

create or replace function public.void_work_order(p_work_order_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_kind text;
  v_job_id uuid;
begin
  select org_id, kind, job_id
  into v_org_id, v_kind, v_job_id
  from public.work_orders where id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  -- The row named in the call is ALWAYS a deliberate void, so its marker is
  -- cleared. That is what makes the Monday/Tuesday case work: a trade voided
  -- by name on Monday carries no marker and survives Wednesday's restore.
  update public.work_orders
  set voided_at = coalesce(voided_at, now()),
      void_cascade_source_id = null,
      updated_at = now()
  where id = p_work_order_id;

  if v_kind = 'master' then
    -- `voided_at is null` is the whole trick: already-voided trades are not
    -- re-stamped and not marked, so the cascade owns only what it took.
    update public.work_orders
    set voided_at = now(),
        void_cascade_source_id = p_work_order_id,
        updated_at = now()
    where job_id = v_job_id
      and kind = 'trade'
      and voided_at is null;

    -- No active agreement may point at a voided work order. Voided here in the
    -- same transaction, with the prior status preserved so restore is exact.
    update public.work_order_agreements
    set void_cascade_prior_status = status,
        status = 'voided',
        voided_at = coalesce(voided_at, now()),
        void_reason = coalesce(void_reason, 'master work order voided'),
        void_cascade_source_id = p_work_order_id,
        updated_at = now()
    where work_order_id = p_work_order_id
      and status <> 'voided';
  end if;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4 · restore_work_order — reverses the cascade, and ONLY the cascade
-- ---------------------------------------------------------------------------

create or replace function public.restore_work_order(p_work_order_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_kind text;
  v_job_id uuid;
  v_master_voided_at timestamptz;
begin
  select org_id, kind, job_id
  into v_org_id, v_kind, v_job_id
  from public.work_orders where id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  -- A live trade hanging under a voided master is not a state the tree allows.
  -- Refusing here is not SCOPE §2.8 blocking: nothing is disabled pending other
  -- data, the action itself would produce an invalid tree, and the message
  -- names the one move that works.
  if v_kind = 'trade' then
    select m.voided_at into v_master_voided_at
    from public.work_orders m
    where m.job_id = v_job_id and m.kind = 'master';

    if v_master_voided_at is not null then
      raise exception 'trade work order % cannot be restored while its master work order is voided — restore the master, which brings back every trade that was voided with it', p_work_order_id;
    end if;
  end if;

  update public.work_orders
  set voided_at = null,
      void_cascade_source_id = null,
      updated_at = now()
  where id = p_work_order_id;

  if v_kind = 'master' then
    -- Matches ONLY rows this master's cascade voided. A trade with a null
    -- marker was voided deliberately and is left exactly where it is.
    update public.work_orders
    set voided_at = null,
        void_cascade_source_id = null,
        updated_at = now()
    where kind = 'trade'
      and void_cascade_source_id = p_work_order_id;

    -- Reactivates to the exact status held before the cascade. The not-exists
    -- guard covers the one case that would otherwise produce two active
    -- documents: an agreement created while the master was voided.
    update public.work_order_agreements
    set status = void_cascade_prior_status,
        voided_at = null,
        void_reason = null,
        void_cascade_prior_status = null,
        void_cascade_source_id = null,
        updated_at = now()
    where void_cascade_source_id = p_work_order_id
      and not exists (
        select 1 from public.work_order_agreements a2
        where a2.work_order_id = work_order_agreements.work_order_id
          and a2.status <> 'voided'
      );
  end if;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 5 · delete_work_order — refuses a master that has trades
-- ---------------------------------------------------------------------------

create or replace function public.delete_work_order(p_work_order_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_kind text;
  v_job_id uuid;
  v_trade_count int;
  v_successor_count int;
  v_has_children boolean;
begin
  select org_id, kind, job_id
  into v_org_id, v_kind, v_job_id
  from public.work_orders where id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  if v_kind = 'master' then
    select count(*) into v_trade_count
    from public.work_orders
    where job_id = v_job_id and kind = 'trade';

    if v_trade_count > 0 then
      raise exception 'work order % is a master with % trade work order(s) under it and cannot be deleted — that would destroy the whole job''s production record and cannot be undone. Void it instead: voiding a master voids its live trades and can be restored.',
        p_work_order_id, v_trade_count;
    end if;
  end if;

  -- Without this the FK on predecessor_id raises a raw constraint error at the
  -- user. Same refuse-and-explain shape as the master case.
  select count(*) into v_successor_count
  from public.work_orders
  where predecessor_id = p_work_order_id;

  if v_successor_count > 0 then
    raise exception 'work order % is the predecessor of % other trade work order(s) — clear that dependency first, or void this work order instead',
      p_work_order_id, v_successor_count;
  end if;

  select
    exists(select 1 from public.material_items where work_order_id = p_work_order_id)
    or exists(select 1 from public.schedule_blocks where work_order_id = p_work_order_id)
    or exists(select 1 from public.check_ins where work_order_id = p_work_order_id)
    or exists(select 1 from public.production_packets where work_order_id = p_work_order_id)
  into v_has_children;

  if v_has_children then
    raise exception 'work order % has materials, a schedule, check-ins, or a production packet and cannot be deleted — void it instead', p_work_order_id;
  end if;

  delete from public.work_orders where id = p_work_order_id;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 6 · THE INHERIT PASS — 15 functions stop assuming their level
-- ---------------------------------------------------------------------------
-- §4.4 lists 13 functions as "INHERIT — verify only", said to inherit their
-- level from their parent. Verification found that none of them establishes a
-- level at all: every one reads org_id off its OWN row and never looks at the
-- parent work order's `kind`. They were correct only while no child row could
-- exist on a master — and that guarantee does not hold, because
-- `member insert own <table>` RLS policies let an authenticated user insert a
-- check-in, material item, schedule block or production packet straight onto a
-- master, bypassing the trade-asserting creation RPC entirely. Probe-confirmed
-- 2026-08-19. With the guarantor bypassable, all 13 were BROKEN, not ASSUMES.
--
-- The fix is the same in every one: resolve the level THROUGH THE PARENT and
-- assert it. assert_work_order_level() also checks the parent's org, which
-- closes the second half of the same hole — a child row whose own org_id is
-- mine but whose work order belongs to another org (A1.3b's silent breakage #3,
-- which was fixed for material items only).
--
-- update_material_item and delete_material_item are here too: they are the two
-- carried as debt from A1.3b and they have exactly this shape.
--
-- Every signature below is byte-identical to the live one, so these are
-- replacements, not overloads (CLAUDE.md rule 1). Overload counts are verified
-- after apply, not assumed (rule 3).

-- 6a · check_ins children ----------------------------------------------------

create or replace function public.add_check_in_photo(p_check_in_id uuid, p_photo_data_url text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.check_ins where id = p_check_in_id;

  if v_org_id is null then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  update public.check_ins
  set photos = array_append(photos, p_photo_data_url),
      updated_at = now()
  where id = p_check_in_id;
end;
$function$;

create or replace function public.remove_check_in_photo(p_check_in_id uuid, p_photo_data_url text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.check_ins where id = p_check_in_id;

  if v_org_id is null then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  update public.check_ins
  set photos = array_remove(photos, p_photo_data_url),
      updated_at = now()
  where id = p_check_in_id;
end;
$function$;

create or replace function public.update_check_in(
  p_check_in_id uuid,
  p_crew_name text default null::text,
  p_check_in_date date default null::date,
  p_hours numeric default null::numeric,
  p_materials_used text default null::text,
  p_blockers text default null::text
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.check_ins where id = p_check_in_id;

  if v_org_id is null then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  update public.check_ins
  set crew_name = coalesce(p_crew_name, crew_name),
      check_in_date = coalesce(p_check_in_date, check_in_date),
      hours = coalesce(p_hours, hours),
      materials_used = coalesce(p_materials_used, materials_used),
      blockers = coalesce(p_blockers, blockers),
      updated_at = now()
  where id = p_check_in_id;
end;
$function$;

create or replace function public.delete_check_in(p_check_in_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.check_ins where id = p_check_in_id;

  if v_org_id is null then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  delete from public.check_ins where id = p_check_in_id;
end;
$function$;

-- Stays `sql`/stable and still returns zero rows rather than raising — that is
-- the existing fetch contract for an inaccessible id, and the page treats an
-- empty result as "not found". The join is what enforces the level.
create or replace function public.fetch_check_in(p_check_in_id uuid)
returns setof check_ins
language sql
stable security definer
set search_path to 'public'
as $function$
  select c.*
  from public.check_ins c
  join public.work_orders w on w.id = c.work_order_id
  where c.id = p_check_in_id
    and w.kind = 'trade'
    and w.org_id = c.org_id
    and w.org_id in (select my_org_ids());
$function$;

-- 6b · schedule_blocks children ----------------------------------------------

create or replace function public.update_schedule_block(
  p_schedule_block_id uuid,
  p_crew_name text default null::text,
  p_start_date date default null::date,
  p_end_date date default null::date
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
  v_start_date date;
  v_end_date date;
  v_blocking_name text;
  v_blocking_ready_by date;
  v_blocked boolean;
  v_reason text;
begin
  select org_id, work_order_id, start_date, end_date
  into v_org_id, v_work_order_id, v_start_date, v_end_date
  from public.schedule_blocks where id = p_schedule_block_id;

  if v_org_id is null then
    raise exception 'schedule block not found or not accessible: %', p_schedule_block_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'schedule block not found or not accessible: %', p_schedule_block_id;
  end if;

  v_start_date := coalesce(p_start_date, v_start_date);
  v_end_date := coalesce(p_end_date, v_end_date);

  select name, ready_by into v_blocking_name, v_blocking_ready_by
  from public.material_items
  where work_order_id = v_work_order_id and ready_by is not null
  order by ready_by desc
  limit 1;

  v_blocked := v_blocking_ready_by is not null and v_start_date < v_blocking_ready_by;
  v_reason := case when v_blocked
    then format('blocked on %s (ready %s)', v_blocking_name, v_blocking_ready_by)
    else null
  end;

  update public.schedule_blocks
  set crew_name = coalesce(p_crew_name, crew_name),
      start_date = v_start_date,
      end_date = v_end_date,
      blocked = v_blocked,
      blocked_reason = v_reason,
      updated_at = now()
  where id = p_schedule_block_id;
end;
$function$;

create or replace function public.delete_schedule_block(p_schedule_block_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.schedule_blocks where id = p_schedule_block_id;

  if v_org_id is null then
    raise exception 'schedule block not found or not accessible: %', p_schedule_block_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'schedule block not found or not accessible: %', p_schedule_block_id;
  end if;

  delete from public.schedule_blocks where id = p_schedule_block_id;
end;
$function$;

-- 6c · production_packets children -------------------------------------------

create or replace function public.fetch_production_packet(p_production_packet_id uuid)
returns setof production_packets
language sql
stable security definer
set search_path to 'public'
as $function$
  select p.*
  from public.production_packets p
  join public.work_orders w on w.id = p.work_order_id
  where p.id = p_production_packet_id
    and w.kind = 'trade'
    and w.org_id = p.org_id
    and w.org_id in (select my_org_ids());
$function$;

create or replace function public.delete_production_packet(p_production_packet_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.production_packets where id = p_production_packet_id;

  if v_org_id is null then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  delete from public.production_packets where id = p_production_packet_id;
end;
$function$;

create or replace function public.update_production_packet_notes(p_production_packet_id uuid, p_notes text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.production_packets where id = p_production_packet_id;

  if v_org_id is null then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  update public.production_packets
  set notes = p_notes,
      updated_at = now()
  where id = p_production_packet_id;
end;
$function$;

create or replace function public.add_production_packet_callout(
  p_production_packet_id uuid,
  p_label text,
  p_detail text default null::text
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
  v_callout_id uuid := gen_random_uuid();
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.production_packets where id = p_production_packet_id;

  if v_org_id is null then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  update public.production_packets
  set callouts = callouts || jsonb_build_array(
        jsonb_build_object('id', v_callout_id, 'label', p_label, 'detail', p_detail)
      ),
      updated_at = now()
  where id = p_production_packet_id;

  return v_callout_id;
end;
$function$;

create or replace function public.update_production_packet_callout(
  p_production_packet_id uuid,
  p_callout_id uuid,
  p_label text default null::text,
  p_detail text default null::text
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.production_packets where id = p_production_packet_id;

  if v_org_id is null then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  update public.production_packets
  set callouts = (
        select coalesce(jsonb_agg(
          case when (elem->>'id')::uuid = p_callout_id
            then jsonb_build_object(
              'id', elem->>'id',
              'label', coalesce(p_label, elem->>'label'),
              'detail', coalesce(p_detail, elem->>'detail')
            )
            else elem
          end
        ), '[]'::jsonb)
        from jsonb_array_elements(callouts) as elem
      ),
      updated_at = now()
  where id = p_production_packet_id;
end;
$function$;

create or replace function public.delete_production_packet_callout(p_production_packet_id uuid, p_callout_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.production_packets where id = p_production_packet_id;

  if v_org_id is null then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  update public.production_packets
  set callouts = (
        select coalesce(jsonb_agg(elem), '[]'::jsonb)
        from jsonb_array_elements(callouts) as elem
        where (elem->>'id')::uuid <> p_callout_id
      ),
      updated_at = now()
  where id = p_production_packet_id;
end;
$function$;

-- 6d · material_items children — the two carried as debt from A1.3b -----------

create or replace function public.update_material_item(
  p_material_item_id uuid,
  p_name text default null::text,
  p_quantity numeric default null::numeric,
  p_ready_by date default null::date,
  p_sort_order integer default null::integer
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
  v_trade text;
  v_master_id uuid;
  v_sign_off_at timestamptz;
  v_old_name text;
  v_old_quantity numeric;
  v_old_ready_by date;
  v_actor_id uuid;
begin
  select mi.org_id, mi.work_order_id, mi.name, mi.quantity, mi.ready_by
  into v_org_id, v_work_order_id, v_old_name, v_old_quantity, v_old_ready_by
  from public.material_items mi
  where mi.id = p_material_item_id;

  -- A1.3b checked org against the parent; A1.4 adds the level. Both now come
  -- from one call, so the item's own org_id must match the work order's.
  if v_org_id is null then
    raise exception 'material item not found or not accessible: %', p_material_item_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'material item not found or not accessible: %', p_material_item_id;
  end if;

  select w.trade into v_trade from public.work_orders w where w.id = v_work_order_id;

  select s.master_id, s.sign_off_at into v_master_id, v_sign_off_at
  from public.job_master_sign_off(v_work_order_id) s;

  update public.material_items
  set name = coalesce(p_name, name),
      quantity = coalesce(p_quantity, quantity),
      ready_by = coalesce(p_ready_by, ready_by),
      sort_order = coalesce(p_sort_order, sort_order),
      updated_at = now()
  where id = p_material_item_id;

  if v_sign_off_at is not null then
    select id into v_actor_id from public.profiles where id = auth.uid();
    insert into public.work_order_activity (work_order_id, org_id, action, from_value, to_value, actor_id)
    values (
      coalesce(v_master_id, v_work_order_id), v_org_id, 'material_updated_after_signoff',
      format('%s (qty %s%s)', v_old_name, v_old_quantity, case when v_old_ready_by is not null then ', ready ' || v_old_ready_by else '' end),
      format('%s (qty %s%s) [%s]', coalesce(p_name, v_old_name), coalesce(p_quantity, v_old_quantity), case when coalesce(p_ready_by, v_old_ready_by) is not null then ', ready ' || coalesce(p_ready_by, v_old_ready_by) else '' end, coalesce(v_trade, 'trade')),
      v_actor_id
    );
  end if;
end;
$function$;

create or replace function public.delete_material_item(p_material_item_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
  v_trade text;
  v_master_id uuid;
  v_sign_off_at timestamptz;
  v_name text;
  v_actor_id uuid;
begin
  select mi.org_id, mi.work_order_id, mi.name
  into v_org_id, v_work_order_id, v_name
  from public.material_items mi
  where mi.id = p_material_item_id;

  if v_org_id is null then
    raise exception 'material item not found or not accessible: %', p_material_item_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'material item not found or not accessible: %', p_material_item_id;
  end if;

  select w.trade into v_trade from public.work_orders w where w.id = v_work_order_id;

  select s.master_id, s.sign_off_at into v_master_id, v_sign_off_at
  from public.job_master_sign_off(v_work_order_id) s;

  delete from public.material_items where id = p_material_item_id;

  if v_sign_off_at is not null then
    select id into v_actor_id from public.profiles where id = auth.uid();
    insert into public.work_order_activity (work_order_id, org_id, action, from_value, actor_id)
    values (coalesce(v_master_id, v_work_order_id), v_org_id, 'material_deleted_after_signoff',
            format('%s (%s)', v_name, coalesce(v_trade, 'trade')), v_actor_id);
  end if;
end;
$function$;
