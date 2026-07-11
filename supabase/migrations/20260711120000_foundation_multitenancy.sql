-- StructTech OS — Week 1 Foundation: multi-tenancy (additive)
--
-- NOT APPLIED. Author-only migration file — see CLAUDE.md "ask before applying
-- any migration to the live Supabase project."
--
-- Context (discovered via read-only introspection of the live `structtech`
-- project before writing this file — see conversation for the full findings):
--   * `organizations` and `org_members` ALREADY EXIST live, serving
--     org_systems / tickets / org_invoices / org_invites today. This
--     migration EXTENDS them in place rather than creating parallel tables.
--   * `my_org_ids()` ALREADY EXISTS (security definer, stable, setof uuid)
--     and is already embedded in 8 existing RLS policies. This migration
--     reuses it as CLAUDE.md's `get_my_org_ids()` helper rather than adding
--     a duplicate/aliased function.
--   * `is_staff()` already exists and is used as a blanket bypass
--     (`for all using (is_staff())`) on every adjacent org-scoped table
--     (org_systems, tickets, org_invoices, org_invites, engagements, ...).
--     Those EXISTING policies are left untouched — migrating them to the
--     membership model is a separate security workstream, not this one.
--   * The NEW OS surface added by this migration (tenant_modules + the
--     provisioning RPCs below) deliberately does NOT use is_staff().
--     Per SCOPE.md §3, the agency operator layer is modeled as an ordinary
--     membership row (role = agency_admin) in the client org, so
--     `my_org_ids()` already returns it and reads need no special case.
--     For platform-level actions (provisioning a tenant, granting module
--     entitlements — actions no single client org's own owner should be
--     able to do to itself), the gate is `is_platform_admin()`: a new
--     helper defined below, checking the caller holds an owner/agency_admin
--     membership in *some* internal-type org (i.e. StructTech itself).
--     StructTech staff see a given client's data by holding an agency_admin
--     row in *that* client org — no blanket bypass on these new tables.
--   * `org_id` backfill on the CRM tables (deals, deal_notes, deal_activity,
--     follow_ups, audit_leads) is a SEPARATE migration file
--     (20260711120100_backfill_org_id_crm.sql), per instruction.
--
-- Bootstrap note: create_organization/add_org_member both require an
-- existing platform admin to call them, which is correct for every org
-- after the first — but StructTech's own internal org and Jacob's owner
-- membership in it can't come from these RPCs (no platform admin exists
-- yet to satisfy the gate). That first org + membership row are inserted
-- directly in the Week 1 seed step, bypassing these RPCs entirely — not a
-- gap in this migration, a deliberate one-time bootstrap.

-- ============================================================================
-- 1. organizations — add tenant_type
-- ============================================================================
-- Default 'contractor' is a structural inference, not a guess at specific
-- business identity: the `tenant_type` axis (internal vs. contractor) did not
-- exist in the prior schema, so any pre-existing organizations row was
-- necessarily a client org (StructTech's own 'internal' row does not exist
-- yet — it is inserted fresh in the Week 1 seed step). Review the existing
-- row's value before/at apply time; adjust if it disagrees.
alter table public.organizations
  add column if not exists tenant_type text not null default 'contractor'
    check (tenant_type in ('internal', 'contractor'));

comment on column public.organizations.tenant_type is
  'internal = StructTech itself (agency layer, all modules). contractor = a licensed client tenant.';

-- ============================================================================
-- 2. org_members — expand role taxonomy to the SCOPE.md §5 role model
-- ============================================================================
-- Was: role in ('owner', 'member'). Now: SCOPE.md §5's canonical set
-- (locked 7/9), which deliberately keeps the legacy 'member' value valid —
-- unlike a hard cutover, this needs no reassignment of the existing row
-- before the constraint can validate.
alter table public.org_members
  drop constraint if exists org_members_role_check;

alter table public.org_members
  add constraint org_members_role_check
  check (role in ('owner', 'admin', 'office', 'field', 'client_portal_viewer', 'agency_admin', 'member'));

comment on column public.org_members.role is
  'owner: full tenant, dashboard, financials. admin: delegated admin (settings, users) short of owner. '
  'office: office/coordinator tier — pipeline, coordination, estimating. '
  'field: field/crew tier — Field module only, no $ or pipeline. '
  'client_portal_viewer: read-only delivery view + confirm own items. '
  'agency_admin: StructTech operator membership inside a client org (internal tenant type only). '
  'member: legacy value, preserved for existing rows/features.';

-- ============================================================================
-- 3. is_platform_admin() — the gate for platform-level (StructTech-only)
-- actions: provisioning tenants and granting module entitlements. NOT the
-- same thing as "is_staff()" — this checks an ordinary membership row
-- (owner or agency_admin) in an internal-type org, not a separate bypass
-- table. Distinct from `my_org_ids()`/per-org role checks, which govern
-- operating *inside* a specific org a caller already has a membership in.
-- ============================================================================
create or replace function public.is_platform_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.org_members m
    join public.organizations o on o.id = m.org_id
    where m.user_id = auth.uid()
      and o.tenant_type = 'internal'
      and m.role in ('owner', 'agency_admin')
  );
