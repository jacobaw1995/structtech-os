-- MATERIAL TAKE-OFF SPINE. Track S · 2026-09-14.
-- Rollback: supabase/rollbacks/20260914_material_take_off_spine_rollback.sql
--
-- THE PROPERTY (controller, 2026-09-14): AN ESTIMATE LINE THAT REPRESENTS MATERIAL MUST
-- BECOME A MATERIAL ITEM ON THE RIGHT TRADE WORK ORDER WITHOUT A HUMAN RE-TYPING IT, AND
-- THE SYSTEM MUST NEVER INVENT A MATERIAL THE ESTIMATE DID NOT CONTAIN.
--
-- WHAT ALREADY EXISTED, MEASURED — the premise "nothing carries estimate lines across" was
-- wrong. generate_take_off (A2.1) copies TICKED lines onto ONE chosen trade, no re-typing,
-- idempotent per trade; material_items already carries estimate_line_item_id. What it did
-- not have, each PROVED before this ran (authenticated, BMR owner JWT, synthetic Fake Lead
-- job, rolled back):
--   · condition 1 — a LABOR line ticked became a material; nothing held "is this material?"
--   · condition 3 — the same line taken off onto a SECOND trade became TWO materials
--   · condition 4 — a material a human DELETED was re-created by the next run; a human edit
--                   and a change to the signed line were both invisible
--   · condition 5 — a DIRECT INSERT created a material from a labor line on another trade
--   · and signed estimate lines are still writable at the TABLE (the RPCs refuse; the
--     "member update own estimate_line_items" policy does not test status) — so an estimate
--     line CAN change after sign-off, and the take-off must be able to see that it did.
--
-- BEFORE-MEASUREMENT (live, 2026-09-14): 21 estimate lines on 4 estimates (3 signed, 1 void);
-- 20 lines on signed estimates; 1 material item; 3 work orders (2 masters, 1 trade) on 2 jobs.
-- Only 2 of the 3 signed estimates have a job (EST-8's 10 lines have none), so the take-off
-- population is 10 lines. scope_key is NULL on all 20 signed lines; product_id on 0.
--
-- THE RULE (an input). A line's take-off disposition is decided ONLY by:
--   (a) a HUMAN decision — set_take_off_decision(), or ticking it in generate_take_off; or
--   (b) the TENANT'S OWN CONFIGURATION for the line's scope_key:
--       tenant_modules(estimating).config.scope_line_items.<scope_key>.take_off =
--         {"disposition": "material" | "not_material", "trade": "<work order trade>"}
--       and a configured trade resolves only when EXACTLY ONE live trade on the job has it.
-- Nothing else is read: never the description text, the unit, the price, or a catalog
-- link. Everything else is UNDECIDED — a state shown and resolved by a human, never a
-- default and never a skip. (The descriptions do carry "(labor)" / "(material)" markers; a
-- rule that parsed them would classify 11 of 20 by guessing at prose and still leave the 8
-- "material & labor" lines, which are not one thing. Not built.)
-- THE PERCENTAGE (an output), today: of 10 lines in the population, 1 decided (the one
-- already taken off by a human on 2026-09-10, backfilled below as that decision) and 9
-- UNDECIDED. The configuration arm decides 0, because no line has a scope_key.
--
-- THE SHAPE
--   take_off_decisions   one row per estimate line a human (or a take-off tick) decided.
--                        No row = undecided unless the tenant config decides it.
--   take_off_lines       view (security_invoker): every line on a job's estimate with its
--                        disposition, its trade, and the STATE of its material item.
--   material_items.take_off_{description,quantity,unit}
--                        what the line said AT TAKE-OFF, written only by the table trigger,
--                        so "a human edited the material" and "the estimate changed" are two
--                        different, visible facts.
--   material_items_one_per_estimate_line
--                        one material per estimate line, across ALL trades (was per trade).
--   materialize_take_off(job)   creates the decided, not-yet-taken-off materials. Never
--                        updates or re-creates anything.
--   set_take_off_decision(line, disposition, trade)   the human resolution.
--   generate_take_off    unchanged signature; a tick now records the human decision first.

-- ---------------------------------------------------------------------------------------
-- 1. What the line said at take-off
-- ---------------------------------------------------------------------------------------
alter table public.material_items
  add column take_off_description text null,
  add column take_off_quantity numeric null,
  add column take_off_unit text null;

comment on column public.material_items.take_off_description is
  'What the estimate line said when this material was taken off. Written ONLY by the
   material_items_take_off_guard trigger, from the line; a writer cannot set it. NULL on a
   hand-added material, and on the one item taken off before 2026-09-14 (not reconstructed —
   what the line said that day is not recorded anywhere).';

-- ---------------------------------------------------------------------------------------
-- 2. One material per estimate line, across every trade (condition 3)
-- ---------------------------------------------------------------------------------------
drop index public.material_items_take_off_uniq;
create unique index material_items_one_per_estimate_line
  on public.material_items (estimate_line_item_id)
  where estimate_line_item_id is not null;

-- ---------------------------------------------------------------------------------------
-- 3. The human decision (conditions 1 and 2)
-- ---------------------------------------------------------------------------------------
create table public.take_off_decisions (
  estimate_line_item_id uuid primary key references public.estimate_line_items(id) on delete cascade,
  org_id uuid not null references public.organizations(id),
  disposition text not null,
  work_order_id uuid null references public.work_orders(id) on delete set null,
  source text not null,
  decided_by uuid null,
  decided_at timestamptz not null default now(),
  item_removed_at timestamptz null,
  item_removed_by uuid null,
  constraint take_off_decisions_disposition_valid check (disposition in ('material', 'not_material')),
  constraint take_off_decisions_source_valid check (source in ('human', 'generate_take_off', 'backfill')),
  constraint take_off_decisions_trade_only_for_material check (disposition = 'material' or work_order_id is null),
  constraint take_off_decisions_removed_only_for_material check (disposition = 'material' or item_removed_at is null)
);

comment on table public.take_off_decisions is
  'Whether an estimate line is MATERIAL, and on which trade — decided by a human. No row means
   UNDECIDED unless the tenant''s scope_line_items config decides it. There is no "undecided"
   value to default to. item_removed_at records that a human deleted the taken-off material,
   so no later run re-creates it; only an explicit take-off tick clears it.';

alter table public.take_off_decisions enable row level security;
revoke all on table public.take_off_decisions from anon;
revoke insert, update, delete, truncate, references, trigger on table public.take_off_decisions from authenticated;
grant select on table public.take_off_decisions to authenticated;
create policy "member read own take_off_decisions" on public.take_off_decisions
  for select to authenticated
  using (org_id in (select my_org_ids()) and has_capability(org_id, 'view_estimates'));

create function public.take_off_decisions_validate()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
declare v_line_org uuid; v_line_estimate uuid; v_job uuid;
begin
  -- OLD vs NEW (§7.1 rule 8): a write that does not move the decision is not re-validated.
  if tg_op = 'UPDATE'
     and new.estimate_line_item_id is not distinct from old.estimate_line_item_id
     and new.org_id is not distinct from old.org_id
     and new.work_order_id is not distinct from old.work_order_id then
    return new;
  end if;

  select e.org_id, e.estimate_id into v_line_org, v_line_estimate
  from public.estimate_line_items e where e.id = new.estimate_line_item_id;

  if new.org_id is distinct from v_line_org then
    raise exception 'a take-off decision must belong to the organization of its estimate line';
  end if;

  select j.id into v_job from public.jobs j
  where j.estimate_id = v_line_estimate and j.org_id = v_line_org;

  if v_job is null then
    raise exception 'this estimate line is not on a job''s estimate — take-off decisions are made on a job';
  end if;

  if new.work_order_id is not null and not exists (
       select 1 from public.work_orders w
       where w.id = new.work_order_id and w.job_id = v_job and w.kind = 'trade'
         and w.voided_at is null and w.org_id = v_line_org) then
    raise exception 'the chosen work order is not a live trade on this line''s job';
  end if;
  return new;
end;
$function$;

create trigger take_off_decisions_validate
  before insert or update on public.take_off_decisions
  for each row execute function public.take_off_decisions_validate();

-- ---------------------------------------------------------------------------------------
-- 4. The one taken-off material that already exists becomes the decision it was
-- ---------------------------------------------------------------------------------------
insert into public.take_off_decisions (estimate_line_item_id, org_id, disposition, work_order_id, source, decided_by, decided_at)
select m.estimate_line_item_id, m.org_id, 'material', m.work_order_id, 'backfill', null, m.created_at
from public.material_items m
where m.estimate_line_item_id is not null;

-- ---------------------------------------------------------------------------------------
-- 5. The state (conditions 1, 2, 3, 4 made visible)
-- ---------------------------------------------------------------------------------------
create view public.take_off_lines with (security_invoker = true) as
with lines as (
  select j.id as job_id, e.org_id, e.estimate_id, est.status as estimate_status,
         e.id as estimate_line_item_id, e.description, e.quantity, e.unit, e.sort_order, e.scope_key,
         d.disposition as decided_disposition, d.work_order_id as decided_work_order_id,
         d.source as decided_source, d.item_removed_at,
         case when e.scope_key is not null then
           (select tm.config -> 'scope_line_items' -> e.scope_key -> 'take_off'
              from public.tenant_modules tm
             where tm.org_id = e.org_id and tm.module_key = 'estimating'
             limit 1)
         end as config_rule
  from public.estimate_line_items e
  join public.estimates est on est.id = e.estimate_id
  join public.jobs j on j.estimate_id = e.estimate_id and j.org_id = e.org_id
  left join public.take_off_decisions d on d.estimate_line_item_id = e.id
), resolved as (
  select l.*,
    case when l.decided_disposition is not null then l.decided_disposition
         when l.config_rule ->> 'disposition' in ('material', 'not_material') then l.config_rule ->> 'disposition'
         else 'undecided' end as disposition,
    case when l.decided_disposition is not null then l.decided_source
         when l.config_rule ->> 'disposition' in ('material', 'not_material') then 'tenant_config'
    end as disposition_source,
    case when l.decided_disposition is not null then l.decided_work_order_id
         when l.config_rule ->> 'disposition' = 'material' then
           (select case when count(*) = 1 then (array_agg(w.id))[1] end
              from public.work_orders w
             where w.job_id = l.job_id and w.kind = 'trade' and w.voided_at is null
               and w.trade = l.config_rule ->> 'trade')
    end as trade_work_order_id
  from lines l
)
select r.job_id, r.org_id, r.estimate_id, r.estimate_status, r.estimate_line_item_id,
       r.description, r.quantity, r.unit, r.sort_order, r.scope_key,
       r.disposition, r.disposition_source, r.trade_work_order_id,
       case when r.disposition <> 'material' then 'not_applicable'
            when r.trade_work_order_id is null then 'undecided'
            when exists (select 1 from public.work_orders w
                          where w.id = r.trade_work_order_id and w.voided_at is not null) then 'trade_voided'
            else 'decided' end as trade_state,
       m.id as material_item_id, m.work_order_id as material_work_order_id,
       case
         when m.id is null and r.item_removed_at is not null then 'removed_by_human'
         when m.id is null and r.disposition = 'material' and r.trade_work_order_id is not null then 'not_taken_off'
         when m.id is null then 'none'
         when r.disposition <> 'material' then 'item_without_material_decision'
         when m.work_order_id is distinct from r.trade_work_order_id then 'item_on_other_trade'
         when m.take_off_description is null then 'no_snapshot'
         when c.item_changed and c.line_changed then 'both_changed'
         when c.item_changed then 'edited_by_human'
         when c.line_changed then 'estimate_changed'
         else 'matches'
       end as item_state
from resolved r
left join public.material_items m on m.estimate_line_item_id = r.estimate_line_item_id
left join lateral (
  select
    (m.name, m.quantity, m.unit) is distinct from
      (btrim(m.take_off_description), m.take_off_quantity, nullif(btrim(m.take_off_unit), '')) as item_changed,
    (r.description, r.quantity, r.unit) is distinct from
      (m.take_off_description, m.take_off_quantity, m.take_off_unit) as line_changed
) c on true
union all
-- Taken-off materials whose line no longer resolves to their job's estimate: the line was
-- deleted (provenance set NULL, snapshot kept), or the job now points at another estimate.
select w.job_id, m.org_id, null::uuid, null::text, m.estimate_line_item_id,
       m.take_off_description, m.take_off_quantity, m.take_off_unit, m.sort_order, null::text,
       null::text, null::text, null::uuid, 'not_applicable',
       m.id, m.work_order_id,
       case when m.estimate_line_item_id is null then 'estimate_line_deleted'
            else 'line_not_on_job_estimate' end
from public.material_items m
join public.work_orders w on w.id = m.work_order_id
where (m.estimate_line_item_id is not null or m.take_off_description is not null)
  and not exists (
    select 1 from public.estimate_line_items e
    join public.jobs j on j.estimate_id = e.estimate_id and j.org_id = e.org_id
    where e.id = m.estimate_line_item_id and j.id = w.job_id);

revoke all on table public.take_off_lines from anon;
revoke insert, update, delete, truncate, references, trigger on table public.take_off_lines from authenticated;
grant select on table public.take_off_lines to authenticated;

-- ---------------------------------------------------------------------------------------
-- 6. The table refuses what the functions refuse (condition 5)
-- ---------------------------------------------------------------------------------------
create function public.material_items_take_off_guard()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
declare v_disp text; v_trade uuid;
begin
  -- Nothing about provenance moved: keep what was taken off; a writer cannot set it.
  if tg_op = 'UPDATE'
     and new.estimate_line_item_id is not distinct from old.estimate_line_item_id
     and new.work_order_id is not distinct from old.work_order_id then
    new.take_off_description := old.take_off_description;
    new.take_off_quantity := old.take_off_quantity;
    new.take_off_unit := old.take_off_unit;
    return new;
  end if;

  if new.estimate_line_item_id is null then
    if tg_op = 'INSERT' then
      -- a hand-added material: nothing was taken off
      new.take_off_description := null; new.take_off_quantity := null; new.take_off_unit := null;
    else
      -- provenance removed (line deleted, or detached): keep what was taken off
      new.take_off_description := old.take_off_description;
      new.take_off_quantity := old.take_off_quantity;
      new.take_off_unit := old.take_off_unit;
    end if;
    return new;
  end if;

  select t.disposition, t.trade_work_order_id into v_disp, v_trade
  from public.take_off_lines t
  where t.estimate_line_item_id = new.estimate_line_item_id and t.estimate_status is not null
  limit 1;

  if v_disp is null then
    raise exception 'estimate line % is not on a job''s estimate — a material cannot be taken off from it', new.estimate_line_item_id;
  elsif v_disp = 'undecided' then
    raise exception 'estimate line % is UNDECIDED for take-off — decide whether it is material before a material item is created from it', new.estimate_line_item_id;
  elsif v_disp = 'not_material' then
    raise exception 'estimate line % is decided NOT MATERIAL — a material item cannot be created from it', new.estimate_line_item_id;
  elsif v_trade is null then
    raise exception 'estimate line % is material but NO TRADE is decided for it — choose the trade first', new.estimate_line_item_id;
  elsif v_trade <> new.work_order_id then
    raise exception 'the take-off decision puts estimate line % on a different trade work order', new.estimate_line_item_id;
  end if;

  if tg_op = 'UPDATE' and new.estimate_line_item_id is not distinct from old.estimate_line_item_id then
    -- a move between trades: the snapshot stays what the line said at take-off
    new.take_off_description := old.take_off_description;
    new.take_off_quantity := old.take_off_quantity;
    new.take_off_unit := old.take_off_unit;
  else
    select e.description, e.quantity, e.unit
      into new.take_off_description, new.take_off_quantity, new.take_off_unit
    from public.estimate_line_items e where e.id = new.estimate_line_item_id;
  end if;
  return new;
end;
$function$;

create trigger material_items_take_off_guard
  before insert or update on public.material_items
  for each row execute function public.material_items_take_off_guard();

-- A human deleting a taken-off material is a decision that it should not exist. Recorded at
-- the table, so a delete by any path is remembered and no run re-creates the item.
create function public.material_items_take_off_removed()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
begin
  if old.estimate_line_item_id is null then
    return old;
  end if;
  insert into public.take_off_decisions
    (estimate_line_item_id, org_id, disposition, work_order_id, source, decided_by, decided_at, item_removed_at, item_removed_by)
  select old.estimate_line_item_id, e.org_id, 'material', null, 'human', auth.uid(), now(), now(), auth.uid()
  from public.estimate_line_items e
  join public.jobs j on j.estimate_id = e.estimate_id and j.org_id = e.org_id
  where e.id = old.estimate_line_item_id
  on conflict (estimate_line_item_id) do update
    set item_removed_at = now(), item_removed_by = auth.uid();
  return old;
end;
$function$;

create trigger material_items_take_off_removed
  after delete on public.material_items
  for each row execute function public.material_items_take_off_removed();

-- ---------------------------------------------------------------------------------------
-- 7. The human resolution
-- ---------------------------------------------------------------------------------------
create function public.set_take_off_decision(
  p_estimate_line_item_id uuid, p_disposition text, p_work_order_id uuid default null
)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_org uuid; v_estimate uuid; v_job uuid;
  v_item uuid; v_item_wo uuid; v_item_trade text;
begin
  select e.org_id, e.estimate_id into v_org, v_estimate
  from public.estimate_line_items e where e.id = p_estimate_line_item_id;

  if v_org is null or v_org not in (select my_org_ids()) then
    raise exception 'estimate line not found or not accessible: %', p_estimate_line_item_id;
  end if;
  if not coalesce(public.can_view_financials(v_org), false) then
    raise exception 'a take-off decision reads the estimate''s priced line items, and your role cannot view financials';
  end if;
  if not coalesce(public.has_capability(v_org, 'view_estimates'), false) then
    raise exception 'a take-off decision reads the estimate''s line items, and your role cannot view estimates';
  end if;

  if p_disposition is null or p_disposition not in ('material', 'not_material', 'undecided') then
    raise exception 'choose material, not_material or undecided for this line — "%" is not a take-off decision', coalesce(p_disposition, 'nothing');
  end if;

  select j.id into v_job from public.jobs j where j.estimate_id = v_estimate and j.org_id = v_org;
  if v_job is null then
    raise exception 'this estimate line is not on a job''s estimate — take-off decisions are made on a job';
  end if;

  if p_disposition <> 'material' and p_work_order_id is not null then
    raise exception 'a line that is not decided material has no trade — leave the work order empty';
  end if;

  select m.id, m.work_order_id, w.trade into v_item, v_item_wo, v_item_trade
  from public.material_items m join public.work_orders w on w.id = m.work_order_id
  where m.estimate_line_item_id = p_estimate_line_item_id;

  if v_item is not null and p_disposition <> 'material' then
    raise exception 'a material item already exists for this line on trade "%" — delete that material first, then change the decision', coalesce(v_item_trade, 'trade');
  end if;
  if v_item is not null and p_work_order_id is null then
    raise exception 'a material item already exists for this line on trade "%" — choose the trade it belongs on (it will move there), or delete it first', coalesce(v_item_trade, 'trade');
  end if;

  if p_disposition = 'undecided' then
    delete from public.take_off_decisions where estimate_line_item_id = p_estimate_line_item_id;
  else
    insert into public.take_off_decisions
      (estimate_line_item_id, org_id, disposition, work_order_id, source, decided_by, decided_at)
    values (p_estimate_line_item_id, v_org, p_disposition, p_work_order_id, 'human', auth.uid(), now())
    on conflict (estimate_line_item_id) do update
      set disposition = excluded.disposition,
          work_order_id = excluded.work_order_id,
          source = 'human',
          decided_by = excluded.decided_by,
          decided_at = now(),
          -- a deletion stays remembered while the line stays material; only a take-off tick clears it
          item_removed_at = case when excluded.disposition = 'material' then take_off_decisions.item_removed_at end,
          item_removed_by = case when excluded.disposition = 'material' then take_off_decisions.item_removed_by end;

    if v_item is not null and v_item_wo is distinct from p_work_order_id then
      update public.material_items set work_order_id = p_work_order_id, updated_at = now() where id = v_item;
    end if;
  end if;

  return (select to_jsonb(t) from public.take_off_lines t
          where t.estimate_line_item_id = p_estimate_line_item_id and t.estimate_status is not null);
end;
$function$;

-- ---------------------------------------------------------------------------------------
-- 8. The run (conditions 3 and 4: creates only what is decided and missing; never updates,
--    never re-creates a removed material)
-- ---------------------------------------------------------------------------------------
create function public.materialize_take_off(p_job_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_org uuid; v_status text; v_created int := 0; v_by_trade jsonb; v_trade record;
  v_master uuid; v_sign timestamptz; v_actor uuid; v_counts jsonb;
begin
  select j.org_id, e.status into v_org, v_status
  from public.jobs j join public.estimates e on e.id = j.estimate_id
  where j.id = p_job_id;

  if v_org is null or v_org not in (select my_org_ids()) then
    raise exception 'job not found or not accessible: %', p_job_id;
  end if;
  if not coalesce(public.can_view_financials(v_org), false) then
    raise exception 'a take-off reads the estimate''s priced line items, and your role cannot view financials';
  end if;
  if not coalesce(public.has_capability(v_org, 'view_estimates'), false) then
    raise exception 'a take-off reads the estimate''s line items, and your role cannot view estimates';
  end if;
  if v_status is distinct from 'signed' then
    raise exception 'this job''s estimate is %, not signed — a take-off runs from a signed estimate', coalesce(v_status, 'missing');
  end if;

  with todo as (
    select t.estimate_line_item_id, t.trade_work_order_id, e.description, e.quantity, e.unit, e.product_id,
           row_number() over (partition by t.trade_work_order_id order by e.sort_order, e.id) as rn
    from public.take_off_lines t
    join public.estimate_line_items e on e.id = t.estimate_line_item_id
    where t.job_id = p_job_id and t.estimate_status is not null
      and t.disposition = 'material' and t.trade_state = 'decided' and t.item_state = 'not_taken_off'
  ), ins as (
    insert into public.material_items
      (org_id, work_order_id, name, quantity, unit, product_id, estimate_line_item_id, sort_order)
    select v_org, todo.trade_work_order_id, todo.description, todo.quantity, todo.unit, todo.product_id,
           todo.estimate_line_item_id,
           coalesce((select max(m.sort_order) from public.material_items m
                      where m.work_order_id = todo.trade_work_order_id), -1) + todo.rn
    from todo
    on conflict (estimate_line_item_id) where estimate_line_item_id is not null do nothing
    returning work_order_id
  )
  select coalesce(jsonb_object_agg(x.work_order_id, x.n), '{}'::jsonb) into v_by_trade
  from (select work_order_id, count(*) as n from ins group by work_order_id) x;

  for v_trade in select key::uuid as work_order_id, value::int as n from jsonb_each_text(v_by_trade) loop
    v_created := v_created + v_trade.n;
    select s.master_id, s.sign_off_at into v_master, v_sign from public.job_master_sign_off(v_trade.work_order_id) s;
    if v_sign is not null then
      select id into v_actor from public.profiles where id = auth.uid();
      insert into public.work_order_activity (work_order_id, org_id, action, to_value, actor_id)
      values (v_master, v_org, 'material_added_after_signoff',
              format('take-off: %s material(s) (%s)', v_trade.n,
                     coalesce((select trade from public.work_orders where id = v_trade.work_order_id), 'trade')),
              v_actor);
    end if;
  end loop;

  select jsonb_build_object(
    'job_id', p_job_id,
    'created', v_created,
    'lines_on_estimate', count(*) filter (where estimate_status is not null),
    'undecided', count(*) filter (where disposition = 'undecided'),
    'not_material', count(*) filter (where disposition = 'not_material'),
    'material', count(*) filter (where disposition = 'material'),
    'material_trade_undecided', count(*) filter (where disposition = 'material' and trade_state = 'undecided'),
    'material_trade_voided', count(*) filter (where trade_state = 'trade_voided'),
    'removed_by_human', count(*) filter (where item_state = 'removed_by_human'),
    'matches', count(*) filter (where item_state = 'matches'),
    'edited_by_human', count(*) filter (where item_state = 'edited_by_human'),
    'estimate_changed', count(*) filter (where item_state = 'estimate_changed'),
    'both_changed', count(*) filter (where item_state = 'both_changed'),
    'no_snapshot', count(*) filter (where item_state = 'no_snapshot'),
    'item_on_other_trade', count(*) filter (where item_state = 'item_on_other_trade'),
    'item_without_material_decision', count(*) filter (where item_state = 'item_without_material_decision'),
    'line_gone', count(*) filter (where item_state in ('estimate_line_deleted', 'line_not_on_job_estimate')))
  into v_counts
  from public.take_off_lines where job_id = p_job_id;

  return v_counts;
end;
$function$;

-- ---------------------------------------------------------------------------------------
-- 9. generate_take_off: same signature; a tick is a human decision, recorded first
-- ---------------------------------------------------------------------------------------
create or replace function public.generate_take_off(p_work_order_id uuid, p_estimate_line_item_ids uuid[])
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_org_id        uuid;
  v_kind          text;
  v_job_id        uuid;
  v_estimate_id   uuid;
  v_trade         text;
  v_ids           uuid[];
  v_requested     int;
  v_valid         int;
  v_conflicts     int;
  v_created       int;
  v_next_sort     int;
  v_live_trades   int;
  v_with_takeoff  int;
  v_master_id     uuid;
  v_sign_off_at   timestamptz;
  v_actor_id      uuid;
begin
  -- ---- existence + org, before anything is disclosed ----------------------
  select w.org_id, w.kind, w.job_id, w.estimate_id
    into v_org_id, v_kind, v_job_id, v_estimate_id
  from public.work_orders w
  where w.id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  -- ---- the crew gate, at the RPC layer (unchanged) -------------------------
  if not coalesce(public.can_view_financials(v_org_id), false) then
    raise exception 'a take-off reads the estimate''s priced line items, and your role cannot view financials';
  end if;

  if not coalesce(public.has_capability(v_org_id, 'view_estimates'), false) then
    raise exception 'a take-off reads the estimate''s line items, and your role cannot view estimates';
  end if;

  -- ---- CLAUSE (b): the master is not a destination (unchanged) -------------
  if v_kind = 'master' then
    select count(*) into v_live_trades
    from public.work_orders t
    where t.job_id = v_job_id and t.kind = 'trade' and t.voided_at is null;

    if v_live_trades = 0 then
      raise exception 'this job has 0 trade work orders, so a take-off has nowhere to land — materials attach to a trade. Create trades first, then open a trade and run the take-off there.';
    end if;

    raise exception 'a take-off runs from a trade, not from the master — this job has % live trade work order(s). Open the trade these materials belong to and run it there.', v_live_trades;
  end if;

  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');

  select w.trade into v_trade
  from public.work_orders w where w.id = p_work_order_id;

  -- ---- the selection (unchanged) -------------------------------------------
  select coalesce(array_agg(distinct x), '{}'::uuid[]) into v_ids
  from unnest(p_estimate_line_item_ids) as t(x)
  where x is not null;

  v_requested := coalesce(array_length(v_ids, 1), 0);

  if v_requested = 0 then
    raise exception 'no estimate line items were selected — tick the lines that belong to this trade, then run the take-off';
  end if;

  select count(*) into v_valid
  from public.estimate_line_items e
  where e.id = any(v_ids)
    and e.org_id = v_org_id
    and e.estimate_id = v_estimate_id;

  if v_valid <> v_requested then
    raise exception '% of % selected line items are not on this job''s estimate — nothing was taken off',
      v_requested - v_valid, v_requested;
  end if;

  -- ---- NEW: a tick does not silently overrule another human's decision ----
  -- A line a human decided NOT material, or decided onto ANOTHER trade, or whose material
  -- already sits on another trade, is refused with its count and nothing is taken off.
  -- (Before 2026-09-14 the same line ticked on a second trade became a second material.)
  select count(*) into v_conflicts
  from public.take_off_lines t
  where t.estimate_line_item_id = any(v_ids) and t.estimate_status is not null
    and ( (t.disposition_source in ('human', 'generate_take_off', 'backfill') and t.disposition = 'not_material')
       or (t.disposition_source in ('human', 'generate_take_off', 'backfill') and t.disposition = 'material'
           and t.trade_work_order_id is not null and t.trade_work_order_id <> p_work_order_id)
       or (t.material_item_id is not null and t.material_work_order_id <> p_work_order_id) );

  if v_conflicts > 0 then
    raise exception '% of % selected line items are already decided for take-off elsewhere (not material, or on another trade) — change their decision first; nothing was taken off',
      v_conflicts, v_requested;
  end if;

  -- ---- NEW: the tick IS the human decision, recorded before the insert -----
  -- An explicit tick also clears a remembered deletion: taking the line off again is the
  -- human saying the material should exist.
  insert into public.take_off_decisions
    (estimate_line_item_id, org_id, disposition, work_order_id, source, decided_by, decided_at)
  select x, v_org_id, 'material', p_work_order_id, 'generate_take_off', auth.uid(), now()
  from unnest(v_ids) as x
  on conflict (estimate_line_item_id) do update
    set disposition = 'material',
        work_order_id = excluded.work_order_id,
        source = 'generate_take_off',
        decided_by = excluded.decided_by,
        decided_at = now(),
        item_removed_at = null,
        item_removed_by = null;

  -- ---- the insert ---------------------------------------------------------
  select coalesce(max(m.sort_order) + 1, 0) into v_next_sort
  from public.material_items m
  where m.work_order_id = p_work_order_id;

  -- NO MONEY CROSSES THIS BOUNDARY (unchanged).
  with src as (
    select e.id, e.description, e.quantity, e.unit, e.product_id,
           row_number() over (order by e.sort_order, e.id) - 1 as rn
    from public.estimate_line_items e
    where e.id = any(v_ids)
  ),
  ins as (
    insert into public.material_items
      (org_id, work_order_id, name, quantity, unit, product_id,
       estimate_line_item_id, sort_order)
    select v_org_id, p_work_order_id, src.description, src.quantity, src.unit,
           src.product_id, src.id, v_next_sort + src.rn
    from src
    -- IDEMPOTENCE, now across every trade: one material per estimate line.
    on conflict (estimate_line_item_id)
      where estimate_line_item_id is not null
    do nothing
    returning 1
  )
  select count(*) into v_created from ins;

  -- ---- audit parity with add_material_item (unchanged) ---------------------
  select s.master_id, s.sign_off_at into v_master_id, v_sign_off_at
  from public.job_master_sign_off(p_work_order_id) s;

  if v_sign_off_at is not null and v_created > 0 then
    select id into v_actor_id from public.profiles where id = auth.uid();
    insert into public.work_order_activity (work_order_id, org_id, action, to_value, actor_id)
    values (v_master_id, v_org_id, 'material_added_after_signoff',
            format('take-off: %s material(s) (%s)', v_created, coalesce(v_trade, 'trade')),
            v_actor_id);
  end if;

  -- ---- CLAUSE (a)'s REPORTED FIGURE (unchanged) -----------------------------
  select count(*) into v_live_trades
  from public.work_orders t
  where t.job_id = v_job_id and t.kind = 'trade' and t.voided_at is null;

  select count(distinct m.work_order_id) into v_with_takeoff
  from public.material_items m
  join public.work_orders t on t.id = m.work_order_id
  where t.job_id = v_job_id
    and t.kind = 'trade'
    and t.voided_at is null
    and m.estimate_line_item_id is not null;

  return jsonb_build_object(
    'work_order_id',        p_work_order_id,
    'job_id',               v_job_id,
    'trade',                v_trade,
    'lines_requested',      v_requested,
    'created',              v_created,
    'skipped_existing',     v_requested - v_created,
    'trades_with_take_off', v_with_takeoff,
    'live_trade_count',     v_live_trades
  );
end;
$function$;

-- ---------------------------------------------------------------------------------------
-- 10. Grants — rule 7 per function; rule 8 per table/view
-- ---------------------------------------------------------------------------------------
revoke execute on function public.take_off_decisions_validate() from public, anon, authenticated;
revoke execute on function public.material_items_take_off_guard() from public, anon, authenticated;
revoke execute on function public.material_items_take_off_removed() from public, anon, authenticated;
revoke execute on function public.set_take_off_decision(uuid, text, uuid) from public, anon;
revoke execute on function public.materialize_take_off(uuid) from public, anon;
revoke execute on function public.generate_take_off(uuid, uuid[]) from public, anon;

-- Rule 3: never trust the success response.
do $$
begin
  if (select count(*) from public.material_items m
       where m.estimate_line_item_id is not null
         and not exists (select 1 from public.take_off_decisions d where d.estimate_line_item_id = m.estimate_line_item_id)) <> 0
    then raise exception 'a taken-off material has no decision after the backfill'; end if;
  if exists (select 1 from pg_indexes where indexname = 'material_items_take_off_uniq')
    then raise exception 'the per-trade unique index is still present'; end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.material_items'::regclass
       and tgname in ('material_items_take_off_guard', 'material_items_take_off_removed')) <> 2
    then raise exception 'material_items take-off triggers not attached'; end if;
end $$;