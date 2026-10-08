-- ROLLBACK for 20261008180116_gate_three_ungated_definers.sql
-- Written BEFORE the migration. Track S, 2026-10-08.
--
-- Restores the `authenticated` EXECUTE grant on three SECURITY DEFINER functions.
-- Signatures copied VERBATIM from pg_get_function_identity_arguments() at
-- 2026-10-08 14:01 EDT (rule 2 — a retyped signature drops nothing and reports
-- success). No function body is touched by the migration or by this file; the
-- only thing that changes is reachability.
--
-- ⚠ RUNNING THIS RE-OPENS A CROSS-TENANT ORACLE. Measured 2026-10-08 as the real
-- Material Matrix member c62adbfc (who sees 0 BMR deals and 0 BMR work orders
-- through RLS): work_order_version returned a 64-char sha256 over BMR's pilot
-- work order; qc_photo_on_work_order answered; create_engagement_from_roadmap
-- reached its body and raised from inside it, distinguishing "deal not found"
-- from "no roadmap found" — an existence oracle, and it INSERTS when a roadmap
-- exists. Do not run this to fix an unrelated failure.
--
-- IF A LEGITIMATE CALLER BREAKS, THIS IS ALMOST CERTAINLY NOT THE CAUSE.
-- All five in-database callers are SECURITY DEFINER owned by `postgres`
-- (measured, not assumed) and therefore reach these three regardless of the
-- `authenticated` grant: deal_stage_side_effects, acknowledge_work_order,
-- fetch_work_order_brief, qc_items_guard_write, record_qc_item. There are ZERO
-- callers in src/. A failure after the migration is more likely a new caller
-- somebody added — in which case the fix is to decide whether that caller
-- should exist, not to restore the grant.

begin;

grant execute on function public.create_engagement_from_roadmap(p_deal_id uuid) to authenticated;
grant execute on function public.work_order_version(p_work_order_id uuid) to authenticated;
grant execute on function public.qc_photo_on_work_order(p_work_order_id uuid, p_photo_ref text) to authenticated;

-- VERIFY, do not trust the success response (rule 3).
select p.proname,
       coalesce(array_to_string(p.proacl,' | '),'(null)') as proacl,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated_can_execute,
       has_function_privilege('anon', p.oid, 'execute') as anon_can_execute
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('create_engagement_from_roadmap','work_order_version','qc_photo_on_work_order')
order by p.proname;

commit;
