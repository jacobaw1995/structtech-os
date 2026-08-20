-- A1.5 — Crew visibility, the RLS write hole, and the anon EXECUTE sweep
-- Directive §5.1 · constraint 7 ("no dollars in the field") · §6.9
--
-- ORDER OF WORK: the UI half was authored first and ships in the same commit
-- (standing correction, 2026-08-19). This migration is the last thing to touch
-- prod.
--
-- WHY RESTRICTIVE POLICIES
--   Every existing policy on these tables is PERMISSIVE, and permissive
--   policies OR together — `deals` already carries a second permissive policy
--   ("staff all deals"). Adding a condition to one permissive policy therefore
--   does not gate anything; another policy can still let the row through. The
--   crew gates below are RESTRICTIVE, which ANDs with everything else, so they
--   cannot be OR'd around by a policy that exists now or is added later.
--
-- WHAT IS DELIBERATELY *NOT* DONE HERE
--   has_capability()'s global fallback array is NOT changed. Flipping it would
--   alter what every existing member can see, one day before A1 acceptance, in
--   a shipped and deployed mechanism. Decision recorded in §10 (controller,
--   2026-08-20). Instead this migration adds two NEW capability functions with
--   the same shape as has_capability() and a role-derived default, so no
--   existing member's answer changes: all four current members are manager-tier
--   and short-circuit to true. The fails-open finding is recorded in §6.9 and
--   scheduled for A2.

-- ---------------------------------------------------------------------------
-- 1 · CAPABILITY HELPERS
-- ---------------------------------------------------------------------------

-- Same three-tier shape as has_capability(): manager short-circuit, then an
-- explicit per-member permission, then a default. The difference is the
-- default: role-derived and CLOSED for crew-tier roles, rather than a global
-- allow-list that a member inherits by having no permissions row at all.
create or replace function public.can_view_master_work_order(p_org_id uuid)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $function$
  select coalesce(
    case
      when public.is_org_manager(p_org_id) then true
      else (
        select coalesce(
          (m.permissions ->> 'view_master_work_order')::boolean,
          m.role not in ('field', 'client_portal_viewer')
        )
        from public.org_members m
        where m.org_id = p_org_id and m.user_id = auth.uid()
      )
    end,
    false
  );
$function$;

comment on function public.can_view_master_work_order(uuid) is
  'A1.5. True when the caller may see MASTER work orders and master-level documents in this org. Manager roles always may; any member may be granted it explicitly via org_members.permissions->>''view_master_work_order''; otherwise field and client_portal_viewer may not and everyone else may. Deliberately separate from has_capability(), whose global fallback array fails open (§6.9).';

create or replace function public.can_view_financials(p_org_id uuid)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $function$
  select coalesce(
    case
      when public.is_org_manager(p_org_id) then true
      else (
        select coalesce(
          (m.permissions ->> 'view_financials')::boolean,
          m.role not in ('field', 'client_portal_viewer')
        )
        from public.org_members m
        where m.org_id = p_org_id and m.user_id = auth.uid()
      )
    end,
    false
  );
$function$;

comment on function public.can_view_financials(uuid) is
  'A1.5, constraint 7. True when the caller may see money in this org. Reads the SAME org_members.permissions->>''view_financials'' key as has_capability(), but its default is role-derived and closed for field/client_portal_viewer instead of has_capability()''s fails-open global array. The two disagree for a crew-tier member with no permissions row, which is the point; reconciling them is A2 work (§6.9).';

-- Used by the write-hole policies below. Answers one question: is this work
-- order both mine and a TRADE? That is the pair the old policies never asked.
create or replace function public.work_order_is_my_trade(p_work_order_id uuid)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $function$
  select exists (
    select 1
    from public.work_orders w
    where w.id = p_work_order_id
      and w.kind = 'trade'
      and w.org_id in (select my_org_ids())
  );
$function$;

