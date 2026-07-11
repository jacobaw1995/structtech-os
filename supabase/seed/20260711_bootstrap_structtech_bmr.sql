-- StructTech OS — Week 1 bootstrap seed
--
-- NOT APPLIED. Run AFTER 20260711120000_foundation_multitenancy.sql, in the
-- Supabase SQL editor (runs as the postgres role, bypasses RLS — required,
-- since create_organization()/add_org_member() both gate on an existing
-- platform admin, and none exists yet. This is the one-time bootstrap
-- exception documented in that migration's header comment).
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
-- 1. Create StructTech's internal org + jacob@structtek.com as its owner
-- ============================================================================
-- Single statement (data-modifying CTE) so the generated org id never has to
-- be copied by hand between statements.
with new_org as (
  insert into public.organizations (name, tenant_type, trade)
  values ('StructTech', 'internal', null)
  returning id
)
insert into public.org_members (org_id, user_id, role, full_name)
select id, '09a25143-e069-401b-a49d-a6879fe43d7c'::uuid, 'owner', 'Jacob Walker'
from new_org;

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
-- 4. Verify — expect exactly 2 rows: StructTech/owner, BMR/agency_admin,
-- both jacob@structtek.com. The jacobaw1995@gmail.com row should be gone.
-- ============================================================================
select
  o.name as org_name,
  o.tenant_type,
  m.role,
  m.user_id,
  m.full_name
from public.org_members m
join public.organizations o on o.id = m.org_id
order by o.tenant_type desc, o.name;
