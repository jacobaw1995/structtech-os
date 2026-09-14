-- ROLLBACK for 2026-09-13 schedule_blocks_gate_every_update (ruling d).
-- Captured from pg_get_triggerdef() on the LIVE database 2026-09-13 before the change.
-- The trigger FUNCTION public.schedule_blocks_ready_by_gate() is not modified by the
-- forward migration, so only the trigger definition is restored.
--
-- RESTORING THIS RE-OPENS: a direct UPDATE that sets ready_by_conflict = false (or edits
-- the reason) without touching start_date or work_order_id stores the lie, with the
-- tenant's enforce_stage_gating ON or OFF. Proved 2026-09-13 as the BMR owner.

drop trigger if exists schedule_blocks_ready_by_gate on public.schedule_blocks;
CREATE TRIGGER schedule_blocks_ready_by_gate BEFORE INSERT OR UPDATE OF start_date, work_order_id ON public.schedule_blocks FOR EACH ROW EXECUTE FUNCTION schedule_blocks_ready_by_gate();
