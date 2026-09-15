-- ROLLBACK for 2026-09-14 remote_signing_spine.
-- signatures.sign_token was captured from information_schema and pg_constraint on the LIVE
-- database 2026-09-14 BEFORE the change: `sign_token text NULL`, constraint
-- `signatures_sign_token_key UNIQUE (sign_token)`, NULL on all 4 rows, referenced by 0 functions.
--
-- RESTORING THIS RE-OPENS: two signatures on one estimate (no uniqueness, no row lock); a signature
-- row editable after signing; a direct insert of a signature on an estimate that was never
-- presented; and a plaintext token column on a row that only exists after signing.
--
-- DATA LOSS ON ROLLBACK: every estimate_sign_links row (issued links, their expiry, revocations and
-- uses) and signatures.sign_link_id (which signatures arrived by link). Export them first if any
-- link has been issued.

drop function if exists public.sign_estimate_by_link(text, text, text, text, text);
drop function if exists public.signing_link_view(text);
drop function if exists public.revoke_estimate_sign_link(uuid);
drop function if exists public.create_estimate_sign_link(uuid, integer);
drop function if exists public.signing_link_resolve(text);
drop function if exists public.estimate_signing_document(uuid);

drop trigger if exists signatures_guard_insert on public.signatures;
drop trigger if exists signatures_after_insert on public.signatures;
drop trigger if exists signatures_immutable on public.signatures;
drop function if exists public.signatures_guard_insert();
drop function if exists public.signatures_after_insert();
drop function if exists public.signatures_immutable();

drop trigger if exists estimate_sign_links_immutable on public.estimate_sign_links;
drop function if exists public.estimate_sign_links_immutable();

drop index if exists public.signatures_one_per_estimate;
alter table public.signatures drop column if exists sign_link_id;
drop table if exists public.estimate_sign_links;

alter table public.signatures add column sign_token text null;
alter table public.signatures add constraint signatures_sign_token_key unique (sign_token);
