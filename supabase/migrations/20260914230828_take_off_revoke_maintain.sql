-- CORRECTIVE to 20260914230647 material_take_off_spine. Track S · 2026-09-14.
-- The spine revoked INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER from `authenticated` on
-- take_off_decisions and take_off_lines but not MAINTAIN (PostgreSQL 17's `m`), leaving both at
-- `authenticated=rm`. MEASURED house baseline across the 52 owned tables and views:
-- 44 carry `authenticated=arwd` (no MAINTAIN). Found by reading relacl after the apply, not by
-- the advisor, which has no rule for MAINTAIN. Rollback: grant maintain on both back to
-- authenticated.
revoke maintain on table public.take_off_decisions from authenticated;
revoke maintain on table public.take_off_lines from authenticated;

do $$
begin
  if (select relacl::text from pg_class where oid = 'public.take_off_decisions'::regclass) ~ 'authenticated=[a-zA-Z]*m'
     or (select relacl::text from pg_class where oid = 'public.take_off_lines'::regclass) ~ 'authenticated=[a-zA-Z]*m'
  then raise exception 'authenticated still holds MAINTAIN on a take-off object'; end if;
end $$;