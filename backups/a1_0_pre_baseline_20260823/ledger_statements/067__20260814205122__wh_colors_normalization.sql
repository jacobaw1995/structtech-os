-- 12_wh-colors-normalization (backups already created out-of-band)

-- 1. Schema additions
alter table wh_colors
  add column if not exists color_family      text,
  add column if not exists available_finishes text[] not null default array['smooth']::text[];

alter table wh_colors drop constraint if exists wh_colors_available_finishes_chk;
alter table wh_colors
  add constraint wh_colors_available_finishes_chk
  check (available_finishes <@ array['smooth','textured']::text[]
         and array_length(available_finishes, 1) >= 1);

-- 2. Remap links retired -> survivor, collision-safe
with m(retired, survivor) as (values
  ('167f1057-abc0-4de2-a3c4-63c5c6f714ce'::uuid,'1f22048a-da0a-4a31-9263-6240a3b27715'::uuid),
  ('8f0bb59b-54f0-445b-8761-f3c7038c6c12','cbadaa21-88f1-4ef5-9616-ad7fc6dfa5ac'),
  ('6db69806-bfe6-48e4-abc4-3a34c56a935c','c00e4671-0b77-4c6f-a504-305f1504434c'),
  ('a47c5980-6539-411d-a91b-3d69875eebec','a5f3cc66-af2c-416a-ae11-5b1179bf4da2'),
  ('24866f27-ff25-4b63-97fe-086907d043fc','6b96eea1-1046-466a-838a-8ca0a180a908'),
  ('76b350b9-8625-4553-b123-ee42829f1764','faa8100a-b523-4b9c-b047-a6b1b1248903'),
  ('0ecb2d8d-dde2-4c2d-b7d6-6fed67f552e4','1de906f0-dc27-4678-8417-881d592f873f'),
  ('c75b5a44-69bd-4e82-ba70-91a09352c66b','da5bc97e-63aa-432d-8226-eaae267569c4'),
  ('a3cc6c3d-b2d3-4ae4-8212-3d691a1aef69','58980f96-1418-4207-8059-4d956857be28'),
  ('a80260db-6eea-4623-ab0f-16e3eb9ccdac','732c7e68-9f45-4ee6-9fe0-d969daccf7c0'),
  ('b9b792e7-918e-4958-a89f-331eb7f99271','fbf08598-b3a7-4c36-8281-62dd1972ce70'),
  ('bcec814d-30b9-47de-b75f-776b5171d53e','1f22048a-da0a-4a31-9263-6240a3b27715'),
  ('4218d9e6-8ba2-4bec-805e-accab8f84368','58980f96-1418-4207-8059-4d956857be28'),
  ('63ace80b-3f68-4f2a-85b2-454b2a56fb20','4262bdd7-061e-49b2-8917-383fb0c78f6b'),
  ('4d49a582-2f63-4304-aec1-42928381ded3','fbf08598-b3a7-4c36-8281-62dd1972ce70'),
  ('df4808a3-a8b2-4e5c-8fb5-e8aa3cdac573','660d1dcb-8062-4fba-a622-7325a48a8ca0'),
  ('a33483a0-e15e-4db3-bef5-e174d960d06b','1de906f0-dc27-4678-8417-881d592f873f'),
  ('752d896e-455d-48aa-bd84-9535895e2550','1de906f0-dc27-4678-8417-881d592f873f'),
  ('cabd27de-865c-4c3e-84e0-2b04c18552b3','488599a3-c0cd-47bc-8e8e-4b2afbf7d5ed'),
  ('34addc7a-6b34-4579-ba8c-ba33358cbd5b','488599a3-c0cd-47bc-8e8e-4b2afbf7d5ed'),
  ('df09d032-93c0-4adb-80fd-aa6ce9fcf255','b41583ee-9bf8-4d5e-8f36-98e8cd81ea89'),
  ('171e0750-1b53-472a-814e-80e4d2c07244','a5f3cc66-af2c-416a-ae11-5b1179bf4da2'),
  ('a60cb5bf-7101-48fa-8a76-6785d8c9f98b','faa8100a-b523-4b9c-b047-a6b1b1248903')
),
ins as (
  insert into wh_product_colors (product_id, color_id, price_modifier)
  select pc.product_id, m.survivor, max(pc.price_modifier)
  from wh_product_colors pc
  join m on pc.color_id = m.retired
  group by pc.product_id, m.survivor
  on conflict (product_id, color_id) do nothing
  returning 1
)
delete from wh_product_colors pc
using m
where pc.color_id = m.retired;

