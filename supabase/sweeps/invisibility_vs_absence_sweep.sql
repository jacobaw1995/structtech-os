-- =============================================================================
-- INVISIBILITY-VS-ABSENCE SWEEP — "a view that cannot see a row must not report that the row is absent".
-- Track S · first run 2026-09-15. READ-ONLY. Safe against production.
--
-- THE RULE (controller, 2026-09-15; the database form of §7.1 rule 5): ANY VIEW BRANCH USING NOT EXISTS —
-- or a LEFT JOIN … IS NULL, or a count — AGAINST A TABLE THE CALLER MAY NOT SEE WILL REPORT ABSENCE WHEN IT
-- MEANS INVISIBILITY. A security_invoker view runs its absence tests AS THE CALLER.
-- Found by Track U on take_off_lines: a field member (0 estimate lines visible, 1 material item visible)
-- was told `line_not_on_job_estimate`; the owner, on the same row, `no_snapshot`. Fixed in 20260915221254
-- by branching on the capability before the NOT EXISTS (`line_not_visible`).
--
-- THE INSTRUMENT NARROWS; THE GRADE IS FROM READING EACH ABSENCE TEST AGAINST THE POLICIES OF THE TABLE IT
-- READS. A test is SAFE when every caller who can see the view's row can also see the table the test reads.
--
-- INSTRUMENT TRAP, FOUND ON THE FIRST RUN: pg_get_viewdef() renders `not exists (…)` as `NOT (EXISTS (…))`,
-- so a regex for `not\s+exists` matched ZERO views while one had the defect. Match `NOT \(?\s*EXISTS`.
--
-- FIRST RUN, 2026-09-15 — DENOMINATOR: 3 views in public; 2 owned (wh_current_prices is Material Matrix's).
-- Both are security_invoker and both contain absence inferences. 7 absence tests graded:
--   take_off_lines
--     FIXED  orphan branch — NOT EXISTS estimate_line_items ⋈ jobs (estimate_line_items needs view_estimates
--            AND view_financials; material_items does not) → now `line_not_visible` for such a caller
--     SAFE   LEFT JOIN take_off_decisions IS NULL → 'undecided' (decisions need view_estimates; the base row
--            is an estimate line, which needs more — whoever sees the row sees its decision)
--     SAFE   LEFT JOIN material_items IS NULL → 'none' / 'not_taken_off' (material_items: any member)
--     SAFE   EXISTS work_orders voided → 'trade_voided' (the decided work order is validated as a trade;
--            the only restrictive work_orders policy hides masters)
--     SAFE   tenant_modules config lookup (member read)
--   crew_assignment_states
--     SAFE   LEFT JOIN crew_memberships/crew_people count → 'crew_has_no_members' (member read, same tenant)
--     SAFE   LEFT JOIN schedule_blocks IS NULL → 'not_scheduled'; EXISTS crew_person_unavailability
--            (both member read)
--   UNGRADED 0.
-- NOT IN THIS POPULATION: SECURITY INVOKER functions. Every function in public that reads an RLS table to
-- decide absence today is SECURITY DEFINER (it sees everything), so it cannot misreport invisibility — but
-- that is a fact about today's functions, and a future invoker function joins this sweep.
-- =============================================================================

with v as (
  select c.oid, c.relname, coalesce(c.reloptions::text, '') as opts, pg_get_viewdef(c.oid) as def
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('v','m') and c.relname !~ '^wh_'
), deps as (
  select distinct v.relname as view_name, t.relname as table_name, t.oid as toid
  from v join pg_rewrite rw on rw.ev_class = v.oid
  join pg_depend d on d.objid = rw.oid
  join pg_class t on t.oid = d.refobjid
  where t.relkind = 'r'
)
select v.relname as view_name,
       v.opts ~ 'security_invoker=true' as runs_as_caller,
       v.def ~* 'NOT \(?\s*EXISTS' as has_not_exists,
       v.def ~* 'IS NULL' as has_is_null,
       v.def ~* '\mcount\(' as has_count,
       d.table_name as reads_table,
       (select string_agg(format('%s %s%s: %s', case when pol.polpermissive then 'permissive' else 'RESTRICTIVE' end,
                                 pol.polcmd, '', pg_get_expr(pol.polqual, pol.polrelid)), ' | ')
          from pg_policy pol where pol.polrelid = d.toid and pol.polcmd in ('r','*')) as select_policies
from v join deps d on d.view_name = v.relname
order by v.relname, d.table_name;
