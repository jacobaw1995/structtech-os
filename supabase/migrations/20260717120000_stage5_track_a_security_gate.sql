-- StructTech OS — CRM Depth Stage 5, Track A: the go-live security gate.
--
-- Context: docs/reference/STAGE5_GOLIVE_GATE.md. This is a HARD GATE — no
-- client login (Isaac) may be created until this migration is applied and
-- the Supabase security advisor is re-run clean on these tables. Live audit
-- performed 7/17 against ejlhrykcdfcyeooooodx; see A0 findings for detail.
--
-- Explicitly OUT of scope for this migration (tracked separately in
-- docs/BACKLOG.md, per 7/17 review with Jacob):
--   * client_roadmaps — `read roadmap by token` (SELECT true) and
--     `update roadmap milestones` (UPDATE true/true) are a real anon
--     read/write-all leak, but this repo's app never touches that table
--     (an external client portal does) and the correct fix is a
--     token-checked security-definer RPC coordinated with that portal.
--     Deferred to its own reviewed migration.
--
-- ============================================================================
-- 1. audit_leads — drop the wide-open read. `member read own audit_leads`
--    (org_id in my_org_ids()) and `staff all audit_leads` (is_staff()) already
--    exist from 20260712120000_org_scoped_rls_crm.sql and are untouched.
--    `Allow anon insert` (public scan-form capture) is untouched.
-- ============================================================================
drop policy if exists "Allow authenticated read" on public.audit_leads;

-- ============================================================================
-- 2/3/4. audits, proposals, prospects — internal StructTech sales-prospecting
--    data with NO org_id column (confirmed via information_schema — there is
--    no tenant concept here at all). Replace the blanket ALL true/true
--    policies with is_platform_admin() (StructTech-internal owner/agency_admin),
--    matching the same gate tenant_modules already uses.
-- ============================================================================
drop policy if exists "all_audits" on public.audits;
create policy "platform admin all audits"
  on public.audits for all
  using (is_platform_admin())
  with check (is_platform_admin());

drop policy if exists "all_proposals" on public.proposals;
create policy "platform admin all proposals"
  on public.proposals for all
  using (is_platform_admin())
  with check (is_platform_admin());

drop policy if exists "all_prospects" on public.prospects;
create policy "platform admin all prospects"
  on public.prospects for all
  using (is_platform_admin())
  with check (is_platform_admin());

-- ============================================================================
-- 5. profiles — is_pipeline_user() means "has any profile row," i.e. every
--    profiled user could read every other user's profile across all tenants.
--    Re-scope to self-or-shares-an-org. `pipeline_profiles_update_own`
--    (id = auth.uid()) is untouched.
-- ============================================================================
drop policy if exists "pipeline_profiles_select" on public.profiles;
create policy "profiles_select_self_or_org"
  on public.profiles for select
  using (
    id = auth.uid()
    or id in (
      select om.user_id
      from public.org_members om
      where om.org_id in (select my_org_ids())
    )
  );

-- ============================================================================
-- 6. Legacy is_pipeline_user()/is_pipeline_manager()-gated cluster:
--    leads, lead_notes, lead_activity, lead_appointments, pipeline_invites.
--    None of these 5 tables has an org_id column (confirmed), and none are
--    referenced anywhere in this app's source outside generated
--    database.types.ts — grepped 7/17, no authenticated-member code path
--    reads them. is_pipeline_user() only means "has a profile," so the
--    instant Isaac gets one, he could read/write every tenant's rows here.
--    Lock to is_staff() (StructTech-internal only) rather than leave them on
--    a cross-tenant gate. Proper org-scoping (add + backfill org_id, or fold
--    into deals) is a deliberate Stage 6+ follow-up, tracked in BACKLOG.md —
--    not attempted here since it's a schema change, not a policy tweak.
-- ============================================================================
drop policy if exists "leads_insert" on public.leads;
drop policy if exists "leads_select" on public.leads;
drop policy if exists "leads_update_owner_or_manager" on public.leads;
create policy "staff all leads"
  on public.leads for all
  using (is_staff())
  with check (is_staff());

drop policy if exists "lead_notes_insert" on public.lead_notes;
drop policy if exists "lead_notes_select" on public.lead_notes;
create policy "staff all lead_notes"
  on public.lead_notes for all
  using (is_staff())
  with check (is_staff());

drop policy if exists "lead_activity_insert" on public.lead_activity;
drop policy if exists "lead_activity_select" on public.lead_activity;
create policy "staff all lead_activity"
  on public.lead_activity for all
  using (is_staff())
  with check (is_staff());

drop policy if exists "lead_appointments_manage" on public.lead_appointments;
drop policy if exists "lead_appointments_select" on public.lead_appointments;
create policy "staff all lead_appointments"
  on public.lead_appointments for all
  using (is_staff())
  with check (is_staff());

drop policy if exists "pipeline_invites_manage" on public.pipeline_invites;
create policy "staff all pipeline_invites"
  on public.pipeline_invites for all
  using (is_staff())
  with check (is_staff());

-- ============================================================================
-- 7. Helper hardening — pin search_path on my_org_ids() (the one gate
--    function missing it) plus the 7 other functions the security advisor
--    flags with mutable search_path. All 8 bodies checked 7/17: every
--    cross-schema reference (auth.uid()) is already schema-qualified, so
--    pinning to `public` changes nothing behaviorally, only closes the
--    search_path-hijack vector on SECURITY DEFINER functions.
-- ============================================================================
alter function public.my_org_ids() set search_path = public;
alter function public.protect_roadmap_columns() set search_path = public;
alter function public.roadmap_playbook(text) set search_path = public;
alter function public.auto_create_roadmap() set search_path = public;
alter function public.generate_roadmap_for_lead(uuid) set search_path = public;
alter function public.build_roadmap_levels(jsonb, integer) set search_path = public;
alter function public.accept_invite(text, text) set search_path = public;
alter function public.touch_leads_updated_at() set search_path = public;