-- 3. Retire folded/duplicate rows (24: 23 remapped + Grey)
update wh_colors set active = false
where id in (
  '167f1057-abc0-4de2-a3c4-63c5c6f714ce','8f0bb59b-54f0-445b-8761-f3c7038c6c12',
  '6db69806-bfe6-48e4-abc4-3a34c56a935c','a47c5980-6539-411d-a91b-3d69875eebec',
  '24866f27-ff25-4b63-97fe-086907d043fc','76b350b9-8625-4553-b123-ee42829f1764',
  '0ecb2d8d-dde2-4c2d-b7d6-6fed67f552e4','c75b5a44-69bd-4e82-ba70-91a09352c66b',
  'a3cc6c3d-b2d3-4ae4-8212-3d691a1aef69','a80260db-6eea-4623-ab0f-16e3eb9ccdac',
  'b9b792e7-918e-4958-a89f-331eb7f99271','bcec814d-30b9-47de-b75f-776b5171d53e',
  '4218d9e6-8ba2-4bec-805e-accab8f84368','63ace80b-3f68-4f2a-85b2-454b2a56fb20',
  '4d49a582-2f63-4304-aec1-42928381ded3','df4808a3-a8b2-4e5c-8fb5-e8aa3cdac573',
  'a33483a0-e15e-4db3-bef5-e174d960d06b','752d896e-455d-48aa-bd84-9535895e2550',
  'cabd27de-865c-4c3e-84e0-2b04c18552b3','34addc7a-6b34-4579-ba8c-ba33358cbd5b',
  'df09d032-93c0-4adb-80fd-aa6ce9fcf255','171e0750-1b53-472a-814e-80e4d2c07244',
  'a60cb5bf-7101-48fa-8a76-6785d8c9f98b','3d33abb1-1d58-4ae2-adac-1a6fba41640b'
);

-- 4. Survivor metadata
update wh_colors as c
set name               = v.nm,
    hex_code           = v.hex,
    color_family       = v.fam,
    display_order      = v.ord,
    available_finishes = case when v.fin = 'ST'
                              then array['smooth','textured']::text[]
                              else array['smooth']::text[] end
from (values
  ('488599a3-c0cd-47bc-8e8e-4b2afbf7d5ed','Arctic White',          '#f0f0ec','White / Off-White', 10,'S'),
  ('aa8dae07-2e39-4dbd-99bd-f2c5ee90bea1','Alamo White',           '#d4cfd3','White / Off-White', 11,'S'),
  ('11361127-31c1-4684-b9e0-d315b121116c','Arctic White - G100',   '#dae6e5','White / Off-White', 12,'S'),
  ('31b0f62b-abdc-45e0-9127-f2c3b07fdf7a','Ivory',                 '#f2e0c3','White / Off-White', 13,'S'),
  ('1f22048a-da0a-4a31-9263-6240a3b27715','Ash Gray',              '#b2beb5','Gray',              20,'ST'),
  ('5b17aee3-0ac3-498c-9c08-7a2f48fa80e4','Pewter Gray',           '#8b8487','Gray',              21,'S'),
  ('85483166-32c3-44b6-9d88-4b7504a3807c','Gray',                  '#808080','Gray',              22,'S'),
  ('c00e4671-0b77-4c6f-a504-305f1504434c','Charcoal',              '#615b5d','Black & Charcoal',  30,'ST'),
  ('1de906f0-dc27-4678-8417-881d592f873f','Black',                 '#252525','Black & Charcoal',  31,'ST'),
  ('cbadaa21-88f1-4ef5-9616-ad7fc6dfa5ac','Burnished Slate',       '#504541','Brown & Bronze',    40,'ST'),
  ('a5f3cc66-af2c-416a-ae11-5b1179bf4da2','Cocoa Brown',           '#8b4513','Brown & Bronze',    41,'ST'),
  ('faa8100a-b523-4b9c-b047-a6b1b1248903','Buckskin',              '#ae8f8f','Tan & Beige',       50,'ST'),
  ('fbf08598-b3a7-4c36-8281-62dd1972ce70','Taupe/Clay',            '#7a685b','Tan & Beige',       51,'ST'),
  ('4262bdd7-061e-49b2-8917-383fb0c78f6b','Lightstone',            '#c9b6aa','Tan & Beige',       52,'S'),
  ('6b96eea1-1046-466a-838a-8ca0a180a908','Rustic Red',            '#7b2e28','Red',               60,'ST'),
  ('da5bc97e-63aa-432d-8226-eaae267569c4','Burgundy',              '#482a32','Red',               61,'ST'),
  ('660d1dcb-8062-4fba-a622-7325a48a8ca0','Bright Red',            '#bf2b2f','Red',               62,'S'),
  ('58980f96-1418-4207-8059-4d956857be28','Hunter Green',          '#2a5138','Green',             70,'ST'),
  ('83f35804-8089-460a-a9fe-771fae13d201','Dark Green',            '#355e3b','Green',             71,'S'),
  ('1f6076a8-ef21-4e70-966a-e347c207910e','Ocean Blue',            '#3d5f71','Blue',              80,'S'),
  ('732c7e68-9f45-4ee6-9fe0-d969daccf7c0','Gallery Blue',          '#9bbce4','Blue',              81,'ST'),
  ('b41583ee-9bf8-4d5e-8f36-98e8cd81ea89','Copper Metallic',       '#b07840','Metallic & Bare',   90,'S'),
  ('fae8b5ab-5db2-4b3a-a14a-381bc755aed8','Clear',                 null,     null,                99,'S')
) as v(id, nm, hex, fam, ord, fin)
where c.id = v.id::uuid;
