-- StructTech OS — 2026-08-29 policy pass. MIGRATION A of B.
--
-- FINDING. 49 StructTech-owned tables in `public` hold the full anon privilege
-- set `arwdDxtm`. RLS is on for every one of them, and every one is closed ONLY
-- because its policies' predicates call security-definer helpers (my_org_ids,
-- is_staff, is_platform_admin, has_capability, can_view_financials,
-- can_view_master_work_order, work_order_is_my_trade) that anon cannot EXECUTE.
-- All eight helpers were resolved to their bodies. All eight are sound. The
-- predicate was never the problem.
--
-- Rule 13 — name the thing that would have to change for this to open:
-- "somebody grants EXECUTE on my_org_ids() to anon." ONE grant on ONE unrelated
-- helper opens 49 tables at once. That is closed by accident, not by control.
-- `audit_leads` was not one of one. It was one of 49.
--
-- THIS IS THE 2026-08-20 MECHANISM RUN BACKWARDS. In August a REVOKE on
-- my_org_ids() took the Material Matrix storefront down. A GRANT on the same
-- function opens 49 of our tables at once. One statement, both directions,
-- opposite disasters.
--
-- Seven of the 49 have RLS on and ZERO policies (estimate_number_counters,
-- structtech_state, and the five migration_bmr_* raw PII tables). Those are
-- closed by the ABSENCE of a policy — rule 13's other form, "somebody adds one."
--
-- This migration makes the table grant the outer control, so closure no longer
-- depends on a helper's EXECUTE bit.
--
-- SCOPE. StructTech-owned tables only. The 15 wh_* tables, the wh_current_prices
-- view and the wh_order_number_seq sequence are Material Matrix's anon-facing
-- storefront read path and are DELIBERATELY NOT TOUCHED (8/20 precedent).
--
-- LIVE REVENUE PATH PRESERVED. audit.structtek.com posts its lead form into
-- public.audit_leads as anon. `revoke all` is followed by an explicit
-- `grant insert`, the only privilege that path uses — supabase-js `.insert()`
-- defaults to `return=minimal`, and `INSERT … RETURNING` already failed before
-- this migration (form 3, `permission denied for function my_org_ids`).
--
-- ROLLBACK: `grant all on table <t> to anon` over the same 49-table list,
-- plus recreating the client_roadmaps policy dropped at the foot of this file.

revoke all on table public.audit_leads from anon;
revoke all on table public.audits from anon;
revoke all on table public.check_ins from anon;
revoke all on table public.deal_activity from anon;
revoke all on table public.deal_notes from anon;
revoke all on table public.deals from anon;
revoke all on table public.engagement_checkins from anon;
revoke all on table public.engagement_levels from anon;
revoke all on table public.engagement_milestones from anon;
revoke all on table public.engagements from anon;
revoke all on table public.estimate_line_items from anon;
revoke all on table public.estimate_number_counters from anon;
revoke all on table public.estimates from anon;
revoke all on table public.follow_ups from anon;
revoke all on table public.jobs from anon;
revoke all on table public.lead_activity from anon;
revoke all on table public.lead_appointments from anon;
revoke all on table public.lead_notes from anon;
revoke all on table public.leads from anon;
revoke all on table public.migration_bmr_activity_raw from anon;
revoke all on table public.migration_bmr_id_map from anon;
revoke all on table public.migration_bmr_leads_raw from anon;
revoke all on table public.migration_bmr_notes_raw from anon;
revoke all on table public.migration_bmr_users_raw from anon;
revoke all on table public.org_invites from anon;
revoke all on table public.org_invoices from anon;
revoke all on table public.org_members from anon;
revoke all on table public.org_systems from anon;
revoke all on table public.organizations from anon;
revoke all on table public.pipeline_invites from anon;
revoke all on table public.production_packets from anon;
revoke all on table public.profiles from anon;
revoke all on table public.proposals from anon;
revoke all on table public.prospects from anon;
revoke all on table public.roadmap_items from anon;
revoke all on table public.roadmap_projects from anon;
revoke all on table public.schedule_blocks from anon;
revoke all on table public.signatures from anon;
revoke all on table public.staff_invites from anon;
revoke all on table public.staff_users from anon;
revoke all on table public.structtech_state from anon;
revoke all on table public.tenant_modules from anon;
revoke all on table public.ticket_messages from anon;
revoke all on table public.tickets from anon;
revoke all on table public.tracker_items from anon;
revoke all on table public.tracker_projects from anon;
revoke all on table public.work_order_activity from anon;
revoke all on table public.work_order_agreements from anon;
revoke all on table public.work_orders from anon;

-- The one anon privilege this build actually uses.
grant insert on table public.audit_leads to anon;

-- Dangling anon-permissive policy left behind by the 8/28 P0. `client_roadmaps`
-- has held no anon grant since 20260828165739, so this policy is inert TODAY —
-- which is exactly rule 13's point. Its predicate is `with check (true)`, so a
-- future `grant insert … to anon` would reopen anonymous writes with nothing
-- else standing in the way. Removed, not relied upon.
drop policy if exists "insert roadmap" on public.client_roadmaps;
