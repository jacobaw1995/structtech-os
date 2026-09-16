-- INVISIBILITY IS NOT ABSENCE — take_off_lines. Track S · 2026-09-15.
-- Rollback: supabase/rollbacks/20260915_take_off_lines_invisible_rollback.sql
--
-- MEASURED BY TRACK U, RE-PROVED HERE BEFORE THIS RAN (rolled back): as `authenticated`, a synthetic
-- `field` member of Brothers Metal Roofing sees 0 estimate lines and 1 material item, and take_off_lines
-- labels that material `line_not_on_job_estimate` — while the owner, on the same row, sees `no_snapshot`.
-- A confident answer to the wrong question: the line is on the estimate; this caller cannot see it.
--
-- THE FIX: the orphan branch now says `line_not_visible` whenever the caller lacks view_financials or
-- view_estimates — the two capabilities the estimate_line_items policies require — before it concludes
-- anything from its NOT EXISTS. `estimate_line_deleted` stays first: a NULL provenance on the material row
-- is a fact about a row the caller CAN see. Same column list; grants unchanged.

create or replace view public.take_off_lines with (security_invoker = true) as
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
            -- INVISIBILITY IS NOT ABSENCE (2026-09-15). The NOT EXISTS below runs as the caller, and a
            -- caller without view_financials + view_estimates sees NO estimate lines at all, so it would
            -- report every taken-off material's line as not on the estimate. Branch on the capability,
            -- never on the empty read (§7.1 rule 5).
            when not (coalesce(public.can_view_financials(m.org_id), false)
                      and coalesce(public.has_capability(m.org_id, 'view_estimates'), false)) then 'line_not_visible'
            else 'line_not_on_job_estimate' end
from public.material_items m
join public.work_orders w on w.id = m.work_order_id
where (m.estimate_line_item_id is not null or m.take_off_description is not null)
  and not exists (
    select 1 from public.estimate_line_items e
    join public.jobs j on j.estimate_id = e.estimate_id and j.org_id = e.org_id
    where e.id = m.estimate_line_item_id and j.id = w.job_id);

revoke all on table public.take_off_lines from anon;
revoke insert, update, delete, truncate, references, trigger, maintain on table public.take_off_lines from authenticated;