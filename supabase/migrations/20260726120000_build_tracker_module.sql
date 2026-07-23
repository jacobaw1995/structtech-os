-- StructTech OS — In-app Build Tracker v1 (StructTech-internal module).
--
-- NOT APPLIED. Author-only migration file — ask before applying to the live
-- Supabase project, same as every other migration in this repo.
--
-- Context: CLAUDE.md "NEW — build FIRST" (Jacob's priority call, 7/24) +
-- BACKLOG.md "In-app Build Tracker". Replaces the static
-- docs/ROADMAP_MATRIX.html + docs/ROLLOUT_CHECKLIST.md files with a single,
-- attributed, in-app source of truth. Dogfoods the platform. Module key is
-- 'build' (NOT 'roadmap' — that key is already taken by the client-roadmap
-- module, live on both StructTech and BMR).
--
-- Pattern precedent: 20260722120000_tracker_module.sql (same shape — add
-- module_key to the check constraint, one table, RLS, security-definer
-- RPCs, seed). update_roadmap_fields follows the jsonb-patch + allowlist
-- convention from 20260724120000_update_deal_fields_jsonb_patch.sql (key
-- ABSENT = untouched, key PRESENT = write it, including explicit clear) —
-- not update_tracker_project's scalar-coalesce style, since the "notes"
-- field needs to be clearable.

-- ============================================================================
-- 1. tenant_modules.module_key — add 'build' to the allowed set.
-- ============================================================================
alter table public.tenant_modules
  drop constraint tenant_modules_module_key_check;

alter table public.tenant_modules
  add constraint tenant_modules_module_key_check
  check (module_key in ('crm', 'estimating', 'coordination', 'field', 'delivery', 'scan', 'roadmap', 'tracker', 'build'));

-- ============================================================================
-- 2. roadmap_items
-- ============================================================================
create table public.roadmap_items (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  phase text not null check (phase in ('now', 'A', 'B', 'C', 'D', 'later')),
  section text not null,
  feature text not null,
  status text not null default 'planned' check (status in ('shipped', 'in_progress', 'planned')),
  notes text,
  sort_order int not null default 0,
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.roadmap_items is
  'In-app Build Tracker: one row per feature/phase cell on the roadmap matrix. StructTech-internal (module entitlement gates the route) — never licensed to contractor tenants.';

alter table public.roadmap_items enable row level security;

create policy "member read own roadmap_items"
  on public.roadmap_items for select
  using (org_id in (select my_org_ids()));

create policy "member insert own roadmap_items"
  on public.roadmap_items for insert
  with check (org_id in (select my_org_ids()));

create policy "member update own roadmap_items"
  on public.roadmap_items for update
  using (org_id in (select my_org_ids()))
  with check (org_id in (select my_org_ids()));

create index roadmap_items_org_id_idx on public.roadmap_items (org_id);
create index roadmap_items_org_section_sort_idx on public.roadmap_items (org_id, section, sort_order);

-- ============================================================================
-- 3. RPCs
-- ============================================================================
create or replace function public.create_roadmap_item(
  p_org_id uuid,
  p_phase text,
  p_section text,
  p_feature text,
  p_status text default 'planned',
  p_notes text default null,
  p_sort_order int default 0
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item_id uuid;
  v_actor_id uuid;
begin
  if p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of organization %', p_org_id;
  end if;

  if p_phase not in ('now', 'A', 'B', 'C', 'D', 'later') then
    raise exception 'invalid roadmap phase: %', p_phase;
  end if;

  if p_status not in ('shipped', 'in_progress', 'planned') then
    raise exception 'invalid roadmap status: %', p_status;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  insert into public.roadmap_items (org_id, phase, section, feature, status, notes, sort_order, updated_by)
  values (p_org_id, p_phase, p_section, p_feature, p_status, p_notes, p_sort_order, v_actor_id)
  returning id into v_item_id;

  return v_item_id;
end;
$$;

comment on function public.create_roadmap_item(uuid, text, text, text, text, text, int) is
  'Build Tracker item insert RPC. Org-scoped from caller membership; stamps updated_by.';

-- update_roadmap_fields — jsonb-patch convention (CLAUDE.md-required for
-- this module): key ABSENT means untouched, key PRESENT (including explicit
-- JSON null or '') means write it. v_allowed is the only thing standing
-- between "patch my notes" and "patch any column" — org_id/id/updated_by
-- are deliberately never in it (ownership/identity stay out of the patch
-- surface, same reasoning as update_deal_fields).
create or replace function public.update_roadmap_fields(p_id uuid, p_patch jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_actor_id uuid;
  v_key text;
  v_allowed text[] := array['phase', 'section', 'feature', 'status', 'notes', 'sort_order'];
  v_new_phase text;
  v_new_status text;
begin
  select org_id into v_org_id from public.roadmap_items where id = p_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'roadmap item not found or not accessible: %', p_id;
  end if;

  for v_key in select jsonb_object_keys(p_patch) loop
    if not (v_key = any(v_allowed)) then
      raise exception 'field not writable via patch: %', v_key;
    end if;
  end loop;

  if p_patch ? 'phase' then
    v_new_phase := p_patch ->> 'phase';
    if v_new_phase not in ('now', 'A', 'B', 'C', 'D', 'later') then
      raise exception 'invalid roadmap phase: %', v_new_phase;
    end if;
  end if;

  if p_patch ? 'status' then
    v_new_status := p_patch ->> 'status';
    if v_new_status not in ('shipped', 'in_progress', 'planned') then
      raise exception 'invalid roadmap status: %', v_new_status;
    end if;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.roadmap_items
  set
    phase = case when p_patch ? 'phase' then v_new_phase else phase end,
    section = case when p_patch ? 'section' then p_patch ->> 'section' else section end,
    feature = case when p_patch ? 'feature' then p_patch ->> 'feature' else feature end,
    status = case when p_patch ? 'status' then v_new_status else status end,
    notes = case when p_patch ? 'notes' then p_patch ->> 'notes' else notes end,
    sort_order = case when p_patch ? 'sort_order' then nullif(p_patch ->> 'sort_order', '')::int else sort_order end,
    updated_by = coalesce(v_actor_id, updated_by),
    updated_at = now()
  where id = p_id;
end;
$$;

comment on function public.update_roadmap_fields(uuid, jsonb) is
  'Build Tracker patch-update RPC (jsonb-patch + allowlist convention, CLAUDE.md-required). Absent key = untouched; present key = write it, including clearing notes to null/empty.';

create or replace function public.delete_roadmap_item(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.roadmap_items where id = p_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'roadmap item not found or not accessible: %', p_id;
  end if;

  delete from public.roadmap_items where id = p_id;
end;
$$;

comment on function public.delete_roadmap_item(uuid) is
  'Build Tracker hard-delete RPC. No archive tier — per §2.6 full CRUD, a matrix row can just be deleted outright (unlike tracker_projects, nothing else references a roadmap_item).';

-- ============================================================================
-- 4. Entitlement — StructTech (internal) only. Contractors never get this.
-- ============================================================================
insert into public.tenant_modules (org_id, module_key, enabled, config)
select o.id, 'build', true, '{}'::jsonb
from public.organizations o
where o.tenant_type = 'internal'
on conflict (org_id, module_key) do update
  set enabled = excluded.enabled,
      updated_at = now();

-- ============================================================================
-- 5. Seed — ~66 rows straight across from docs/ROADMAP_MATRIX.html's ROWS
-- array (the SEED source; that file + docs/ROLLOUT_CHECKLIST.md retire once
-- this ships, per CLAUDE.md). status = 'shipped' where phase='now', else
-- 'planned' (no row in the source array pre-dates as 'in_progress' — that
-- status exists for use going forward, in-app). sort_order preserves the
-- source array's order so the grouped table renders in the same reading
-- order as the matrix did.
-- ============================================================================
do $$
declare
  v_org_id uuid;
begin
  select id into v_org_id from public.organizations where tenant_type = 'internal' limit 1;

  if v_org_id is null then
    raise exception 'roadmap_items seed: no internal-type org found';
  end if;

  if exists (select 1 from public.roadmap_items where org_id = v_org_id) then
    return;
  end if;

  insert into public.roadmap_items (org_id, phase, section, feature, status, sort_order)
  values
  (v_org_id, 'now', 'CRM & pipeline', 'Kanban pipeline (config-driven stages)', 'shipped', 0),
  (v_org_id, 'now', 'CRM & pipeline', 'Lead Control Center (form == checklist)', 'shipped', 1),
  (v_org_id, 'now', 'CRM & pipeline', 'Owner assign / claim / reassign', 'shipped', 2),
  (v_org_id, 'now', 'CRM & pipeline', 'Author attribution on notes + edits', 'shipped', 3),
  (v_org_id, 'now', 'CRM & pipeline', 'Free navigation, no forced-order gating', 'shipped', 4),
  (v_org_id, 'now', 'CRM & pipeline', 'Full edit / clear / delete every field', 'shipped', 5),
  (v_org_id, 'later', 'CRM & pipeline', 'Table + calendar views (beyond kanban)', 'planned', 6),
  (v_org_id, 'later', 'CRM & pipeline', 'Global search across leads', 'planned', 7),
  (v_org_id, 'later', 'CRM & pipeline', 'Per-lead next-action chip', 'planned', 8),
  (v_org_id, 'now', 'Estimating', 'Document-as-editor estimate (WYSIWYG)', 'shipped', 9),
  (v_org_id, 'now', 'Estimating', 'Manual line items (any order)', 'shipped', 10),
  (v_org_id, 'now', 'Estimating', 'Guided mode (scope checklist → lines)', 'shipped', 11),
  (v_org_id, 'now', 'Estimating', 'PDF output (parity with on-screen)', 'shipped', 12),
  (v_org_id, 'C', 'Estimating', 'Pricing matrix (data point → priced line)', 'planned', 13),
  (v_org_id, 'later', 'Estimating', 'Product-catalog pricing', 'planned', 14),
  (v_org_id, 'now', 'Signing & documents', 'In-person e-signature (estimates)', 'shipped', 15),
  (v_org_id, 'A', 'Signing & documents', 'Remote / email signing link (send → sign → sync)', 'planned', 16),
  (v_org_id, 'A', 'Signing & documents', 'Auto-emailed signed copy to customer', 'planned', 17),
  (v_org_id, 'A', 'Signing & documents', 'Transactional email (Resend: invites / reset / copies)', 'planned', 18),
  (v_org_id, 'A', 'Signing & documents', 'Self-serve password reset', 'planned', 19),
  (v_org_id, 'D', 'Signing & documents', 'Docs section (view / download / send all)', 'planned', 20),
  (v_org_id, 'later', 'Signing & documents', 'Editable templates + invoices', 'planned', 21),
  (v_org_id, 'now', 'Present mode & sales', 'Present estimate full-screen + sign', 'shipped', 22),
  (v_org_id, 'B', 'Present mode & sales', 'Multi-section deck that sells the roof', 'planned', 23),
  (v_org_id, 'B', 'Present mode & sales', 'Testimonials / past-jobs section', 'planned', 24),
  (v_org_id, 'B', 'Present mode & sales', 'Payment schedule (30/40/30)', 'planned', 25),
  (v_org_id, 'B', 'Present mode & sales', 'Product section (profile / color / warranty)', 'planned', 26),
  (v_org_id, 'now', 'Coordination', 'Sign-off gate → work order → materials', 'shipped', 27),
  (v_org_id, 'now', 'Coordination', 'Material ready-by gates the schedule', 'shipped', 28),
  (v_org_id, 'now', 'Coordination', 'Change-after-sign-off audit trail', 'shipped', 29),
  (v_org_id, 'A', 'Coordination', 'Real homeowner sign-off + signed doc (both paths)', 'planned', 30),
  (v_org_id, 'later', 'Coordination', 'Formal change orders', 'planned', 31),
  (v_org_id, 'now', 'Scheduling (kept distinct)', 'Per-work-order crew + start/end dates', 'shipped', 32),
  (v_org_id, 'now', 'Scheduling (kept distinct)', 'Material-delivery ready-by dates', 'shipped', 33),
  (v_org_id, 'later', 'Scheduling (kept distinct)', 'Site-visit / appointment scheduling (calendar)', 'planned', 34),
  (v_org_id, 'later', 'Scheduling (kept distinct)', 'Cross-job crew Gantt (all jobs + crews)', 'planned', 35),
  (v_org_id, 'D', 'Scheduling (kept distinct)', 'Google Calendar two-way sync', 'planned', 36),
  (v_org_id, 'now', 'Field (crew)', 'Crew mobile check-ins', 'shipped', 37),
  (v_org_id, 'now', 'Field (crew)', 'Visual production packet + outdoor mode', 'shipped', 38),
  (v_org_id, 'A', 'Field (crew)', 'Office-side roof-data / photo upload', 'planned', 39),
  (v_org_id, 'A', 'Field (crew)', 'Per-role file permissions (edit / delete)', 'planned', 40),
  (v_org_id, 'later', 'Field (crew)', 'Photos at volume (R2) + annotated trim-map', 'planned', 41),
  (v_org_id, 'C', 'Customer / homeowner portal', 'Portal v1 — signed docs + schedule + status', 'planned', 42),
  (v_org_id, 'later', 'Customer / homeowner portal', 'Portal v2 — photos + progress timeline', 'planned', 43),
  (v_org_id, 'later', 'Customer / homeowner portal', 'Portal v3 — homeowner confirms / schedules', 'planned', 44),
  (v_org_id, 'now', 'Roles & access', 'Owner / manager / member roles', 'shipped', 45),
  (v_org_id, 'now', 'Roles & access', 'Edit-by-ownership (RPC-level)', 'shipped', 46),
  (v_org_id, 'A', 'Roles & access', 'Assistant role — capability flags (hide $)', 'planned', 47),
  (v_org_id, 'C', 'Roles & access', 'Edit-by-ownership at RLS (safe for reps)', 'planned', 48),
  (v_org_id, 'A', 'Overview', 'Dashboard / home view', 'planned', 49),
  (v_org_id, 'now', 'Platform / multi-tenant', 'Pooled multi-tenancy + entitlements', 'shipped', 50),
  (v_org_id, 'now', 'Platform / multi-tenant', 'Config-driven engine (reads per-tenant config)', 'shipped', 51),
  (v_org_id, 'C', 'Platform / multi-tenant', 'Self-serve config editor (tenant edits own)', 'planned', 52),
  (v_org_id, 'C', 'Platform / multi-tenant', 'Second contractor tenant onboarded', 'planned', 53),
  (v_org_id, 'later', 'Platform / multi-tenant', 'Multiple pipeline types (sales / campaign / mktg)', 'planned', 54),
  (v_org_id, 'later', 'Platform / multi-tenant', 'Self-serve onboarding at scale', 'planned', 55),
  (v_org_id, 'now', 'Auth / account', 'Email + password login, invites', 'shipped', 56),
  (v_org_id, 'D', 'Auth / account', 'First-timer onboarding tour + tutorial tab', 'planned', 57),
  (v_org_id, 'D', 'Integrations', 'Google (sign-in / Calendar / Gmail CRM sends)', 'planned', 58),
  (v_org_id, 'D', 'Integrations', 'Twilio SMS (instant lead response)', 'planned', 59),
  (v_org_id, 'D', 'Integrations', 'Stripe billing (the $20K MRR path)', 'planned', 60),
  (v_org_id, 'later', 'Integrations', 'QuickBooks · aerial roof measurement', 'planned', 61),
  (v_org_id, 'later', 'North Star', 'AI assistant + semantic search', 'planned', 62),
  (v_org_id, 'later', 'North Star', 'Product catalogs + inventory', 'planned', 63),
  (v_org_id, 'later', 'North Star', 'StructTech supply shop / distribution', 'planned', 64),
  (v_org_id, 'later', 'North Star', 'Native mobile app (App Store / Play)', 'planned', 65);
end $$;
