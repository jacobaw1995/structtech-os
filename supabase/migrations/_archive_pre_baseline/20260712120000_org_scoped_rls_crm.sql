-- StructTech OS — Week 2 Stage 0: org-scoped RLS on the 5 CRM tables
--
-- NOT APPLIED. Author-only migration file — ask before applying to the live
-- Supabase project, same as every other migration in this repo.
--
-- Context: `deals`, `deal_notes`, `deal_activity`, `follow_ups`, `audit_leads`
-- currently carry exactly one RLS policy each — `is_staff()`, a blanket
-- internal-staff bypass (`audit_leads` additionally has "Allow anon insert"
-- for the public scan form and "Allow authenticated read" for any logged-in
-- user — see the caveat below). None of them are scoped by org_id today.
-- The Week 1 foundation migration deliberately left this alone
-- ("migrating them to the membership model is a separate security
-- workstream, not part of Week 1"). Week 2's pipeline deliverable is that
-- workstream, for these 5 tables specifically.
--
-- This migration is purely ADDITIVE: every existing policy (is_staff(),
-- the anon-insert and authenticated-read policies on audit_leads) is left
-- untouched. New policies are added alongside, scoped by my_org_ids(), for
-- ordinary org members to read/write their own org's rows directly — the
-- same pattern the Week 1 foundation migration used for tenant_modules.
--
-- Ordering dependency: run this AFTER 20260711120100_backfill_org_id_crm.sql
-- (these tables have no org_id column until that migration runs).
--
-- Known gap this migration does NOT fix (by design — out of scope for a
-- mechanical backfill + RLS pass, tracked for the Week 2 Stage 1 trigger
-- rewrite instead): StructTech's own scan-sourced deals that haven't
-- produced an organization yet (i.e. every deal still `new_scan` at the
-- time of the backfill) get org_id = null from the backfill and so are
-- NOT visible under these new member policies — only via is_staff(), same
-- as before. Stage 1 updates auto_create_deal() to stamp org_id at
-- creation time going forward; closing that gap for the 4 existing
-- null-org StructTech deals is a Stage 1 decision, not smuggled in here.
--
-- Caveat worth flagging explicitly rather than leaving implicit: adding a
-- member-scoped SELECT policy to `audit_leads` has NO practical effect on
-- its own. `audit_leads` already carries "Allow authenticated read" with
-- qual = true — any authenticated user can already read every lead
-- regardless of org. RLS permissive policies are OR'd, so the org-scoped
-- policy added below is strictly narrower than that existing one and
-- changes nothing until/unless that broader policy is itself revisited.
-- Leaving that broader policy alone here on purpose — tightening it is a
-- real behavior change (SCOPE.md §11's "security workstream" territory),
-- not part of "add org-scoped policies alongside what's there."
--
-- Multiple permissive policies compose with OR, so none of this narrows
-- what is_staff() (or, on audit_leads, the anon/authenticated policies)
-- already allow — it only adds a second path in for ordinary org members.

-- ============================================================================
-- deals
-- ============================================================================
create policy "member read own deals"
  on public.deals for select
  using (org_id in (select my_org_ids()));

create policy "member insert own deals"
  on public.deals for insert
  with check (org_id in (select my_org_ids()));

create policy "member update own deals"
  on public.deals for update
  using (org_id in (select my_org_ids()))
  with check (org_id in (select my_org_ids()));

-- ============================================================================
-- deal_notes
-- ============================================================================
create policy "member read own deal_notes"
  on public.deal_notes for select
  using (org_id in (select my_org_ids()));

create policy "member insert own deal_notes"
  on public.deal_notes for insert
  with check (org_id in (select my_org_ids()));

create policy "member update own deal_notes"
  on public.deal_notes for update
  using (org_id in (select my_org_ids()))
  with check (org_id in (select my_org_ids()));

-- ============================================================================
-- deal_activity — append-only; no member update/delete policy. Rows are
-- written by security-definer RPCs/triggers (which bypass RLS as the
-- function owner) — the member insert policy below is a defense-in-depth
-- backstop, not something the app relies on for its normal write path.
-- ============================================================================
create policy "member read own deal_activity"
  on public.deal_activity for select
  using (org_id in (select my_org_ids()));

create policy "member insert own deal_activity"
  on public.deal_activity for insert
  with check (org_id in (select my_org_ids()));

-- ============================================================================
-- follow_ups
-- ============================================================================
create policy "member read own follow_ups"
  on public.follow_ups for select
  using (org_id in (select my_org_ids()));

create policy "member insert own follow_ups"
  on public.follow_ups for insert
  with check (org_id in (select my_org_ids()));

create policy "member update own follow_ups"
  on public.follow_ups for update
  using (org_id in (select my_org_ids()))
  with check (org_id in (select my_org_ids()));

-- ============================================================================
-- audit_leads — see the caveat above: the pre-existing "Allow authenticated
-- read" (qual = true) policy makes this SELECT addition a no-op for now.
-- Added anyway for consistency and so it's already in place, narrowed for
-- free, whenever that broader policy is tightened in the separate security
-- workstream. No insert policy added — audit_leads inserts come from the
-- public scan form (anon) and RPCs, not org members directly.
-- ============================================================================
create policy "member read own audit_leads"
  on public.audit_leads for select
  using (org_id in (select my_org_ids()));
