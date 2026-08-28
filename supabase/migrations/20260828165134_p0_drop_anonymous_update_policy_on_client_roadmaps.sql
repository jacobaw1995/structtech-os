-- P0 INCIDENT — 2026-08-28. STEP 1 OF 5, APPLIED UNCONDITIONALLY AND FIRST.
--
-- `public.client_roadmaps` carried:
--     "update roadmap milestones"  UPDATE  roles={public}  USING true  WITH CHECK true
--
-- {public} includes `anon`, `anon` holds UPDATE on the table, and the anon key
-- ships in front-end JS. That is anonymous write to 9 rows of client business
-- data (client_name, company, trade, crew_size, score, risk_level,
-- revenue_leak_monthly, levels, status, lead_id, history).
--
-- Dropped WITHOUT first establishing callers, by controller decision: for a
-- write path this wide the exposure outranks the regression. If a client-facing
-- page offered milestone updates it can be broken for a day.
--
-- Reported by Material Matrix and verified by the controller against pg_policies
-- before this ran. Found by the other project — not by us, not by any advisor,
-- and not by Thursday's embed sweep, which read `src/` for dereferences and
-- never asked what the policies permitted.

drop policy "update roadmap milestones" on public.client_roadmaps;