-- TEARDOWN — removes the synthetic field tenant in ONE statement. Track S · 2026-09-17.
-- Keyed on the org's primary key. Foreign keys to organizations are mostly NO ACTION, which PostgreSQL checks at
-- the END of the statement, so every data-modifying CTE below runs before any FK is checked: all or nothing.
-- It covers every table the seed and the field path write to. If someone has written rows elsewhere (a
-- signature, a sign link, a purchase order…), the statement FAILS on that table's foreign key and removes
-- NOTHING — loudly, with the table named — rather than leaving half an org. Files in the org-files bucket under
-- the prefix e0851ad8-35d6-4e17-b267-6cd35cb6f713/ are NOT rows this can delete (storage refuses direct deletes);
-- remove them through the Storage API first. The synthetic auth user is deleted separately, in the dashboard.
with
  ci  as (delete from public.check_ins                  where org_id = 'e0851ad8-35d6-4e17-b267-6cd35cb6f713' returning 1),
  pp  as (delete from public.production_packets         where org_id = 'e0851ad8-35d6-4e17-b267-6cd35cb6f713' returning 1),
  sb  as (delete from public.schedule_blocks            where org_id = 'e0851ad8-35d6-4e17-b267-6cd35cb6f713' returning 1),
  mi  as (delete from public.material_items             where org_id = 'e0851ad8-35d6-4e17-b267-6cd35cb6f713' returning 1),
  td  as (delete from public.take_off_decisions         where org_id = 'e0851ad8-35d6-4e17-b267-6cd35cb6f713' returning 1),
  wa  as (delete from public.work_order_crew_assignments where org_id = 'e0851ad8-35d6-4e17-b267-6cd35cb6f713' returning 1),
  cu  as (delete from public.crew_person_unavailability where org_id = 'e0851ad8-35d6-4e17-b267-6cd35cb6f713' returning 1),
  cm  as (delete from public.crew_memberships           where org_id = 'e0851ad8-35d6-4e17-b267-6cd35cb6f713' returning 1),
  cr  as (delete from public.crews                      where org_id = 'e0851ad8-35d6-4e17-b267-6cd35cb6f713' returning 1),
  cp  as (delete from public.crew_people                where org_id = 'e0851ad8-35d6-4e17-b267-6cd35cb6f713' returning 1),
  wo  as (delete from public.work_orders                where org_id = 'e0851ad8-35d6-4e17-b267-6cd35cb6f713' returning 1),
  jb  as (delete from public.jobs                       where org_id = 'e0851ad8-35d6-4e17-b267-6cd35cb6f713' returning 1),
  li  as (delete from public.estimate_line_items        where org_id = 'e0851ad8-35d6-4e17-b267-6cd35cb6f713' returning 1),
  en  as (delete from public.estimate_number_counters   where org_id = 'e0851ad8-35d6-4e17-b267-6cd35cb6f713' returning 1),
  es  as (delete from public.estimates                  where org_id = 'e0851ad8-35d6-4e17-b267-6cd35cb6f713' returning 1),
  da  as (delete from public.deal_activity              where org_id = 'e0851ad8-35d6-4e17-b267-6cd35cb6f713' returning 1),
  dn  as (delete from public.deal_notes                 where org_id = 'e0851ad8-35d6-4e17-b267-6cd35cb6f713' returning 1),
  fu  as (delete from public.follow_ups                 where org_id = 'e0851ad8-35d6-4e17-b267-6cd35cb6f713' returning 1),
  dl  as (delete from public.deals                      where org_id = 'e0851ad8-35d6-4e17-b267-6cd35cb6f713' returning 1)
delete from public.organizations where id = 'e0851ad8-35d6-4e17-b267-6cd35cb6f713';
-- org_members, tenant_modules and org_invites cascade from the organization.
