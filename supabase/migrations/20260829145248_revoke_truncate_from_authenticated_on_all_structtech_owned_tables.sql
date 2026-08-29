-- StructTech OS — 2026-08-29. THE TRUNCATE GRANT.
--
-- Class found by Material Matrix on their own side as a P0, on `authenticated`
-- — the role NEITHER PROJECT HAD AUDITED. 52 of 80 tables in `public` were
-- TRUNCATE-able by `authenticated`. All 52 are StructTech's; zero are MM's.
-- They include `deals` (198 rows), `estimates`, `jobs`, `work_orders`,
-- `organizations`, `org_members`, `leads`, `products`, `client_roadmaps`, and
-- all five `migration_bmr_*_raw` PII tables.
--
-- RLS DOES NOT APPLY TO TRUNCATE. Every restrictive policy A1.5 and A2.0 built
-- is irrelevant to it. This is not a read exposure — it is a DESTRUCTION
-- exposure, and it is the first thing all month that RLS structurally cannot
-- mediate.
--
-- PROVED, NOT ARGUED, before this migration: as `authenticated` with NO JWT at
-- all — so `auth.uid()` is NULL and the caller is the LEAST privileged
-- authenticated identity that can exist — `truncate public.migration_bmr_id_map`
-- destroyed all 948 rows. Run inside a transaction and rolled back; 948 rows
-- confirmed restored. RLS was fully enabled and every policy intact throughout.
--
-- VECTOR: NOT ESTABLISHED, AND SAID PLAINLY RATHER THAN ASSUMED EITHER WAY.
-- Against this codebase and schema no browser-reachable path was found:
-- `authenticated` is NOLOGIN (only `authenticator` connects, then SET ROLEs);
-- PostgREST exposes no TRUNCATE verb; NO function in `public` contains TRUNCATE;
-- NO function reachable by `authenticated` contains dynamic SQL; and `src/`
-- holds zero SQL truncate (8 grep hits, all Tailwind `truncate` classes).
-- MM found theirs with a real signed-in persona and called it P0, so they may
-- hold a path we do not. THE MISSING VECTOR DID NOT GATE THE FIX.
--
-- SCOPE. TRUNCATE ONLY. `authenticated`'s SELECT/INSERT/UPDATE/DELETE are
-- DELIBERATELY UNTOUCHED — on this role those grants are LOAD-BEARING. Every
-- user of this build runs as `authenticated`, and the barrier there is
-- INTENTIONALLY RLS. Revoking them would break the application, not an attacker.
-- Rule 7's carve-out test, applied to a privilege rather than to a function.
--
-- ROLLBACK: `grant truncate on table <t> to authenticated` over the same list.

revoke truncate on table public.audit_leads from authenticated;
revoke truncate on table public.audits from authenticated;
revoke truncate on table public.check_ins from authenticated;
revoke truncate on table public.client_roadmaps from authenticated;
revoke truncate on table public.deal_activity from authenticated;
revoke truncate on table public.deal_notes from authenticated;
revoke truncate on table public.deals from authenticated;
revoke truncate on table public.engagement_checkins from authenticated;
revoke truncate on table public.engagement_levels from authenticated;
revoke truncate on table public.engagement_milestones from authenticated;
revoke truncate on table public.engagements from authenticated;
revoke truncate on table public.estimate_line_items from authenticated;
revoke truncate on table public.estimate_number_counters from authenticated;
revoke truncate on table public.estimates from authenticated;
revoke truncate on table public.follow_ups from authenticated;
revoke truncate on table public.jobs from authenticated;
revoke truncate on table public.lead_activity from authenticated;
revoke truncate on table public.lead_appointments from authenticated;
revoke truncate on table public.lead_notes from authenticated;
revoke truncate on table public.leads from authenticated;
revoke truncate on table public.material_items from authenticated;
revoke truncate on table public.migration_bmr_activity_raw from authenticated;
revoke truncate on table public.migration_bmr_id_map from authenticated;
revoke truncate on table public.migration_bmr_leads_raw from authenticated;
revoke truncate on table public.migration_bmr_notes_raw from authenticated;
revoke truncate on table public.migration_bmr_users_raw from authenticated;
revoke truncate on table public.org_invites from authenticated;
revoke truncate on table public.org_invoices from authenticated;
revoke truncate on table public.org_members from authenticated;
revoke truncate on table public.org_systems from authenticated;
revoke truncate on table public.organizations from authenticated;
revoke truncate on table public.pipeline_invites from authenticated;
revoke truncate on table public.production_packets from authenticated;
revoke truncate on table public.products from authenticated;
revoke truncate on table public.profiles from authenticated;
revoke truncate on table public.proposals from authenticated;
revoke truncate on table public.prospects from authenticated;
revoke truncate on table public.roadmap_items from authenticated;
revoke truncate on table public.roadmap_projects from authenticated;
revoke truncate on table public.schedule_blocks from authenticated;
revoke truncate on table public.signatures from authenticated;
revoke truncate on table public.staff_invites from authenticated;
revoke truncate on table public.staff_users from authenticated;
revoke truncate on table public.structtech_state from authenticated;
revoke truncate on table public.tenant_modules from authenticated;
revoke truncate on table public.ticket_messages from authenticated;
revoke truncate on table public.tickets from authenticated;
revoke truncate on table public.tracker_items from authenticated;
revoke truncate on table public.tracker_projects from authenticated;
revoke truncate on table public.work_order_activity from authenticated;
revoke truncate on table public.work_order_agreements from authenticated;
revoke truncate on table public.work_orders from authenticated;
