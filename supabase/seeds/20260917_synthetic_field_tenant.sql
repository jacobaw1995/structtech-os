-- SYNTHETIC FIELD TENANT — a disposable org with the shape of one job, for exercising the field path as a
-- real `field` login. Track S · 2026-09-17. Controller ruling 2026-09-17 (Task 2). DATA, not schema.
-- Teardown (ONE statement): supabase/seeds/20260917_synthetic_field_tenant_teardown.sql
--
-- NOT Brothers Metal Roofing and not any client. No real person, address, phone or email appears here.
-- Every id is a literal, so the teardown keys on primary keys, never on a mutable name (§7.1 rule 1 / CLAUDE.md 10).
--
-- WHAT IS NOT HERE, ON PURPOSE: the crew login. Track S does not create accounts or handle passwords.
-- Jacob creates the auth user and attaches it with the statement in docs (§10 row, 2026-09-17). Until then
-- the org has one member: Jacob's existing account as owner, so the office side (upload, schedule, assign)
-- can be driven through the product, and Track X's §4 check 2 has an office signer.
-- The estimate is PRESENTED, not signed: a 'signed' status with no signature row would be a lie, and it
-- keeps the lines deletable so the teardown stays one statement.
begin;

insert into public.organizations (id, name, tenant_type)
values ('e0851ad8-35d6-4e17-b267-6cd35cb6f713', 'ZZ SYNTHETIC Field Test (not a client, disposable)', 'contractor');

insert into public.tenant_modules (org_id, module_key, enabled, config) values
  ('e0851ad8-35d6-4e17-b267-6cd35cb6f713', 'estimating',   true, '{}'::jsonb),
  ('e0851ad8-35d6-4e17-b267-6cd35cb6f713', 'coordination', true, '{}'::jsonb),
  ('e0851ad8-35d6-4e17-b267-6cd35cb6f713', 'field',        true, '{}'::jsonb);

-- Jacob's existing account (owner of StructTech) as owner here. Removed by the teardown.
insert into public.org_members (org_id, user_id, role, full_name, permissions)
values ('e0851ad8-35d6-4e17-b267-6cd35cb6f713', '09a25143-e069-401b-a49d-a6879fe43d7c', 'owner', null,
        public.default_permissions_for_role('owner'));

insert into public.deals (id, org_id, contact_name, first_name, last_name)
values ('a570f24c-63b7-4fb0-b0f1-97b80763c858', 'e0851ad8-35d6-4e17-b267-6cd35cb6f713',
        'SYNTHETIC Test Homeowner', 'SYNTHETIC', 'Test Homeowner');

insert into public.estimates (id, org_id, deal_id, status, contact_name, site_address, subtotal,
                              presented_total, presented_at, estimate_number, notes_terms)
values ('29e62f5f-d0bc-4d6b-8328-5e52cff67008', 'e0851ad8-35d6-4e17-b267-6cd35cb6f713',
        'a570f24c-63b7-4fb0-b0f1-97b80763c858', 'presented', 'SYNTHETIC Test Homeowner',
        '1 Synthetic Way, Testville', 1000, 1000, now(), 'SYN-1', 'Synthetic estimate for field testing.');

insert into public.estimate_line_items (org_id, estimate_id, description, quantity, unit, unit_price, sort_order)
values ('e0851ad8-35d6-4e17-b267-6cd35cb6f713', '29e62f5f-d0bc-4d6b-8328-5e52cff67008',
        'SYNTHETIC metal panels', 10, 'sq', 100, 0);

insert into public.jobs (id, org_id, deal_id, estimate_id, service_address_street, service_address_city,
                         service_address_state, service_address_zip)
values ('821cea1c-14d2-4aec-a719-685f6696573a', 'e0851ad8-35d6-4e17-b267-6cd35cb6f713',
        'a570f24c-63b7-4fb0-b0f1-97b80763c858', '29e62f5f-d0bc-4d6b-8328-5e52cff67008',
        '1 Synthetic Way', 'Testville', 'ZZ', '00000');

insert into public.work_orders (id, org_id, estimate_id, job_id, kind, trade) values
  ('029e4346-d30a-4da8-ad1d-1eee27d094ff', 'e0851ad8-35d6-4e17-b267-6cd35cb6f713',
   '29e62f5f-d0bc-4d6b-8328-5e52cff67008', '821cea1c-14d2-4aec-a719-685f6696573a', 'master', null),
  ('6af911f6-5c60-4041-9a4f-582f5f08434e', 'e0851ad8-35d6-4e17-b267-6cd35cb6f713',
   '29e62f5f-d0bc-4d6b-8328-5e52cff67008', '821cea1c-14d2-4aec-a719-685f6696573a', 'trade', 'SYNTHETIC Roofing');

insert into public.material_items (id, org_id, work_order_id, name, quantity, unit)
values ('e315e4d1-c108-45b3-9cd5-ace0e3ce47c8', 'e0851ad8-35d6-4e17-b267-6cd35cb6f713',
        '6af911f6-5c60-4041-9a4f-582f5f08434e', 'SYNTHETIC metal panels', 10, 'sq');

insert into public.schedule_blocks (id, org_id, work_order_id, crew_name, start_date, end_date)
values ('a2a0cf7e-c0b1-4186-8975-1a180cb9d7fa', 'e0851ad8-35d6-4e17-b267-6cd35cb6f713',
        '6af911f6-5c60-4041-9a4f-582f5f08434e', 'SYNTHETIC Crew',
        (now() at time zone 'America/New_York')::date, (now() at time zone 'America/New_York')::date + 2);

commit;
