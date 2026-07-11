-- StructTech OS — rollback for 20260711120000_foundation_multitenancy.sql
--
-- NOT APPLIED. Safety net in place of a data backup (Docker/pg_dump/
-- supabase CLI dump aren't available in this environment). Run this
-- manually in the Supabase SQL editor ONLY if the foundation migration
-- needs to be reversed after being applied. It is not a forward migration
-- and is intentionally kept out of supabase/migrations/ so tooling that
-- walks that directory in order never applies it automatically.
--
-- Reverses exactly what 20260711120000 added: is_platform_admin(),
-- tenant_modules (table + policies), the 5 RPCs, the membership_context
-- type, the org_members role expansion, and organizations.tenant_type.
-- Does NOT touch the separate CRM org_id backfill migration (not applied
-- in this pass) or any pre-existing table/policy/function
-- (organizations, org_members, my_org_ids(), is_staff(), ...).
--
-- Order matters: drop things that reference an object before dropping the
-- object itself.
--   1. RPCs (fetch_membership_context/fetch_organization are LANGUAGE SQL
--      and get a real pg_depend dependency on the tables they query at
--      creation time; drop these before the table/type they touch).
--   2. The membership_context composite type (fetch_membership_context
--      returned it — must go after that function).
--   3. tenant_modules (drops its own RLS policies with it).
--   4. is_platform_admin() (referenced by tenant_modules' policies and by
--      the plpgsql RPCs above — safe to drop once both are gone).
--   5. org_members.role — restore the original 2-value CHECK.
--   6. organizations.tenant_type — drop the column (takes its CHECK and
--      comment with it).

-- ============================================================================
-- 1. Drop the 5 RPCs
-- ============================================================================
drop function if exists public.fetch_membership_context();
drop function if exists public.fetch_organization(uuid);
drop function if exists public.create_organization(text, text, text);
drop function if exists public.add_org_member(uuid, uuid, text, text);
drop function if exists public.set_tenant_module(uuid, text, boolean, jsonb);

-- ============================================================================
-- 2. Drop the composite type
-- ============================================================================
drop type if exists public.membership_context;

-- ============================================================================
-- 3. Drop tenant_modules (its "member read own" / "platform admin manage"
-- policies go with it — nothing else references this table)
-- ============================================================================
drop table if exists public.tenant_modules;

-- ============================================================================
-- 4. Drop is_platform_admin()
-- ============================================================================
drop function if exists public.is_platform_admin();

-- ============================================================================
-- 5. org_members — restore the original role CHECK
-- ============================================================================
-- NOT VALID here (the original constraint wasn't NOT VALID) is a deliberate
-- deviation for THIS rollback script specifically: if seed data introduced
-- any of the new role values (admin/office/field/client_portal_viewer/
-- agency_admin) before this runs, a validating ADD CONSTRAINT would fail
-- outright. NOT VALID lets the rollback itself always succeed; run
-- `alter table public.org_members validate constraint org_members_role_check;`
-- afterward once those rows are reassigned back to owner/member, if needed.
alter table public.org_members
  drop constraint if exists org_members_role_check;

alter table public.org_members
  add constraint org_members_role_check
  check (role in ('owner', 'member'))
  not valid;

comment on column public.org_members.role is null;

-- ============================================================================
-- 6. organizations — drop tenant_type
-- ============================================================================
alter table public.organizations
  drop column if exists tenant_type;
