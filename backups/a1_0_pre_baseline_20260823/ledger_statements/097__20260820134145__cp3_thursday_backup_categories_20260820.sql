-- CP3 Thursday — backup before backfilling wh_categories.image_url.
-- wh_categories is one of the five tables the storefront reads while serving, and
-- image_url is about to change on 25 of 28 rows. Rollback is a single UPDATE from
-- this snapshot.
create schema if not exists archive;
create table if not exists archive.wh_categories_backup_20260820 as select * from public.wh_categories;
