-- ============================================================================
-- X-W1.2 · STORAGE POLICY PROPOSAL — FOR TRACK S. NOT APPLIED BY TRACK X.
-- ============================================================================
-- This file lives in supabase/proposals/, NOT supabase/migrations/, precisely
-- so that nothing can apply it by accident. Track X does not migrate, and
-- storage.objects is not Track X's to migrate in any case.
--
-- Measured on the live project 2026-09-03 (America/New_York), before writing:
--   · storage.objects  — RLS enabled, anon holds arwdDxtm (platform grant,
--                        not revocable by us). RLS is therefore the ONLY
--                        barrier on that table for anon.
--   · storage.buckets  — same shape, same grant.
--   · 6 policies exist on storage.objects. 5 are Material Matrix's
--     (product-photos). The 6th is ours and is SECTION 1 below.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- SECTION 1 — THE FINDING. DROP THIS POLICY.  ** DO THIS FIRST. **
-- ----------------------------------------------------------------------------
-- Policy `anon deal files all` on storage.objects:
--     roles = {anon}   cmd = ALL
--     using       (bucket_id = 'deal-files')
--     with check  (bucket_id = 'deal-files')
--
-- This grants unauthenticated callers SELECT, INSERT, UPDATE and DELETE on
-- every object in the `deal-files` bucket. It is not inferred. On 2026-09-03,
-- holding nothing but the publishable anon key, Track X:
--     uploaded  _xw12_anon_probe.txt  -> HTTP 200
--     read it back                    -> HTTP 200, body returned verbatim
--     listed the bucket               -> the object, with its metadata
--     deleted it                      -> HTTP 200 "Successfully deleted"
-- The same four calls against spec-files and bot-assets were refused with
-- "new row violates row-level security policy". The probe object was removed;
-- deal-files is back to 0 objects.
--
-- The bucket holds nothing today and no code in src/ references it (grep for
-- `deal-files` and `.storage` both return zero hits), which is the ONLY
-- reason this is not a live disclosure. That is CLAUDE.md rule 13 exactly:
-- closed by accident is not closed. The thing that would have to change for
-- this to open is "somebody puts a file in the bucket" — an absence standing
-- in for a control, with no owner and no alarm. A4 field execution starts in
-- nineteen days and its first crew photo is the change.

drop policy if exists "anon deal files all" on storage.objects;

-- Optional, and Jacob's call, not Track X's: deal-files is an orphan. Created
-- 2026-07-03, 0 objects, referenced by no code. Once the policy above is gone
-- it is inert either way. Dropping the bucket row is a separate decision.
--   delete from storage.buckets where id = 'deal-files';


-- ----------------------------------------------------------------------------
-- SECTION 2 — THE ISOLATION POLICY FOR `org-files`
-- ----------------------------------------------------------------------------
-- The bucket already exists (Track X created it 2026-09-03; see
-- SECTION 3 for the literal statement that ran). It is private and carries
-- ZERO policies, which was asserted rather than assumed: with a real BMR
-- owner's claims, as role `authenticated`, an INSERT into it returned
--   42501  "new row violates row-level security policy for table objects"
-- and as `anon` over HTTP the same upload returned 403 AccessDenied. The
-- bucket is born closed; these four policies are what open it, to members
-- of the owning org and nobody else.
--
-- WHY THE PREDICATE READS A PATH SEGMENT. A policy on storage.objects can
-- see the object's name and nothing else — there is no org_id column to
-- scope. So the convention puts the org id in path segment 1 and the policy
-- compares `(storage.foldername(name))[1]` against my_org_ids().
-- src/lib/storage/paths.ts is the other half of this contract; changing the
-- path shape without changing this policy silently unscopes every file.
--
-- WHY `TO authenticated` AND NOT `TO public`. A policy left TO public must be
-- EVALUATED for anon, and this expression calls my_org_ids(), which anon
-- cannot execute (acl: postgres, authenticated, service_role — no PUBLIC
-- entry, verified 2026-09-03). That is the 8/20 Material Matrix outage
-- exactly: a definer helper inside a policy anon has to evaluate. Scoped TO
-- authenticated, anon never reaches the expression and is refused by the
-- absence of any policy that applies to it.
--
-- WHY FOUR POLICIES AND NOT ONE `FOR ALL`. A4.7 wants per-role permissions on
-- office-side uploads. Splitting read from write now means that gate is added
-- to two policies later instead of being carved out of one.

create policy "org-files org read"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'org-files'
    and ((storage.foldername(name))[1])::uuid in (select my_org_ids())
  );

create policy "org-files org insert"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'org-files'
    and ((storage.foldername(name))[1])::uuid in (select my_org_ids())
  );

create policy "org-files org update"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'org-files'
    and ((storage.foldername(name))[1])::uuid in (select my_org_ids())
  )
  with check (
    bucket_id = 'org-files'
    and ((storage.foldername(name))[1])::uuid in (select my_org_ids())
  );

create policy "org-files org delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'org-files'
    and ((storage.foldername(name))[1])::uuid in (select my_org_ids())
  );

-- CAUTION on the ::uuid cast. A name whose first segment is not a uuid raises
-- 22P02 rather than returning false, and inside a policy that is an error the
-- caller sees, not a denial. Every write path in src/lib/storage/paths.ts
-- validates the segment as a uuid before building the path, so a
-- non-conforming name cannot be created THROUGH THE APP — but service_role
-- bypasses RLS and can create one, and then this policy errors for readers.
-- If Track S prefers belt-and-braces, guard the cast:
--     and (storage.foldername(name))[1] ~
--         '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
-- placed BEFORE the cast so it short-circuits. Track X did not fold this in
-- because it changes the predicate Track S is reviewing; the choice is theirs.


-- ----------------------------------------------------------------------------
-- SECTION 3 — WHAT TRACK X ALREADY RAN (reproduced verbatim, not re-run)
-- ----------------------------------------------------------------------------
-- Recorded per CLAUDE.md rule 10: the file reproduces what ran, keyed on the
-- primary key (storage.buckets.id) with the id as a literal. Audit fields
-- (created_at/updated_at) are deliberately NOT pinned — a replay cannot
-- honestly assert production's timestamps.
--
--   insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
--   values ('org-files', 'org-files', false, 26214400, null)
--   on conflict (id) do nothing;
--
-- file_size_limit 26214400 = 25 MiB — a phone photo is 2-5 MB and a signed
-- estimate PDF under 1 MB, so this is roughly 5x headroom without letting a
-- mis-picked video through. allowed_mime_types is null ON PURPOSE: A4.7
-- office-side uploads are documents of unknown type, and a MIME allowlist
-- that has to be edited every time somebody uploads a .heic is §2.8's
-- "never block the user" wearing a different hat.