comment on function public.work_order_is_my_trade(uuid) is
  'A1.5. Ties a child row to its parent for the check_ins / material_items / schedule_blocks / production_packets write policies: the referenced work order must be in one of my orgs AND be a trade. Closes the A1.4 finding that those policies constrained org_id and left work_order_id free.';

-- ---------------------------------------------------------------------------
-- 2 · THE RLS WRITE HOLE (A1.4 carried debt)
-- ---------------------------------------------------------------------------
-- Before: `with check (org_id in (select my_org_ids()))` and nothing else, on
-- INSERT and on UPDATE. A member could create a child row on a MASTER, or on
-- another org's work order, by direct insert; and could MOVE a legitimate row
-- onto either after creation. A1.4 made all 15 child RPCs refuse such a row.
-- This is the other half: stopping it from being created.
--
-- VERIFIED BEFORE APPLYING, not assumed: a grep for .insert( / .update( /
-- .delete( over src/ returns ZERO matches. Every write in the app goes through
-- a SECURITY DEFINER RPC, which runs as the function owner and is not subject
-- to these member policies at all. Tightening them therefore cannot touch the
-- app's write path.

drop policy "member insert own check_ins" on public.check_ins;
create policy "member insert own check_ins" on public.check_ins for insert
  with check (
    org_id in (select my_org_ids())
    and public.work_order_is_my_trade(work_order_id)
  );

drop policy "member update own check_ins" on public.check_ins;
create policy "member update own check_ins" on public.check_ins for update
  using (
    org_id in (select my_org_ids())
    and public.work_order_is_my_trade(work_order_id)
  )
  with check (
    org_id in (select my_org_ids())
    and public.work_order_is_my_trade(work_order_id)
  );

drop policy "member insert own material_items" on public.material_items;
create policy "member insert own material_items" on public.material_items for insert
  with check (
    org_id in (select my_org_ids())
    and public.work_order_is_my_trade(work_order_id)
  );

drop policy "member update own material_items" on public.material_items;
create policy "member update own material_items" on public.material_items for update
  using (
    org_id in (select my_org_ids())
    and public.work_order_is_my_trade(work_order_id)
  )
  with check (
    org_id in (select my_org_ids())
    and public.work_order_is_my_trade(work_order_id)
  );

drop policy "member insert own schedule_blocks" on public.schedule_blocks;
create policy "member insert own schedule_blocks" on public.schedule_blocks for insert
  with check (
    org_id in (select my_org_ids())
    and public.work_order_is_my_trade(work_order_id)
  );

drop policy "member update own schedule_blocks" on public.schedule_blocks;
create policy "member update own schedule_blocks" on public.schedule_blocks for update
  using (
    org_id in (select my_org_ids())
    and public.work_order_is_my_trade(work_order_id)
  )
  with check (
    org_id in (select my_org_ids())
    and public.work_order_is_my_trade(work_order_id)
  );

drop policy "member insert own production_packets" on public.production_packets;
create policy "member insert own production_packets" on public.production_packets for insert
  with check (
    org_id in (select my_org_ids())
    and public.work_order_is_my_trade(work_order_id)
  );

drop policy "member update own production_packets" on public.production_packets;
create policy "member update own production_packets" on public.production_packets for update
  using (
    org_id in (select my_org_ids())
    and public.work_order_is_my_trade(work_order_id)
  )
  with check (
    org_id in (select my_org_ids())
    and public.work_order_is_my_trade(work_order_id)
  );

-- ---------------------------------------------------------------------------
-- 3 · CREW VISIBILITY AT THE RLS LAYER
-- ---------------------------------------------------------------------------
-- RLS is the layer that matters: an RPC gate alone is bypassable by a direct
-- table read, which is the lesson A1.4 produced from the other direction.

create policy "crew cannot reach master work orders" on public.work_orders
  as restrictive for all to public
  using (kind = 'trade' or public.can_view_master_work_order(org_id))
  with check (kind = 'trade' or public.can_view_master_work_order(org_id));

-- Master-level documents follow the master. An agreement is created on a
-- master by definition (A1.3b), and after A1.3b work_order_activity is written
-- against the master too.
create policy "crew cannot reach master agreements" on public.work_order_agreements
  as restrictive for all to public
  using (public.can_view_master_work_order(org_id))
  with check (public.can_view_master_work_order(org_id));

create policy "crew cannot reach master activity" on public.work_order_activity
  as restrictive for all to public
  using (public.can_view_master_work_order(org_id));

-- Constraint 7, at the row layer. estimates / estimate_line_items / deals are
-- the three tables a crew-tier member could reach money through: measured, not
-- assumed — the pre-change probe read 4 estimates (max presented_total
-- 34000.00), 21 line items and 191 deals (max value 82000) as a real
-- role='field' member.
create policy "no dollars in the field - estimates" on public.estimates
  as restrictive for all to public
  using (public.can_view_financials(org_id))
  with check (public.can_view_financials(org_id));

create policy "no dollars in the field - estimate_line_items" on public.estimate_line_items
  as restrictive for all to public
  using (public.can_view_financials(org_id))
  with check (public.can_view_financials(org_id));

create policy "no dollars in the field - deals" on public.deals
  as restrictive for all to public
  using (public.can_view_financials(org_id))
  with check (public.can_view_financials(org_id));

-- ---------------------------------------------------------------------------
-- 4 · CREW VISIBILITY AT THE RPC LAYER
-- ---------------------------------------------------------------------------
-- These are SECURITY DEFINER, so they run as the owner and RLS does NOT apply
-- to them. The policies above do not protect them; the gate has to be written
-- into each function as well. Two layers, both required, neither sufficient.

create or replace function public.fetch_work_order(p_work_order_id uuid)
returns setof work_orders
language sql
stable security definer
set search_path to 'public'
as $function$
  select w.*
  from public.work_orders w
  where w.id = p_work_order_id
    and w.org_id in (select my_org_ids())
    and (w.kind = 'trade' or public.can_view_master_work_order(w.org_id));
$function$;

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
  v_can_see_master boolean;
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

  v_can_see_master := public.can_view_master_work_order(v_org_id);

  -- A1.5: a crew-tier caller gets nothing for a master, exactly as
  -- fetch_work_order does.
  if v_kind = 'master' and not v_can_see_master then
    return null;
  end if;

  select m.id, m.sign_off_at
  into v_master_id, v_master_sign_off
  from public.work_orders m
  where m.job_id = v_job_id and m.kind = 'master';

  -- On a trade, a crew-tier caller still gets the trade — but not a pointer up
  -- to a master they may not open, and not the master's sign-off state.
  if not v_can_see_master then
    v_master_id := null;
    v_master_sign_off := null;
  end if;

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

-- fetch_estimate keeps its name, argument and `setof estimates` return type, so
-- every existing caller is unaffected — but the four money columns come back
-- NULL for a caller who fails can_view_financials(). Converted from `language
-- sql` to plpgsql purely so it can rewrite the row; it is still STABLE and
-- still a replacement, not an overload.
create or replace function public.fetch_estimate(p_estimate_id uuid)
returns setof estimates
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  r public.estimates%rowtype;
  v_money boolean;
begin
  for r in
    select e.*
    from public.estimates e
    where e.id = p_estimate_id
      and e.org_id in (select my_org_ids())
  loop
    v_money := public.can_view_financials(r.org_id);
    if not v_money then
      r.subtotal := null;
      r.presented_total := null;
      r.tax_rate := null;
      r.tax_amount := null;
    end if;
    return next r;
  end loop;
end;
$function$;

-- The field module's Today list. Exists so the crew UI can keep its job header
-- (title, address, squares, pitch) after `estimates` is closed to a crew-tier
-- member. Note the select list: there is no money column in it at all, so this
-- RPC cannot leak a price regardless of who calls it.
create or replace function public.fetch_field_jobs(p_org_id uuid, p_today date default current_date)
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'schedule_block_id', j.id,
        'work_order_id', j.work_order_id,
        'crew_name', j.crew_name,
        'start_date', j.start_date,
        'end_date', j.end_date,
        'blocked', j.blocked,
        'blocked_reason', j.blocked_reason,
        'job_title', coalesce(nullif(j.company, ''), j.contact_name),
        'site_address', j.site_address,
        'squares', j.squares,
        'pitch', j.pitch
      ) order by j.start_date, j.created_at
    ), '[]'::jsonb)
  from (
    select sb.id, sb.work_order_id, sb.crew_name, sb.start_date, sb.end_date,
           sb.blocked, sb.blocked_reason, sb.created_at,
           e.company, e.contact_name, e.site_address, e.squares, e.pitch
    from public.schedule_blocks sb
    join public.work_orders w on w.id = sb.work_order_id
    join public.estimates e on e.id = w.estimate_id
    where sb.org_id = p_org_id
      and p_org_id in (select my_org_ids())
      and w.kind = 'trade'
      and w.voided_at is null
      and sb.end_date >= p_today
    order by sb.start_date, sb.created_at
    limit 20
  ) j;
