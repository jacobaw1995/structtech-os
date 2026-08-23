-- StructTech OS — Phase A Week 1: row-level RLS hardening (Jacob's posture
-- call 7/28), applied BEFORE the assistant capability role is seeded.
--
-- NOT APPLIED. Author-only migration file — ask before applying, extra
-- care per CLAUDE.md ("changing auth/RLS/security").
--
-- Chunks 1-5 of the capability-flags feature (roadmap "Assistant role —
-- capability flags (hide $)") enforced everything at the RPC/route layer.
-- That's airtight for the app itself, but PostgREST exposes these tables
-- directly — a caller with a valid session and the anon/authenticated key
-- can bypass the app entirely and hit the REST API. This migration closes
-- the two gaps that matter for the assistant role specifically:
--
--   1. Estimate visibility — the member policies on estimates,
--      estimate_line_items, signatures only ever checked org membership,
--      never any role/capability. A member without view_estimates could
--      read/write these tables directly even though every app surface
--      (chunk 3) blocks her.
--   2. Deals edit-by-ownership — "member update own deals" only checked
--      org membership too. The RPC-layer C3 gate (is_org_manager OR
--      owner_id=auth.uid() OR has_capability(edit_leads), chunk 4) was
--      never mirrored at RLS, so a direct PostgREST UPDATE bypassed
--      ownership entirely — any org member could edit any deal via the
--      REST API regardless of the RPC gate. This is the "before non-
--      manager reps" item BACKLOG.md already flagged, not new scope.
--
-- SCOPE NOTE (explicit, don't expand): only these two. The `value` COLUMN
-- read staying app-layer-only (RLS can't hide a column, only rows — a
-- direct SELECT would still return the value column even with row access
-- allowed) is an accepted gap, not addressed here. deal_notes/schedule
-- finer-grained RLS stays for a later full pass.
--
-- Read LIVE pg_policies for all 4 tables + org_members before writing this
-- (not guessed): deals has a "staff all deals" ALL/is_staff() catch-all,
-- preserved untouched below. estimates/estimate_line_items/signatures have
-- NO staff/platform-admin catch-all policy at all today — member policies
-- are the only access path, so there is nothing else to preserve there.
--
-- Recursion check (confirmed via pg_policies before writing this):
-- org_members' own policies ("staff all org_members" / "member read own
-- members") key off is_staff()/my_org_ids() only — never has_capability()
-- or is_org_manager(). Both of those are SECURITY DEFINER (bypass RLS on
-- their internal org_members lookups, same as every other helper already
-- embedded in this codebase's policies), so has_capability() -> queries
-- org_members -> is_org_manager() -> queries org_members again never
-- re-enters a policy that calls has_capability(). No cycle.
--
-- ALTER POLICY replaces the full USING/WITH CHECK expression, not an
-- incremental add — each statement below carries the complete new
-- condition (old org-scope AND the new capability/ownership check), not a
-- diff against the old one.

-- ============================================================================
-- 1. Estimate visibility: estimates, estimate_line_items, signatures.
-- Every member policy gets `AND has_capability(org_id, 'view_estimates')`.
-- has_capability() returns true unconditionally for manager-tier roles, so
-- Isaac/Jacob/every existing manager is unaffected. INSERT/UPDATE/DELETE
-- are included, not just SELECT — a caller who can't view estimates
-- shouldn't be able to write them via direct API either, even though the
-- app itself only ever writes through create_estimate_from_deal/
-- update_estimate_* RPCs (CLAUDE.md rule 3).
-- ============================================================================

alter policy "member read own estimates" on public.estimates
  using (org_id in (select my_org_ids()) and has_capability(org_id, 'view_estimates'));

alter policy "member insert own estimates" on public.estimates
  with check (org_id in (select my_org_ids()) and has_capability(org_id, 'view_estimates'));

alter policy "member update own estimates" on public.estimates
  using (org_id in (select my_org_ids()) and has_capability(org_id, 'view_estimates'))
  with check (org_id in (select my_org_ids()) and has_capability(org_id, 'view_estimates'));

alter policy "member read own estimate_line_items" on public.estimate_line_items
  using (org_id in (select my_org_ids()) and has_capability(org_id, 'view_estimates'));

alter policy "member insert own estimate_line_items" on public.estimate_line_items
  with check (org_id in (select my_org_ids()) and has_capability(org_id, 'view_estimates'));

alter policy "member update own estimate_line_items" on public.estimate_line_items
  using (org_id in (select my_org_ids()) and has_capability(org_id, 'view_estimates'))
  with check (org_id in (select my_org_ids()) and has_capability(org_id, 'view_estimates'));

alter policy "member delete own estimate_line_items" on public.estimate_line_items
  using (org_id in (select my_org_ids()) and has_capability(org_id, 'view_estimates'));

alter policy "member read own signatures" on public.signatures
  using (org_id in (select my_org_ids()) and has_capability(org_id, 'view_estimates'));

alter policy "member insert own signatures" on public.signatures
  with check (org_id in (select my_org_ids()) and has_capability(org_id, 'view_estimates'));

-- ============================================================================
-- 2. Deals edit-by-ownership at RLS. "member update own deals" previously
-- checked org membership ONLY (no ownership/manager/capability check at
-- all) — any org member could UPDATE any deal directly via PostgREST.
-- Aligned with the RPC-layer C3 gate (is_org_manager OR
-- owner_id=auth.uid() OR has_capability(edit_leads), chunk 4). "staff all
-- deals" (is_staff()) is untouched — separate policy, separate bypass,
-- not modified.
--
-- Residual gap, flagged not fixed (out of this migration's row-level
-- scope, not newly introduced by it): RLS is row-level, not column-level.
-- WITH CHECK evaluates against the NEW row, so an edit_leads caller who
-- includes owner_id in a direct PostgREST PATCH still passes (her
-- has_capability(edit_leads) branch is true regardless of the new
-- owner_id value) — a direct-API path around assign_deal_owner's "no
-- reassign/give-away by reps" rule. This is not new: EVERY org member
-- could already PATCH owner_id via direct REST before this migration (the
-- old policy had no ownership check whatsoever); this migration narrows
-- who can update a deal at all but does not add column-level protection.
-- Closing it needs a trigger or a narrower with_check than RLS alone can
-- express — left for the later full RLS pass, per this migration's scope
-- note.
-- ============================================================================

alter policy "member update own deals" on public.deals
  using (
    org_id in (select my_org_ids())
    and (is_org_manager(org_id) or owner_id = auth.uid() or has_capability(org_id, 'edit_leads'))
  )
  with check (
    org_id in (select my_org_ids())
    and (is_org_manager(org_id) or owner_id = auth.uid() or has_capability(org_id, 'edit_leads'))
  );
