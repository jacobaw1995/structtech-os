-- ROLLBACK for 20260929025035_special_trip_log.
-- Drops the log entirely. Written before the migration applied.
--
-- READ THIS BEFORE RUNNING IT: this DESTROYS every recorded special trip. There is no other
-- copy — the prose path it replaces holds 0 rows and always did. If any trips have been
-- recorded, export them first; a count nobody can reproduce is the thing this table exists
-- to prevent.
drop function if exists public.delete_special_trip(uuid);
drop function if exists public.record_special_trip(uuid, text, date, text);
drop table if exists public.special_trips;
