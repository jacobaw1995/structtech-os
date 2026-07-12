-- StructTech OS — Week 1 bootstrap seed
--
-- NOT APPLIED. Run AFTER 20260711120000_foundation_multitenancy.sql, in the
-- Supabase SQL editor (runs as the postgres role, bypasses RLS — required,
-- since create_organization()/add_org_member()/set_tenant_module() all gate
-- on an existing platform admin (is_platform_admin()), and none exists yet
-- — auth.uid() is also null in the SQL editor, so is_platform_admin() would
-- be false regardless. This is the one-time bootstrap exception documented
-- in the foundation migration's header comment: direct INSERTs here, RPCs
-- for everything after.
--
-- Landscape this is built from (confirmed via read-only inspection,
-- 2026-07-11):
--   organizations: exactly one row — Brothers Metal Roofing
--     (9d32b5a9-e11e-401b-8fa7-969065b004ce), no StructTech row yet.
--   org_members: exactly one row — jacobaw1995@gmail.com as owner of BMR.
--   auth.users: two accounts —
--     jacobaw1995@gmail.com (f1bcae81-1325-4301-a7aa-b9b8012965f9), no
--       staff_users row.
--     jacob@structtek.com (09a25143-e069-401b-a49d-a6879fe43d7c), the
--       existing staff_users admin.
--
-- Decision: jacob@structtek.com becomes the seeded platform identity — owner
-- of StructTech's new internal org, agency_admin inside BMR. The
-- jacobaw1995@gmail.com owner-of-BMR row was bootstrap scaffolding from
-- before this model existed; dropped here. BMR's real owner membership
-- (Isaac's account) gets added later, whenever that account exists.

-- ============================================================================
-- 1. Create StructTech's internal org, jacob@structtek.com as its owner, and
-- its module entitlements — one statement (chained data-modifying CTEs) so
-- the generated org id never has to be copied by hand. The final insert
-- explicitly joins through new_owner (rather than just new_org) so its
-- execution is guaranteed by the join, not by the (also-correct, but less
-- obvious on a read-through) rule that Postgres always executes
-- data-modifying CTEs even when their output goes unreferenced.
--
-- crm/scan/roadmap/delivery only, per SCOPE.md §4's module registry:
-- estimating/coordination/field are contractor-only. StructTech reaches
-- those by operating inside a client tenant (agency_admin membership),
-- never in its own workspace.
-- ============================================================================
with new_org as (
  insert into public.organizations (name, tenant_type, trade)
  values ('StructTech', 'internal', null)
  returning id
),
new_owner as (
  insert into public.org_members (org_id, user_id, role, full_name)
  select id, '09a25143-e069-401b-a49d-a6879fe43d7c'::uuid, 'owner', 'Jacob Walker'
  from new_org
  returning org_id
)
insert into public.tenant_modules (org_id, module_key, enabled)
select new_owner.org_id, module_key, true
from new_owner, unnest(array[
  'crm', 'scan', 'roadmap', 'delivery'
]) as module_key;

-- ============================================================================
-- 2. jacob@structtek.com operates inside BMR as agency_admin
-- ============================================================================
-- (BMR's org id is already known from the landscape inspection — no lookup
-- needed. on conflict makes this safe to re-run.)
insert into public.org_members (org_id, user_id, role, full_name)
values (
  '9d32b5a9-e11e-401b-8fa7-969065b004ce',
  '09a25143-e069-401b-a49d-a6879fe43d7c',
  'agency_admin',
  'Jacob Walker'
)
on conflict (org_id, user_id) do update
  set role = excluded.role,
      full_name = excluded.full_name;

-- ============================================================================
-- 3. Drop the stale jacobaw1995@gmail.com owner-of-BMR row
-- ============================================================================
delete from public.org_members
where org_id = '9d32b5a9-e11e-401b-8fa7-969065b004ce'
  and user_id = 'f1bcae81-1325-4301-a7aa-b9b8012965f9';

-- ============================================================================
-- 4. BMR entitlements — crm/estimating/coordination/field, plus delivery
-- enabled read-only (the client's "StructTech Roadmap" view, per SCOPE.md's
-- module registry). Deliberately no scan or roadmap — internal-only modules.
-- ============================================================================
insert into public.tenant_modules (org_id, module_key, enabled)
select '9d32b5a9-e11e-401b-8fa7-969065b004ce'::uuid, module_key, true
from unnest(array['crm', 'estimating', 'coordination', 'field']) as module_key;

insert into public.tenant_modules (org_id, module_key, enabled, config)
values (
  '9d32b5a9-e11e-401b-8fa7-969065b004ce',
  'delivery',
  true,
  '{"read_only": true}'::jsonb
);

-- ============================================================================
-- 5. Verify — expect StructTech/owner with exactly crm/delivery/roadmap/scan,
-- BMR/agency_admin with exactly crm/estimating/coordination/field/delivery.
-- The jacobaw1995@gmail.com row should be gone entirely.
-- ============================================================================
select
  o.name as org_name,
  o.tenant_type,
  m.role,
  m.full_name,
  array_agg(distinct tm.module_key order by tm.module_key) as enabled_modules
from public.org_members m
join public.organizations o on o.id = m.org_id
left join public.tenant_modules tm on tm.org_id = o.id and tm.enabled
group by o.name, o.tenant_type, m.role, m.full_name
order by o.tenant_type desc, o.name;
