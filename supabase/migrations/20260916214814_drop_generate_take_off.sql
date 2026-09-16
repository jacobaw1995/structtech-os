-- ONE TAKE-OFF PATH: generate_take_off DROPPED. Track S · 2026-09-16.
-- Rollback: supabase/rollbacks/20260916_drop_generate_take_off_rollback.sql
--
-- Its removal condition (20260915005153): "dropped once no deployed caller remains". Measured 2026-09-16 at the
-- DEPLOYED commit 3d95251 (/api/health): 0 `rpc("generate_take_off"` calls in src/ or scripts/ — U-W1.17
-- removed TakeOffPanel's tick UI and the master card. The remaining text hits are comments, the generated types
-- and `case "generate_take_off"` in src/lib/takeoff/review.ts, which reads take_off_decisions.source (a stored
-- value, kept: history is not rewritten). 0 database functions reference it. materialize_take_off, fed by
-- set_take_off_decision, is the one path.
drop function public.generate_take_off(p_work_order_id uuid, p_estimate_line_item_ids uuid[]);