$$;

comment on function public.is_platform_admin() is
  'True if the caller holds an owner/agency_admin membership in some internal-type org (StructTech itself). '
  'Gate for provisioning RPCs and tenant_modules writes — never used as a blanket read bypass.';

-- ============================================================================
-- 4. tenant_modules — new. The entitlement layer nav/route guards render from.
-- ============================================================================
create table if not exists public.tenant_modules (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  module_key text not null check (
    module_key in ('crm', 'estimating', 'coordination', 'field', 'delivery', 'scan', 'roadmap')
  ),
  enabled boolean not null default true,
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, module_key)
);

comment on table public.tenant_modules is
  'Entitlement layer: which modules an org is licensed for. Nav and route guards render from this.';

alter table public.tenant_modules enable row level security;

-- Read: any member of the org (including an agency_admin operating inside
-- a client tenant — my_org_ids() already returns that org, no special case).
create policy "member read own tenant_modules"
  on public.tenant_modules for select
  using (org_id in (select my_org_ids()));

-- Manage (insert/update/delete): platform admins only. Granting/revoking a
-- module entitlement is a licensing action StructTech performs on a tenant,
-- not something a client org's own owner can do to itself.
create policy "platform admin manage tenant_modules"
  on public.tenant_modules for all
  using (is_platform_admin())
  with check (is_platform_admin());

-- ============================================================================
-- 5. Security-definer RPCs
-- ============================================================================
-- All derive scope from auth.uid() internally rather than trusting a
-- caller-supplied org_id/user_id for authorization, per CLAUDE.md's RPC
-- pattern (insert -> uuid; fetch -> setof <table>/composite, stable).

-- 5a. fetch_membership_context() — everything the app shell needs in one
-- call: every org the caller belongs to, their role in it, and that org's
-- enabled module keys (for the entitlement-driven sidebar).
create type public.membership_context as (
  org_id uuid,
  org_name text,
  tenant_type text,
  role text,
  entitled_modules text[]
);

create or replace function public.fetch_membership_context()
returns setof public.membership_context
language sql
security definer
stable
set search_path = public
as $$
  select
    o.id,
    o.name,
    o.tenant_type,
    m.role,
    coalesce(
      array_agg(tm.module_key) filter (where tm.enabled),
      '{}'
    )
  from public.org_members m
  join public.organizations o on o.id = m.org_id
  left join public.tenant_modules tm on tm.org_id = o.id
  where m.user_id = auth.uid()
  group by o.id, o.name, o.tenant_type, m.role;
$$;

comment on function public.fetch_membership_context() is
  'App-shell load: every org the caller belongs to + role + entitled module keys. Scoped to auth.uid() internally.';

-- 5b. fetch_organization(p_org_id) — single-record fetch by id, per
-- CLAUDE.md rule 4 (direct .select().eq(id).single() fails RLS). Platform
-- admins can fetch any org (tenant management); everyone else only their own.
create or replace function public.fetch_organization(p_org_id uuid)
returns setof public.organizations
language sql
security definer
stable
set search_path = public
as $$
  select o.*
  from public.organizations o
  where o.id = p_org_id
    and (is_platform_admin() or p_org_id in (select my_org_ids()));
$$;

-- 5c. create_organization — license activation step 1. Platform-admin-only:
-- StructTech provisions tenants; a client never creates its own org row.
create or replace function public.create_organization(
  p_name text,
  p_tenant_type text,
  p_trade text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  if not is_platform_admin() then
    raise exception 'only a platform admin can create organizations';
  end if;

  insert into public.organizations (name, tenant_type, trade)
  values (p_name, p_tenant_type, p_trade)
  returning id into v_org_id;

  return v_org_id;
end;
$$;

-- 5d. add_org_member — license activation step 2. Platform-admin-only for
-- now (self-service org_invites acceptance is a separate, already-existing
-- flow this migration does not touch).
create or replace function public.add_org_member(
  p_org_id uuid,
  p_user_id uuid,
  p_role text,
  p_full_name text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_platform_admin() then
    raise exception 'only a platform admin can add org members';
  end if;

  insert into public.org_members (org_id, user_id, role, full_name)
  values (p_org_id, p_user_id, p_role, p_full_name)
  on conflict (org_id, user_id) do update
    set role = excluded.role,
        full_name = excluded.full_name;
end;
$$;

-- 5e. set_tenant_module — license activation step 3. Upsert so re-running
-- the Week 1 seed step is safe. Platform-admin-only.
create or replace function public.set_tenant_module(
  p_org_id uuid,
  p_module_key text,
  p_enabled boolean default true,
  p_config jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not is_platform_admin() then
    raise exception 'only a platform admin can set tenant module entitlements';
  end if;

  insert into public.tenant_modules (org_id, module_key, enabled, config)
  values (p_org_id, p_module_key, p_enabled, p_config)
  on conflict (org_id, module_key) do update
    set enabled = excluded.enabled,
        config = excluded.config,
        updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;
