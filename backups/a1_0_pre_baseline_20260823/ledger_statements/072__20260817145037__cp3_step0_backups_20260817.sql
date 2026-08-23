-- CP3 step 0 — pre-migration-15 backups.
-- Snapshot of every table migration 15 reads, plus the tables the photo pipeline
-- will alter later today. Strictly additive: CREATE TABLE AS SELECT takes only an
-- ACCESS SHARE lock on the sources, so the live storefront keeps reading throughout.
create schema if not exists archive;

create table if not exists archive.wh_products_backup_20260817          as select * from public.wh_products;
create table if not exists archive.wh_product_colors_backup_20260817    as select * from public.wh_product_colors;
create table if not exists archive.wh_categories_backup_20260817        as select * from public.wh_categories;
create table if not exists archive.wh_category_products_backup_20260817 as select * from public.wh_category_products;
