-- Phase A foundation (2026-08-16): close anon exposure on the 8/14 colour-normalisation
-- backups WITHOUT destroying them. Verification showed 491 of 831 product_colour mappings
-- differ from live, so these tables are the only record of the pre-normalisation state.
-- Moving them out of the public schema removes anon/authenticated reachability entirely.

create schema if not exists archive;

-- no grants to anon/authenticated: PostgREST cannot see this schema at all
revoke all on schema archive from anon, authenticated;
alter default privileges in schema archive revoke all on tables from anon, authenticated;

alter table public.wh_colors_backup_20260814 set schema archive;
alter table public.wh_product_colors_backup_20260814 set schema archive;

revoke all on all tables in schema archive from anon, authenticated;

comment on schema archive is 'Point-in-time data snapshots kept out of the API surface. Not exposed to anon/authenticated. Safe to prune once a change is verified in production.';
comment on table archive.wh_colors_backup_20260814 is 'Pre-normalisation snapshot of wh_colors taken 2026-08-14. Retained because 491/831 product-colour mappings changed during normalisation; this is the only record of the prior state.';
comment on table archive.wh_product_colors_backup_20260814 is 'Pre-normalisation snapshot of wh_product_colors taken 2026-08-14. 491 of 831 pairs differ from live.';
