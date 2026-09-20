-- ROLLBACK for 20260919 daily_objective_and_acknowledgment. Removes A4.1 and A4.5 entirely, including the
-- objectives and acknowledgments recorded so far — those rows are not recoverable afterwards.
drop function if exists public.fetch_work_order_brief(uuid);
drop function if exists public.acknowledge_work_order(uuid);
drop function if exists public.clear_work_order_objective(uuid, date);
drop function if exists public.set_work_order_objective(uuid, text, date);
drop function if exists public.work_order_version(uuid);
drop table if exists public.work_order_acknowledgments;
drop table if exists public.work_order_objectives;
