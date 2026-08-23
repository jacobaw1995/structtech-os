-- 15_wh-product-families-variations.sql
-- Phase 3B — additive parent/variation layer over the flattened catalog.
-- Target project : ejlhrykcdfcyeooooodx (structtech)
-- WH org         : "Material Matrix" 1084baa8-0355-4298-9b98-b876a7581173 (supplier)

-- ── Parents ─────────────────────────────────────────────────────────────────
create table if not exists public.wh_product_families (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid not null default '1084baa8-0355-4298-9b98-b876a7581173'
                      references public.organizations(id) on delete cascade,
  name              text not null,
  slug              text,
  product_type      text,
  catalog_section   text,
  compatible_systems text[] not null default '{}',
  image_url         text,
  display_order     int  not null default 0,
  status            text not null default 'live' check (status in ('live','draft','archived')),
  member_conflicts  jsonb,
  created_at        timestamptz not null default now()
);
create unique index if not exists wh_product_families_org_name_uk
  on public.wh_product_families (org_id, lower(name));

-- ── Variations (bridge to the shop's flattened wh_products row) ──────────────
create table if not exists public.wh_product_variations (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid not null default '1084baa8-0355-4298-9b98-b876a7581173'
                      references public.organizations(id) on delete cascade,
  family_id         uuid not null references public.wh_product_families(id) on delete cascade,
  source_product_id uuid references public.wh_products(id) on delete set null,
  name              text not null,
  sku               text,
  price             numeric(10,2),
  price_unit        text,
  gauge             text,
  finish            text,
  status            text not null default 'live' check (status in ('live','draft','special_order')),
  display_order     int  not null default 0,
  created_at        timestamptz not null default now()
);
create index if not exists wh_product_variations_family_idx
  on public.wh_product_variations (family_id);
create unique index if not exists wh_product_variations_source_uk
  on public.wh_product_variations (source_product_id) where source_product_id is not null;

-- ── RLS — mirrors the catalog pattern (migration 12) ────────────────────────
alter table public.wh_product_families   enable row level security;
alter table public.wh_product_variations enable row level security;

do $rls$
declare t text;
begin
  foreach t in array array['wh_product_families','wh_product_variations'] loop
    execute format('drop policy if exists "%1$s anon read" on public.%1$s', t);
    execute format('drop policy if exists "%1$s auth read" on public.%1$s', t);
    execute format('drop policy if exists "%1$s role insert" on public.%1$s', t);
    execute format('drop policy if exists "%1$s role update" on public.%1$s', t);
    execute format('drop policy if exists "%1$s admin delete" on public.%1$s', t);
    execute format('create policy "%1$s anon read" on public.%1$s for select to anon using (status = ''live'')', t);
    execute format('create policy "%1$s auth read" on public.%1$s for select using (auth.role() = ''authenticated'')', t);
    execute format('create policy "%1$s role insert" on public.%1$s for insert with check (org_id in (select public.my_org_ids()) and public.my_wh_role() in (''admin'',''assistant''))', t);
    execute format('create policy "%1$s role update" on public.%1$s for update using (org_id in (select public.my_org_ids()) and public.my_wh_role() in (''admin'',''assistant'')) with check (org_id in (select public.my_org_ids()) and public.my_wh_role() in (''admin'',''assistant''))', t);
    execute format('create policy "%1$s admin delete" on public.%1$s for delete using (org_id in (select public.my_org_ids()) and public.my_wh_role() = ''admin'')', t);
  end loop;
end $rls$;

-- ── Reviewed grouping seed (Phase 3B): product_id → family + variation label ──
create temp table _seed (
  source_product_id uuid, family_name text, variation_label text,
  family_order int, variation_order int
);
insert into _seed (source_product_id, family_name, variation_label, family_order, variation_order) values
  ('d7c44ebf-16aa-4463-9f32-a6421f9a99ad', 'Copper Screws', '1 1/2"', 9, 1),
  ('193354c6-27a0-41de-8c89-c693e6b98ed3', 'Metal Screws', '1 1/2"', 32, 1),
  ('9eaf65d1-ee09-472d-ba33-1f12e8da75ba', 'Stainless Screws', '1 1/2"', 52, 1),
  ('d578bbd2-b3d6-4f06-8b0e-579f3058b819', 'Copper Screws', '2"', 9, 2),
  ('18752520-c85c-409d-8050-dcf9c1eb3b9c', '26 GA Metal Panel', 'Standard', 1, 1),
  ('5cbee91c-9bf7-4c34-99e1-92be83490c35', 'Ag Panel', '28 GA Crinkle', 2, 1),
  ('6643265d-a0a4-4ef9-b371-3fcef31fddf5', 'Ag Panel', '28 GA Smooth', 2, 2),
  ('60156c48-db12-4255-b189-de1f167de702', 'Ag Panel Screws', 'Metal-to-Metal 1.5"', 3, 1),
  ('fc596301-77dc-42f6-9abb-dc00c5d0130f', 'Ag Panel Screws', 'Metal-to-Metal 3"', 3, 2),
  ('467d210e-6311-475e-b627-dfcffd862c2e', 'Ag Panel Screws', 'Metal-to-Wood 1.5"', 3, 4),
  ('655a8f16-6b6a-4f6c-b5f9-e7840a31a366', 'Ag Panel Screws', 'Metal-to-Wood 1"', 3, 3),
  ('662b65fc-a5a3-46af-9a25-3eeb18eba38d', 'Ag Panel Screws', 'Metal-to-Wood 2"', 3, 5),
  ('69f816de-4116-4fba-ab9a-da6d46db8f79', 'Aluminum Panel', 'Standard', 4, 1),
  ('7ce38441-fc02-415a-a36d-a40a9b71761f', 'Board & Batten', 'Premium', 5, 1),
  ('11a6f7c1-1e35-44ac-af1a-424d25ccd952', 'Board & Batten', 'Standard', 5, 2),
  ('439fbc90-26a1-480a-9729-9f4957b9f22d', 'Clear Light Panel (Sunlights)', 'Standard', 6, 1),
  ('25a1d801-98ab-426c-893f-6f6925a1ac06', 'Clear Light Ridge', 'Standard', 7, 1),
  ('78043fee-599c-4642-b4d0-d502eddba90f', 'Copper Panel', 'Standard', 8, 1),
  ('7f0f26f8-889a-48b7-86d3-a642d7adab24', 'Corners (4")', '26 GA Crinkle', 10, 1),
  ('9033e412-f00a-4bbf-8d8b-88cdb316541d', 'Corners (4")', '26 GA Smooth', 10, 2),
  ('b6056bea-681d-4ee4-81b8-9bb87a602bfb', 'Custom Trim / Specialty', 'Standard', 11, 1),
  ('1c51d597-032d-40d4-a6a3-ad6af90a5c46', 'Doors', '4'' AG Door', 12, 1),
  ('49851824-7357-42cf-b011-e41b9208b326', 'Doors', 'AG Entry Door', 12, 2),
  ('d2bb6954-160b-4a77-af11-f8133a0a7cb2', 'Doors', 'Fiberglass Door (Premium)', 12, 3),
  ('8f551d38-bd92-47b2-8e79-59a8d848a502', 'Doors', 'Fiberglass Door (Standard)', 12, 4),
  ('dbafac12-e81d-43ab-b961-21fff4d6ad57', 'Double Bubble Underlayment', 'Standard', 13, 1),
  ('5962283c-3578-4fd1-b700-ddc7b9fd9495', 'Drip Cap', '26 GA Crinkle', 14, 1),
  ('ab526061-5e9b-462c-b51f-fea447857ae3', 'Drip Cap', '26 GA Smooth', 14, 2),
  ('12cd2240-2bca-4456-b309-8058d9fad950', 'Drip Edge', '26 GA Crinkle', 15, 1),
  ('dfe8f8e6-75b8-4d89-8bb6-0af15a97abbc', 'Drip Edge', '26 GA Smooth', 15, 2),
  ('52c067c1-3ebf-4889-a0dd-b04f2e6dd13e', 'EM Seal', 'Standard', 16, 1),
  ('9922b129-afc4-4d62-8666-ba595b4fb0e4', 'End Wall', '26 GA Crinkle', 17, 1),
  ('35a6c3c3-1d9b-428c-93ad-21d4cf84ee39', 'End Wall', '26 GA Smooth', 17, 2),
  ('50dadd8d-7ab8-4d96-8429-6dff7262fe5f', 'F Channel', '26 GA Crinkle', 18, 1),
  ('3b7565e7-7dc4-4a54-ac74-eb04a7ce02be', 'F Channel', '26 GA Smooth', 18, 2),
  ('7265595d-6385-4378-961c-d16be0e58c92', 'F-J #1', '26 GA Crinkle', 19, 1),
  ('b22e108c-ebb7-4160-8420-41b3ed5ad95e', 'F-J #1', '26 GA Smooth', 19, 2),
  ('4a3d6d7b-024f-455f-a10c-e0969b048d47', 'F-J #2', '26 GA Crinkle', 20, 1),
  ('075842ba-14cd-43a4-b666-808eb3fc4c6c', 'F-J #2', '26 GA Smooth', 20, 2),
  ('16984a20-6680-4a09-bc5c-cb7e9a1a9e6c', 'Fascia Trim', '4" Crinkle', 21, 1),
  ('dd0b5208-d599-449e-9019-9958813afd70', 'Fascia Trim', '4" Smooth', 21, 2),
  ('c39f09f4-bb44-4141-9da9-9eeda52583e2', 'Fascia Trim', '5.5" Crinkle', 21, 3),
  ('a562110a-e9c4-419a-8689-22f5e17db1f4', 'Fascia Trim', '5.5" Smooth', 21, 4),
  ('400eb7f4-f653-4e49-803e-b7500b592e67', 'Fascia Trim', '8" Crinkle', 21, 5),
  ('c3feb367-cc16-4de5-8a85-5ffadaecc171', 'Fascia Trim', '8" Smooth', 21, 6),
  ('3210e6fa-2706-49f4-9624-89ec2317360f', 'Fascia Trim', 'W/J Crinkle', 21, 7),
  ('3c8c03ad-2887-49d2-8623-1125e3c10a3f', 'Fascia Trim', 'W/J Smooth', 21, 8),
  ('1cb44f00-e428-47bc-ad4e-87d6723ec98f', 'Flat Stock', 'Standard', 22, 1),
  ('0bf69866-9e77-4c88-b6ae-6cb06c86f143', 'FloVent Ridge Vent', 'Standard', 23, 1),
  ('68a54a5c-6d4f-4d3e-9f34-0d380ce7ddbd', 'Galvalume Panel', 'Standard', 24, 1),
  ('cfb10dab-f1f5-4324-9d59-03511e9a391a', 'Hi-Temp Roof Boot', 'Hi-Temp #3', 25, 1),
  ('a12ea492-405d-470f-99af-d818db5dd409', 'Hi-Temp Roof Boot', 'Hi-Temp #4', 25, 2),
  ('4f7a9873-9706-432a-ad86-9a9a2bd63b83', 'Hi-Temp Roof Boot', 'Hi-Temp #5', 25, 3),
  ('dcef870c-d9ea-4810-98de-407227d9970c', 'Hi-Temp Roof Boot', 'Hi-Temp #7', 25, 4),
  ('cda93a8b-0d31-45a1-8b33-2d5515a9aa2a', 'Hi-Temp Roof Boot', 'Hi-Temp #8', 25, 5),
  ('dbb6f073-8f33-48c1-833b-ce4e0de8a05b', 'Hi-Temp Roof Boot', 'Hi-Temp #9', 25, 6),
  ('a5bb4454-3809-4f44-8f7a-184048a944c5', 'Hip Cap', '26 GA Crinkle', 26, 1),
  ('6dbc0b63-a157-46cf-82ca-f4797202152e', 'Hip Cap', '26 GA Smooth', 26, 2),
  ('749cc0ed-7e38-417f-bda0-988ce826f14d', 'Inside Closures', 'Standard', 27, 1),
  ('37e46b9e-b308-4a19-ae8e-2d250549ecaf', 'Inside Corner', '26 GA Crinkle', 28, 1),
  ('33c4101d-d67a-4154-ac31-d5c79907cebf', 'Inside Corner', '26 GA Smooth', 28, 2),
  ('9e16142b-c9e5-475a-8251-a38667f98dd8', 'J-Trim', '26 GA Crinkle', 29, 1),
  ('2689a791-8a3d-4e91-a3eb-29cc247d43ee', 'J-Trim', '26 GA Smooth', 29, 2),
  ('cf3a8146-da17-4aba-b90c-7f0704a83305', 'Jamb Cover', '26 GA Crinkle', 30, 1),
  ('b062c12f-3148-4d41-b8f2-6999cbf23e55', 'Jamb Cover', '26 GA Smooth', 30, 2),
  ('aa320163-a6d1-4feb-8d3f-1e18ba44b721', 'Liner Panel', 'Standard', 31, 1),
  ('5c561fe9-4f12-4ae9-8fc1-ec5272ee6b48', 'Mini Corner (Residential Rake)', '26 GA Crinkle', 33, 1),
  ('aff048d7-d083-45e3-99ff-bc5587c3b7dc', 'Mini Corner (Residential Rake)', '26 GA Smooth', 33, 2),
  ('80fc072e-52be-4d85-9c41-6250aefc82e9', 'NovaFlex Roof Caulk', 'Alamo White', 34, 1),
  ('527f2db9-9a1f-4cbf-8dd0-c5c9941ac5d4', 'NovaFlex Roof Caulk', 'Black', 34, 2),
  ('66234c31-d52b-402e-8159-a08b3f57dd16', 'NovaFlex Roof Caulk', 'Clear', 34, 3),
  ('e25cfc69-2580-4874-9a09-8b6cfa37e361', 'NovaFlex Roof Caulk', 'Gray', 34, 4),
  ('9c49cf36-746d-4857-bdb5-42e324f43ca1', 'NovaFlex Roof Caulk', 'White', 34, 5),
  ('bce4d906-adb2-4234-85f2-044667cdc28e', 'Outside Closures', 'Standard', 35, 1),
  ('259556e1-3105-41fa-9b9d-5eb43487e3bc', 'Overhead Door Trim', '26 GA Crinkle', 36, 1),
  ('1dd067c8-7604-4ad0-9e7b-08996c2a2aa2', 'Overhead Door Trim', '26 GA Smooth', 36, 2),
  ('62f4371a-dcc2-4e74-b766-c8daa214597f', 'Rake Trim', '26 GA Crinkle', 37, 1),
  ('1821a870-6d27-4378-97dc-25f2fe8418d9', 'Rake Trim', '26 GA Smooth', 37, 2),
  ('74836343-7c53-497b-8d09-b7036d2174a3', 'Rat Guard', '26 GA Crinkle', 38, 1),
  ('14891bba-f30b-43e7-8809-e74ebcf9177b', 'Rat Guard', '26 GA Smooth', 38, 2),
  ('f675fbd9-ab83-459e-addb-0ad1d6dd31d3', 'Residential Valley', '26 GA Crinkle', 39, 1),
  ('0ff61fb3-691d-477d-8410-21ba577b2dac', 'Residential Valley', '26 GA Smooth', 39, 2),
  ('43397367-276f-416f-9fb5-6a7886c62d68', 'Ridge Cap', '26 GA Crinkle', 40, 1),
  ('c16121a1-94a4-4ffb-9b8d-d2cd02d502fe', 'Ridge Cap', '26 GA Smooth', 40, 2),
  ('b724ee69-413d-4d0d-881c-e225d19e8af9', 'Rivets', '100 Count', 41, 1),
  ('8f8add12-76f8-4d04-8e0f-1803683f8be9', 'Rivets', '25 Count', 41, 2),
  ('f29569e0-2af2-4e67-a46b-d4ba67578a75', 'Rivets', '50 Count', 41, 3),
  ('72e1b3cf-ea40-4ec9-8f37-9c850fcf13a3', 'Roof Boot', 'Boot #3', 42, 1),
  ('8d45ce90-0981-4457-849b-070779b38af7', 'Roof Boot', 'Boot #4', 42, 2),
  ('22bceb6b-ffd5-412c-baf2-f0f03cf41cfc', 'Roof Boot', 'Boot #5', 42, 3),
  ('b0677d32-98c1-4dc6-8d87-7af49852e74e', 'Roof Boot', 'Boot #6', 42, 4),
  ('6386aff6-d5be-408e-be7c-75047de515c4', 'Roof Boot', 'Boot #7', 42, 5),
  ('1291f952-d0bc-468f-b121-dcdebf6e6bc1', 'Roof Boot', 'Boot #8', 42, 6),
  ('f75e48ce-8181-4b5d-8a83-1bd7e852c4ce', 'Roof Boot', 'Boot #9', 42, 7),
  ('c79d091e-ae12-4c0f-97c1-30cd9a2a5888', 'Roof Vent', 'AG Panel Roof Vent', 43, 1),
  ('2aca3c94-a7dd-4375-a078-7d85bfcf266b', 'Round Track Cover', '26 GA Crinkle', 44, 1),
  ('f709a784-cbc4-4dea-b03c-ece1588ae81b', 'Round Track Cover', '26 GA Smooth', 44, 2),
  ('e7a64515-3d8a-4ba4-85db-4c99f5cc0da9', 'Side Wall', '26 GA Crinkle', 45, 1),
  ('0064358a-7b04-4841-9931-83e0e4df0259', 'Side Wall', '26 GA Smooth', 45, 2),
  ('c1a98ed0-8b82-4064-8ed4-b2dbb14225da', 'Skylight', 'Standard', 46, 1),
  ('bee502d7-2d15-4c89-bcf5-e4369d4d5cc4', 'Skylight Cap', 'Standard', 47, 1),
  ('64597a8b-93f3-4d0f-9309-c35311939b31', 'Sliding Door System', 'Standard', 48, 1),
  ('9a45abae-5a70-4398-811d-6810a5a97ac0', 'Snow Guards', 'Standard', 49, 1),
  ('6ef8f19f-a7b4-411e-a572-e85fba45aab7', 'Snow Rail', 'Standard', 50, 1),
  ('3a1e8c96-81e6-44a0-a11c-f3a36cdc6d85', 'Split Roof Boot', 'Split Boot #4', 51, 1),
  ('c22a2c4e-2d98-4a28-ac86-900400ee20d3', 'Split Roof Boot', 'Split Boot #7', 51, 2),
  ('0e1c5b3e-153b-4ff8-acc6-873f4b1cb4f7', 'Split Roof Boot', 'Split Boot #9', 51, 3),
  ('648e0d2e-5dc1-4d08-9d4b-b177e016999c', 'Stamped Panel', 'Standard', 53, 1),
  ('257d867e-ca70-480d-b89c-71150b8ffb0a', 'Standing Seam', '1.5" Seam', 54, 2),
  ('fff615a5-183b-4449-af08-b0abc255c4b5', 'Standing Seam', '1" Seam', 54, 1),
  ('fc5de548-f676-428d-b54a-246328d4f28c', 'Standing Seam', '2" Seam', 54, 3),
  ('e348e48a-2288-452b-8dd9-ddc8e498436f', 'Synthetic Underlayment', 'Standard', 55, 1),
  ('36a94aba-384b-49a6-94a8-10df74437d85', 'Thermo Guard', 'Standard', 56, 1),
  ('cad15403-498f-437d-a2d4-dd627879bb3a', 'Transition', '26 GA Crinkle', 57, 1),
  ('4f9f0536-2188-4cdb-9883-fd002a7a460f', 'Transition', '26 GA Smooth', 57, 2),
  ('d9bad6c4-d3d2-466e-b911-8593a998c386', 'Vented Closures', 'Standard', 58, 1),
  ('d36ef57d-7b2f-4a75-b293-065b5a0acbe6', 'Vented Soffit', 'Standard', 59, 1),
  ('ad565b8b-f594-4835-a1d8-6339a1feec45', 'Windows', '3x3 Window', 60, 1),
  ('9d4670f8-59d8-441b-a4ad-0c0f5026d880', 'Windows', '4x3 Window', 60, 2),
  ('2f84d260-f609-48eb-abc6-e767b7923167', 'Z Bar', '26 GA Crinkle', 61, 1),
  ('b5166ef6-7c7e-459d-8f57-0c17bfe0ee90', 'Z Bar', '26 GA Smooth', 61, 2);

-- ── Backfill families (idempotent) — metadata derived from bridged live rows ──
with members as (
  select s.family_name, s.family_order, p.*
  from _seed s join public.wh_products p on p.id = s.source_product_id
),
fam_sys as (
  select m.family_name, array_agg(distinct sys) filter (where sys is not null) as systems
  from members m, lateral unnest(coalesce(m.compatible_systems, '{}'::text[])) as sys
  group by m.family_name
),
fam as (
  select
    family_name,
    min(family_order) as family_order,
    (array_agg(distinct product_type)    filter (where product_type is not null))[1]    as product_type,
    count(distinct product_type)         filter (where product_type is not null)         as n_type,
    (array_agg(distinct catalog_section) filter (where catalog_section is not null))[1]  as catalog_section,
    count(distinct catalog_section)      filter (where catalog_section is not null)      as n_section,
    (array_agg(image_url)                filter (where image_url is not null and image_url <> ''))[1] as image_url,
    count(*) filter (where image_url is not null and image_url <> '')                    as n_photo,
    count(*)                                                                             as n_members,
    count(distinct coalesce(array_to_string(compatible_systems, ','), ''))               as n_sysset,
    bool_or(coalesce(active, true))                                                      as any_active
  from members group by family_name
)
insert into public.wh_product_families
  (org_id, name, slug, product_type, catalog_section, compatible_systems, image_url, display_order, status, member_conflicts)
select
  '1084baa8-0355-4298-9b98-b876a7581173'::uuid,
  f.family_name,
  nullif(regexp_replace(regexp_replace(lower(f.family_name), '[^a-z0-9]+', '-', 'g'), '(^-|-$)', '', 'g'), ''),
  f.product_type,
  f.catalog_section,
  coalesce(fs.systems, '{}'::text[]),
  f.image_url,
  f.family_order,
  case when f.any_active then 'live' else 'draft' end,
  nullif(jsonb_strip_nulls(jsonb_build_object(
    'product_type_mixed',   case when f.n_type    > 1 then true end,
    'catalog_section_mixed',case when f.n_section > 1 then true end,
    'systems_mixed',        case when f.n_sysset  > 1 then true end,
    'photo_partial',        case when f.n_photo > 0 and f.n_photo < f.n_members then true end
  )), '{}'::jsonb)
from fam f
left join fam_sys fs on fs.family_name = f.family_name
where not exists (
  select 1 from public.wh_product_families x
  where x.org_id = '1084baa8-0355-4298-9b98-b876a7581173'::uuid
    and lower(x.name) = lower(f.family_name)
);

-- ── Backfill variations (idempotent) — attributes from the bridged live row ───
insert into public.wh_product_variations
  (org_id, family_id, source_product_id, name, sku, price, price_unit, gauge, finish, status, display_order)
select
  p.org_id,
  fam.id,
  p.id,
  s.variation_label,
  p.sku,
  p.base_price,
  p.unit_type,
  p.gauge,
  p.finish,
  case when coalesce(p.active, true) then 'live' else 'draft' end,
  s.variation_order
from _seed s
join public.wh_products p          on p.id = s.source_product_id
join public.wh_product_families fam on fam.org_id = p.org_id and lower(fam.name) = lower(s.family_name)
where not exists (
  select 1 from public.wh_product_variations v where v.source_product_id = s.source_product_id
);

drop table if exists _seed;
