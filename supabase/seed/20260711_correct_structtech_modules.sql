-- StructTech OS — correct StructTech's tenant_modules entitlements
--
-- NOT APPLIED. Corrects a mistake in the original bootstrap seed
-- (20260711_bootstrap_structtech_bmr.sql), which entitled StructTech's
-- internal org to all 7 modules. Per SCOPE.md §4's module registry,
-- estimating/coordination/field are contractor-only — StructTech reaches
-- them by operating inside a client tenant (e.g. BMR) via its agency_admin
-- membership there, not in its own workspace. StructTech's own entitlements
-- should be exactly: crm, scan, roadmap, delivery.
--
-- Targets the org by name + tenant_type rather than a hardcoded id, since
-- the id was generated (gen_random_uuid()) by the original seed and was
-- never recorded anywhere.

delete from public.tenant_modules
where module_key in ('estimating', 'coordination', 'field')
  and org_id = (
    select id
    from public.organizations
    where name = 'StructTech' and tenant_type = 'internal'
  );

-- Verify — expect exactly 4 rows: crm, delivery, roadmap, scan.
select module_key, enabled, config
from public.tenant_modules
where org_id = (
  select id
  from public.organizations
  where name = 'StructTech' and tenant_type = 'internal'
)
order by module_key;
