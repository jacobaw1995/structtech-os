-- StructTech OS — Phase A Week 1: row-level RLS hardening (Jacob's posture
-- call 7/28), applied BEFORE the assistant capability role is seeded.
--
-- Closes two direct-API bypasses: (1) estimates/estimate_line_items/
-- signatures member policies only checked org membership, never
-- view_estimates; (2) deals' "member update own deals" checked org
-- membership only, no ownership/manager/edit_leads check at all — any org
-- member could UPDATE any deal via direct PostgREST.
--
-- Read LIVE pg_policies for all 4 tables + org_members before writing this.
-- deals has a "staff all deals" (is_staff()) catch-all, untouched.
-- estimates/estimate_line_items/signatures have NO staff catch-all at all
-- — member policies are the only access path. Recursion check: org_members'
-- own policies key off is_staff()/my_org_ids() only, never has_capability()/
-- is_org_manager() (both SECURITY DEFINER, bypass RLS on internal lookups,
-- same pattern already used everywhere else in this codebase). No cycle.

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

-- Deals edit-by-ownership at RLS, mirroring the RPC-layer C3 gate.
-- Residual gap (flagged not fixed, out of row-level scope): WITH CHECK is
-- row-level not column-level, so an edit_leads caller could still PATCH
-- owner_id directly via REST (her edit_leads branch passes regardless of
-- the new owner_id value) — a direct-API path around assign_deal_owner's
-- "no reassign by reps" rule. Not new: every member could already do this
-- before this migration (old policy had zero ownership check). Left for
-- the later full RLS pass.
alter policy "member update own deals" on public.deals
  using (
    org_id in (select my_org_ids())
    and (is_org_manager(org_id) or owner_id = auth.uid() or has_capability(org_id, 'edit_leads'))
  )
  with check (
    org_id in (select my_org_ids())
    and (is_org_manager(org_id) or owner_id = auth.uid() or has_capability(org_id, 'edit_leads'))
  );
