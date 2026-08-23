-- CP3 Wednesday step 0 — backups before the editor write path.
-- Families/variations changed since the 0818 snapshot (type_id added), and today
-- adds image_url plus the first RPC that writes wh_products from the admin.
-- wh_products / wh_product_colors / wh_category_products are all now WRITE targets
-- of the dual-write RPC, so they are backed up as well.

create schema if not exists archive;

create table if not exists archive.wh_product_families_backup_20260819   as select * from public.wh_product_families;
create table if not exists archive.wh_product_variations_backup_20260819 as select * from public.wh_product_variations;
create table if not exists archive.wh_products_backup_20260819           as select * from public.wh_products;
create table if not exists archive.wh_product_colors_backup_20260819     as select * from public.wh_product_colors;
create table if not exists archive.wh_category_products_backup_20260819  as select * from public.wh_category_products;
create table if not exists archive.wh_variation_colors_backup_20260819   as select * from public.wh_variation_colors;
create table if not exists archive.wh_price_history_backup_20260819      as select * from public.wh_price_history;
