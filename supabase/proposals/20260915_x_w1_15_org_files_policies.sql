-- ============================================================================
-- X-W1.15 · `org-files` POLICIES — WORK ORDER FILES. PROPOSAL FOR TRACK S.
-- NOT APPLIED BY TRACK X. storage.objects is not Track X's to migrate.
-- Supersedes SECTION 2 of 20260903_x_w1_2_storage_org_isolation.sql.
-- ============================================================================
-- This file holds ONLY the policy statements, so the fixture that proves them
-- (scripts/storage/org-files-fixture/) loads THIS file rather than a copy.
-- Measurements, the design argument and the proof plan are in
-- 20260915_x_w1_15_org_files_policies.md.
--
-- THE PROPERTY: a file belonging to one tenant is not readable by another, and a
-- crew member does not reach a file their role cannot reach in the app.
--
-- WHAT ENFORCES THE PATH, MECHANICALLY. The name is `{org}/{category}/{work
-- order}/{file}`. Nobody has to remember that. Every write is refused unless:
--   · segment 1 is one of the caller's orgs (my_org_ids), AND
--   · segment 3 is a work order the caller can SEE, through work_orders' own RLS,
--     whose org_id equals segment 1, AND
--   · the caller holds view_master_work_order in that org.
-- A read or delete requires the same work order to be visible now. So the path
-- is not trusted: it is checked against a row, as the caller, on every access.
-- A crew member cannot see a MASTER work order (restrictive policy "crew cannot
-- reach master work orders"), so a file on a master is unreachable for them with
-- no second copy of that rule here.
--
-- NO CASTS ON THE NAME. The 9/03 text cast segment 1 to uuid and said a regex
-- guard "placed BEFORE the cast" would short-circuit. SQL does not promise AND is
-- evaluated left to right, and other buckets hold names like `catalog/x.jpg`.
-- Every comparison here is text = uuid::text: a malformed name compares false,
-- it cannot raise.
--
-- DELIBERATELY ABSENT:
--   · No UPDATE policy. Storage moves and upserts are UPDATEs; refusing them
--     means a file cannot be moved into another org's prefix or overwritten.
--   · No policy for the other categories (check-in-photos, estimate-pdfs). They
--     stay closed until their entity and role mapping is decided.
--   · No new function, so no new EXECUTE surface (CLAUDE.md rule 7).
-- Everything is `to authenticated`: anon never evaluates an expression that
-- calls a definer helper (the 8/20 outage).

create policy "org-files work order files read"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'org-files'
    and array_length(storage.foldername(name), 1) = 3
    and (storage.foldername(name))[2] in ('office-uploads', 'work-order-docs')
    and (storage.foldername(name))[1] in (select o::text from public.my_org_ids() o)
    and exists (
      select 1 from public.work_orders w
      where w.id::text = (storage.foldername(name))[3]
        and w.org_id::text = (storage.foldername(name))[1]
    )
  );

create policy "org-files work order files insert"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'org-files'
    and array_length(storage.foldername(name), 1) = 3
    and (storage.foldername(name))[2] in ('office-uploads', 'work-order-docs')
    and (storage.foldername(name))[1] in (select o::text from public.my_org_ids() o)
    and exists (
      select 1 from public.work_orders w
      where w.id::text = (storage.foldername(name))[3]
        and w.org_id::text = (storage.foldername(name))[1]
        and public.can_view_master_work_order(w.org_id)
    )
  );

create policy "org-files work order files delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'org-files'
    and array_length(storage.foldername(name), 1) = 3
    and (storage.foldername(name))[2] in ('office-uploads', 'work-order-docs')
    and (storage.foldername(name))[1] in (select o::text from public.my_org_ids() o)
    and exists (
      select 1 from public.work_orders w
      where w.id::text = (storage.foldername(name))[3]
        and w.org_id::text = (storage.foldername(name))[1]
        and public.can_view_master_work_order(w.org_id)
    )
  );
