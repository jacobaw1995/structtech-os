-- P0 INCIDENT — 2026-08-28. STEPS 2 AND 4.
--
-- Step 1 (separate migration, applied first and unconditionally) dropped the
-- anonymous UPDATE policy. This closes the anonymous READ and withdraws the
-- table privileges that made both reachable.
--
-- WHY THE BUG EXISTED, IN THE ORIGINAL AUTHOR'S OWN WORDS. Migration
-- 20260702012359 shipped the policy with this comment above it:
--
--     "Anyone with the anon key can READ a roadmap only if they know the token
--      (enforced by querying eq token; RLS allows select but the token is
--      unguessable)"
--
-- That is the false belief written down: RLS CANNOT SEE A CLIENT-SIDE
-- `.eq('token', …)` FILTER. A query filter narrows a RESULT SET; it does not
-- constrain a POLICY. And the token was in the row the open policy returned, so
-- "unguessable" bought nothing — every token came back free with the first read.
--
-- THE NAME IS THE OTHER HALF. The policy is called "read roadmap by token" and
-- tests no token. It survived the 2026-07-07 anon cutover
-- (20260707013828_drop_anon_admin_access) which swept seventeen tables — that
-- migration named `client_roadmaps "insert roadmap"` as deliberately skipped and
-- never mentioned these two at all, because their names do not contain "anon".
-- A POLICY NAME IS NOT A CONTROL, and a name describing an intent the SQL does
-- not implement is worse than no name: it stops the reader looking.

-- ---------------------------------------------------------------------------
-- 1 · THE REPLACEMENT READ PATH
-- ---------------------------------------------------------------------------
-- The correct shape for "one record, addressed by an unguessable secret" is a
-- SECURITY DEFINER function that takes the secret as an ARGUMENT — because then
-- the match happens inside the database, where it is a real constraint, instead
-- of in a client-side filter the policy never sees.
--
-- WHAT IT DOES NOT RETURN, deliberately: `token` (a page that renders a record
-- must never hand back the credential that addressed it), `lead_id` and
-- `org_id` (internal joins, nothing a client page renders).

create or replace function public.fetch_roadmap_by_token(p_token text)
returns table (
  id                   uuid,
  client_name          text,
  company              text,
  trade                text,
  crew_size            integer,
  score                integer,
  risk_level           text,
  revenue_leak_monthly integer,
  levels               jsonb,
  status               text,
  created_at           timestamptz,
  updated_at           timestamptz
)
language sql
stable
security definer
set search_path to 'public'
as $function$
  select r.id, r.client_name, r.company, r.trade, r.crew_size, r.score,
         r.risk_level, r.revenue_leak_monthly, r.levels, r.status,
         r.created_at, r.updated_at
  from public.client_roadmaps r
  where p_token is not null
    and length(p_token) > 0
    and r.token = p_token;
$function$;

-- §7.1 rule 7. The grant removed here is the one on PUBLIC — the leading
-- `=X/postgres` entry in proacl with no grantee before the `=`; a revoke naming
-- only anon would be a no-op.
revoke execute on function public.fetch_roadmap_by_token(text) from public, anon;
grant  execute on function public.fetch_roadmap_by_token(text) to authenticated;

-- ANON IS DELIBERATELY *NOT* GRANTED TONIGHT, and this is the carve-out test
-- applied rather than assumed. Rule 7's test is "does anything outside the
-- database call this?", answered PER FUNCTION. Answered here: NO.
--   · `src/` contains exactly ONE occurrence of `client_roadmaps` — the
--     generated type in database.types.ts. No route, no query, no token page.
--   · No `/roadmap/<token>`-shaped route responds on structtek.com,
--     www.structtek.com, audit.structtek.com or os.structtek.com (eight URL
--     shapes, all 404), though both public hosts are up.
-- So there is no live anon caller to preserve, and granting anon would create a
-- net-new anon-executable definer surface for a page nobody can demonstrate
-- exists. The day that page ships, this is ONE line:
--     grant execute on function public.fetch_roadmap_by_token(text) to anon;
-- Re-granting deliberately, knowing what calls it, is the 2026-08-20 discipline.
-- Leaving it open on the strength of "the page needs it" is what 8/20 forbids.

-- ---------------------------------------------------------------------------
-- 2 · CLOSE THE ANONYMOUS READ
-- ---------------------------------------------------------------------------
-- `member read own roadmaps` (SELECT TO authenticated, org-scoped via
-- my_org_ids()) is untouched and is what staff read through. Permissive policies
-- OR together, so removing this one removes an alternative that granted
-- everything; it takes nothing away from the org-scoped path.
drop policy "read roadmap by token" on public.client_roadmaps;

-- ---------------------------------------------------------------------------
-- 3 · STEP 4 — THE TABLE PRIVILEGES  (§7.1 rule 8)
-- ---------------------------------------------------------------------------
-- anon held `arwdDxtm` — the FULL set, INSERT included, not only the
-- SELECT/UPDATE/DELETE first reported. RLS was the only thing standing between
-- the anon key and this table, and on two commands it was standing aside.
--
-- Nothing anon does needs any privilege here:
--   · READ    — no anon grant on the replacement RPC (above).
--   · UPDATE  — policy dropped in Step 1.
--   · DELETE  — never had a policy; the grant was pure surplus.
--   · INSERT  — the scan intake does NOT use it. `trg_auto_roadmap` on
--     `audit_leads` fires `auto_create_roadmap()`, which is SECURITY DEFINER and
--     therefore inserts as postgres, bypassing both RLS and anon's privileges.
--     Verified: prosecdef = true, trigger enabled.
revoke all on table public.client_roadmaps from anon;

-- The `insert roadmap` policy (INSERT TO anon WITH CHECK true) is LEFT IN PLACE
-- and is now INERT — a policy cannot admit a command the grant above no longer
-- permits. The privilege was the control; the policy is now decoration. It is
-- left standing tonight because the controller reserved that decision, and it is
-- proposed for removal next week on readability grounds alone: a policy that
-- reads "anon may insert" when anon may not is the same species of lie as the
-- name that started this incident.