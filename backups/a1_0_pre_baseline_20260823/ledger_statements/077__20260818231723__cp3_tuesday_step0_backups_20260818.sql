-- CP3 Tuesday — pre-migration backups for the four remaining additive migrations.
-- ALTERED by today's work : wh_product_families, wh_product_variations (type_id columns)
-- READ by today's work    : wh_products, wh_product_colors, wh_colors
-- CREATE TABLE AS SELECT takes only ACCESS SHARE on the sources, so the live
-- storefront keeps reading throughout.

create schema if not exists archive;

create table if not exists archive.wh_product_families_backup_20260818   as select * from public.wh_product_families;
create table if not exists archive.wh_product_variations_backup_20260818 as select * from public.wh_product_variations;
create table if not exists archive.wh_products_backup_20260818           as select * from public.wh_products;
create table if not exists archive.wh_product_colors_backup_20260818     as select * from public.wh_product_colors;
create table if not exists archive.wh_colors_backup_20260818             as select * from public.wh_colors;
