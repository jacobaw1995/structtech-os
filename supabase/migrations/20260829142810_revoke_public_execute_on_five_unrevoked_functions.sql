-- StructTech OS — 2026-08-29 policy pass. MIGRATION B of B.
--
-- Rule 7 debt. Five StructTech-owned functions in `public` still carry the
-- PostgreSQL default grant to PUBLIC — the leading `=X/postgres` entry in
-- `proacl`, with no grantee name before the `=`. Per rule 7 as amended 8/27,
-- that is NOT a grant to `anon`; anon executes them through its PUBLIC
-- membership, so a revoke naming only `anon` would be a no-op.
--
-- SEVERITY IS LOW AND SAYING SO IS PART OF THE RECORD: all five are SECURITY
-- INVOKER, so an anon caller executes with anon's own rights and gains nothing.
-- Three are trigger functions, which cannot be usefully invoked directly.
-- This is hygiene, closing the gap between rule 7 and the schema.
--
-- The `authenticated` carve-out test (rule 7), answered PER FUNCTION: the two
-- callable ones are reachable from application code, so `authenticated` KEEPS
-- EXECUTE. Only PUBLIC and anon are revoked.
--
-- Signatures copied from pg_get_function_identity_arguments(), never retyped
-- (rule 2).

revoke execute on function public.build_roadmap_levels(jsonb, integer) from public, anon;
revoke execute on function public.roadmap_playbook(text) from public, anon;
revoke execute on function public.bmr_ticket_touch() from public, anon;
revoke execute on function public.protect_roadmap_columns() from public, anon;
revoke execute on function public.touch_leads_updated_at() from public, anon;

-- The single `function_search_path_mutable` lint in the advisor set.
alter function public.bmr_ticket_touch() set search_path = public;