$function$;

comment on function public.fetch_field_jobs(uuid, date) is
  'A1.5. Today + upcoming trade work for the field module. Trade work orders only, voided ones excluded, and no money column anywhere in the select list — the crew UI reads this instead of embedding estimates, which is now closed to crew-tier members by a restrictive policy.';

-- ---------------------------------------------------------------------------
-- 5 · §6.9 · THE anon EXECUTE SWEEP, AND THE DEFAULT THAT KEEPS RE-GRANTING IT
-- ---------------------------------------------------------------------------
-- The grant comes from two places, and revoking one without the other does
-- nothing: every function carries BOTH a PUBLIC grant (`=X/postgres`) and an
-- explicit `anon=X/postgres` from Supabase's default privileges. Both go.
--
-- `authenticated=X` is a separate explicit grant on 111 of the 113 — verified
-- before writing this — so revoking public and anon leaves the app's own access
-- untouched, and the two without it (assert_work_order_level,
-- job_master_sign_off) are the internal helpers A1.3b deliberately revoked from
-- everyone. No blanket re-grant is issued, precisely so those two stay revoked.
--
-- TWO DELIBERATE EXCLUSIONS — create_wh_order and get_wh_order.
-- §6.9 recorded that "every one of the 109 is refused on its first statement by
-- my_org_ids()". THAT IS FALSE, and create_wh_order is the proof: its body
-- opens `v_uid := auth.uid(); IF v_uid IS NULL THEN v_org := v_supplier;` — an
-- explicit anonymous branch. It is the Material Matrix storefront's order-
-- placement RPC and it is anon-callable BY DESIGN. get_wh_order is the matching
-- order-lookup. Revoking either would break live order placement on a
-- customer-facing site that this repo cannot test. They are left granted and
-- reported; removing them needs the Material Matrix owner's confirmation and a
-- token-scoped replacement, not a hygiene sweep the day before A1 acceptance.
--
-- The signature is taken from oid::regprocedure rather than retyped — the
-- lesson of migration-discipline rule 2.

do $sweep$
declare
  f record;
  v_count int := 0;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_roles r on r.oid = p.proowner
    where n.nspname = 'public'
      and p.prokind = 'f'
      and p.prosecdef
      and r.rolname = 'postgres'
      and p.proname not in ('create_wh_order', 'get_wh_order')
  loop
    execute format('revoke execute on function %s from public, anon', f.sig);
    v_count := v_count + 1;
  end loop;
  raise notice 'A1.5 anon sweep: revoked EXECUTE from public+anon on % security-definer functions', v_count;
end
$sweep$;

-- Without this, the next migration's functions re-acquire the grant from the
-- same default that created the problem, and the sweep above is a one-off tidy
-- rather than a fix. Scoped to `postgres`, the role every repo migration runs
-- as; the supabase_admin-owned functions in public are extension internals
-- (btree_gist) and are left alone.
alter default privileges for role postgres in schema public
  revoke execute on functions from public;
alter default privileges for role postgres in schema public
  revoke execute on functions from anon;
