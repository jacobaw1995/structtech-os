-- RULING (d), 2026-09-12, Jacob: a direct write into schedule_blocks that stores
-- ready_by_conflict = false while bypassing the stage gating is CLOSED AT THE TABLE.
-- Track S · 2026-09-13. Rollback: supabase/rollbacks/20260913_schedule_gate_every_update_rollback.sql
--
-- WHAT 20260913012939 collapsed_state ALREADY CLOSED, re-probed today as `authenticated`
-- with the BMR owner's JWT: a direct INSERT claiming ready_by_conflict = false is stored
-- as TRUE with gating off and REFUSED with gating on.
--
-- WHAT IT LEFT OPEN, PROVED TODAY BEFORE THIS RAN. The trigger fired only on
-- `UPDATE OF start_date, work_order_id`. A direct
--   update schedule_blocks set ready_by_conflict = false, ready_by_conflict_reason = null
-- touching neither column updated 1 row and STORED false on a block that starts
-- 2026-10-05 against materials ready 2026-10-20 — with enforce_stage_gating OFF and ON.
-- Same lie, different command. The column list was the hole.
--
-- THE FIX: the trigger fires on EVERY insert and EVERY update, so the fact is recomputed
-- on any write and a writer can never set it. Consequence, stated because it narrows:
-- under gating ON, ANY direct update of a block that is in conflict is refused — a crew
-- rename included. That matches update_schedule_block, which recomputes from the
-- coalesced start date and refuses the same case. Under gating OFF, any touch refreshes a
-- stale fact (the stored conflict is otherwise not recomputed when materials move).
--
-- BEFORE-MEASUREMENT (live, 2026-09-13): schedule_blocks holds 1 row; rows with
-- ready_by_conflict = false: 0. Direct-path vs RPC-path authorship of existing rows:
-- CANNOT BE TOLD FROM THE DATABASE — the table has no created_by, no activity row is
-- written for schedule blocks, created_at = updated_at, and both paths insert the same
-- columns. The one row's provenance (add_schedule_block, 2026-09-10) is known only from
-- the session record outside the database.
-- REACH (live memberships, 2026-09-13): 5 memberships · 4 hold `schedule` · 2 can
-- actually direct-write today (both Brothers Metal Roofing; StructTech and Material Matrix
-- hold no trade work orders, so work_order_is_my_trade() fails for them).
--
-- The trigger FUNCTION is unchanged (SECURITY DEFINER, EXECUTE revoked from public, anon,
-- authenticated on 2026-09-12); only its firing condition changes.

drop trigger if exists schedule_blocks_ready_by_gate on public.schedule_blocks;

create trigger schedule_blocks_ready_by_gate
  before insert or update on public.schedule_blocks
  for each row execute function public.schedule_blocks_ready_by_gate();

-- Rule 3: never trust the success response.
do $$
begin
  if (select pg_get_triggerdef(t.oid) from pg_trigger t
      where t.tgrelid = 'public.schedule_blocks'::regclass and t.tgname = 'schedule_blocks_ready_by_gate')
     is distinct from 'CREATE TRIGGER schedule_blocks_ready_by_gate BEFORE INSERT OR UPDATE ON public.schedule_blocks FOR EACH ROW EXECUTE FUNCTION schedule_blocks_ready_by_gate()'
  then raise exception 'schedule gate trigger is not firing on every insert and update'; end if;
end $$;