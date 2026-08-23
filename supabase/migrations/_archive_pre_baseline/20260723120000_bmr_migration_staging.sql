-- BMR data migration — staging tables + provenance map.
--
-- NOT APPLIED. Author-only migration file — ask before applying to the live
-- Supabase project, same as every other migration in this repo.
--
-- Context: docs/reference/BMR_DATA_MIGRATION_PLAN.md (authoritative) — bringing
-- Isaac's real book of business out of the old standalone BMR app (its own,
-- separate Supabase project) and into StructTech OS as BMR-org `deals`.
--
-- Scope resolved 7/19: 4 source tables only — leads, lead_notes, lead_activity,
-- and the old app's users (staged here only to build the identity map, never
-- inserted anywhere as a target row). products/pricing_config/estimate_*
-- and lead_appointments are explicitly OUT of scope for this pass (see plan
-- §"open decisions", resolved) — no staging tables for those.
--
-- Pattern: land raw JSON untransformed (§8 step 2), keyed by the OLD id, so
-- the transform (docs/migration/bmr_transform.sql) is re-runnable and
-- auditable without re-exporting. migration_bmr_id_map is the provenance
-- table — every migrated row traces back to its source and the load is
-- idempotent (`on conflict do nothing`, keyed on old id).
--
-- These 5 tables are scaffolding, not part of the product: no org_id, no
-- tenant scoping, PII-bearing. RLS is enabled with NO policies — deny-all
-- for anon/authenticated, service_role/superuser only (same posture as any
-- admin-only migration script). Intent is to DROP all 5 once the migration
-- is loaded and verified (§9) — do not build app code against them.

-- ============================================================================
-- 1. Raw landing tables — one row per old-app record, untransformed.
-- ============================================================================

create table public.migration_bmr_leads_raw (
  old_id uuid primary key,
  payload jsonb not null,
  loaded_at timestamptz not null default now()
);

comment on table public.migration_bmr_leads_raw is
  'BMR migration staging: raw export of the old app''s public.leads, one row per record, keyed by old id. Scaffolding — drop after the migration is verified.';

create table public.migration_bmr_notes_raw (
  old_id uuid primary key,
  payload jsonb not null,
  loaded_at timestamptz not null default now()
);

comment on table public.migration_bmr_notes_raw is
  'BMR migration staging: raw export of the old app''s public.lead_notes. Scaffolding — drop after the migration is verified.';

create table public.migration_bmr_activity_raw (
  old_id uuid primary key,
  payload jsonb not null,
  loaded_at timestamptz not null default now()
);

comment on table public.migration_bmr_activity_raw is
  'BMR migration staging: raw export of the old app''s public.lead_activity. Scaffolding — drop after the migration is verified.';

create table public.migration_bmr_users_raw (
  old_id uuid primary key,
  payload jsonb not null,
  loaded_at timestamptz not null default now()
);

comment on table public.migration_bmr_users_raw is
  'BMR migration staging: raw export of the old app''s users/profiles. Used ONLY to build migration_bmr_id_map''s user rows (email match against public.profiles) — never inserted as a target row itself. Scaffolding — drop after the migration is verified.';

alter table public.migration_bmr_leads_raw enable row level security;
alter table public.migration_bmr_notes_raw enable row level security;
alter table public.migration_bmr_activity_raw enable row level security;
alter table public.migration_bmr_users_raw enable row level security;
-- Deliberately no policies: deny-all for anon/authenticated. Loaded and read
-- via service_role / the SQL editor only, per the plan's admin-migration flow.

-- ============================================================================
-- 2. Provenance / idempotency map.
-- ============================================================================

create table public.migration_bmr_id_map (
  entity text not null check (entity in ('lead', 'note', 'activity', 'user')),
  old_id uuid not null,
  -- Nullable: a 'user' row with no email match against public.profiles (a
  -- departed/unknown old-app user) has no new_id. The transform's actor/owner
  -- lookups are LEFT JOINs against this table, so an absent or null-new_id
  -- row both resolve to NULL actor/owner — matching the app's existing
  -- graceful fallback for unattributed rows (verified in Stage 5 Track C2).
  new_id uuid,
  created_at timestamptz not null default now(),
  primary key (entity, old_id)
);

comment on table public.migration_bmr_id_map is
  'BMR migration staging: old id -> new id per entity, the provenance/idempotency backbone for docs/migration/bmr_transform.sql. Scaffolding — drop after the migration is verified (or keep briefly for a documented rollback window, then drop).';

alter table public.migration_bmr_id_map enable row level security;
-- Deliberately no policies: deny-all for anon/authenticated, service_role only.
