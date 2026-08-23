-- StructTech OS — CRM Depth Stage 5, Track B2: seed Isaac as a BMR member.
--
-- Context: docs/reference/STAGE5_GOLIVE_GATE.md, Track B2. Isaac's auth user
-- was created via a Supabase Auth dashboard invite (isaac@brothersmetalroofing.com,
-- id d63871d2-cb54-44b2-bac4-502d22a79d96), which fired the Track B1 trigger
-- and auto-created his profile — but with full_name defaulted to his email,
-- since a dashboard invite carries no user_meta_data. This migration corrects
-- that and adds his one org_members row.
--
-- Deliberately NOT touching staff_users — that table grants StructTech
-- platform-admin/cross-tenant access, and Isaac must stay BMR-only per
-- STAGE5_GOLIVE_GATE.md ("never as staff").
--
-- Verified live (7/19): my_org_ids() for Isaac = [BMR only]; is_staff() and
-- is_platform_admin() both false; sees all 8 BMR deals, 0 StructTech deals,
-- 0 audit_leads.
update public.profiles
set full_name = 'Isaac Smith', role = 'manager'
where id = 'd63871d2-cb54-44b2-bac4-502d22a79d96';

insert into public.org_members (org_id, user_id, role, full_name)
values ('9d32b5a9-e11e-401b-8fa7-969065b004ce', 'd63871d2-cb54-44b2-bac4-502d22a79d96', 'owner', 'Isaac Smith')
on conflict do nothing;
