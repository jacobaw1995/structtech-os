-- ROLLBACK for 20260911 permissions_write_path.
-- Both objects are NEW as of this migration (confirmed against pg_proc before
-- applying: neither name existed), so the rollback is a drop list. Nothing
-- pre-existing is altered, and no data is written by the forward migration —
-- it adds a write PATH, it does not use it.
--
-- DROPPING set_member_capability removes the only way to grant or revoke an
-- individual capability. Stored permissions rows are untouched by this
-- rollback; anything already written through it stays written, which is
-- correct — those are deliberate grants, not an artefact of the migration.
drop function if exists public.set_member_capability(uuid, uuid, text, boolean);
drop function if exists public.role_capability_matrix();
