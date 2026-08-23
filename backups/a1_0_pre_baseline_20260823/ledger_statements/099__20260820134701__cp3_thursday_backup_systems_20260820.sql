-- Backup before re-pointing wh_systems.hero_image_url off the sunset project.
-- wh_systems is read by the storefront while serving.
create schema if not exists archive;
create table if not exists archive.wh_systems_backup_20260820 as select * from public.wh_systems;
