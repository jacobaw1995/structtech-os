-- ORG-FILES: WORK ORDER FILES. Track S · 2026-09-16. Track X's X-W1.15 proposal, applied AS AMENDED by two
-- controller rulings. Rollback: supabase/rollbacks/20260916_org_files_work_order_policies_rollback.sql
-- Proposal and fixture: supabase/proposals/20260915_x_w1_15_org_files_policies.{md,sql},
-- scripts/storage/org-files-fixture/ — 24/24 on the proposal; mutant-entity 8 fail, mutant-tenant 13 fail
-- (recorded by Track X; read, not re-run). Unblocks A4.7 / Phase A field #7 and #8.
--
-- BEFORE (measured 2026-09-16): org-files private, 0 objects, 0 policies; storage.objects carries 6 policies,
-- none naming org-files; 0 client_portal_viewer and 0 field members in production.
--
-- AMENDMENT 1 — client_portal_viewer MUST NOT REACH TRADE WORK ORDER FILES (controller ruling). PROVED on the
-- proposal text before applying (rolled back): a synthetic client_portal_viewer in BMR reads 1 trade work
-- order through work_orders' own RLS, and therefore read the trade work order's file (1) — the proposal's
-- "files follow the work order" carries that reach to files. A homeowner does not see internal roof data or
-- crew photos. CLOSED HERE, NOT ON work_orders: that reach is not ruled.
-- field and client_portal_viewer hold IDENTICAL default capabilities (default_permissions_for_role), so no
-- capability can tell them apart. can_reach_work_order_files() is therefore an ALLOW-LIST OF ROLES, closed by
-- default: a role added later reaches no file until it is named here. It is the one place a future
-- `view_work_order_files` capability replaces. SECURITY DEFINER so the caller's own membership is read without
-- depending on org_members' RLS (a hidden row must read as "no", never "not a viewer" — §7.1 RULE 11).
--
-- AMENDMENT 2 — DELETE (and, as proposed, INSERT) FOLLOW view_master_work_order. ** THIS IS A PROXY. **
-- A view capability doing delete duty coincides with the right people today (owner, admin, agency_admin,
-- office, member — not field, not client_portal_viewer) and drifts the day anyone is granted the master view
-- for another reason. REPLACEMENT DATE: 2026-10-07 (the pilot) — replaced by a file-write capability, with
-- default_permissions_for_role and a backfill of org_members.permissions, in one migration.
--
-- WHAT WOULD REOPEN IT (rule 13): a permissive policy widening work_orders reads; a change to
-- can_view_master_work_order / has_capability; a role added to can_reach_work_order_files(). Each is a change
-- to the named object, reviewable where it is made.
-- The rest is the proposal unchanged: no casts on the name, no UPDATE policy (moves and overwrites refused),
-- two categories only, everything TO authenticated.

create function public.can_reach_work_order_files(p_org_id uuid)
returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select exists (
    select 1 from public.org_members m
    where m.org_id = p_org_id
      and m.user_id = auth.uid()
      and m.role in ('owner', 'admin', 'agency_admin', 'office', 'member', 'field')
  );
$function$;
revoke execute on function public.can_reach_work_order_files(uuid) from public, anon;
grant execute on function public.can_reach_work_order_files(uuid) to authenticated;

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
        and public.can_reach_work_order_files(w.org_id)
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
        and public.can_reach_work_order_files(w.org_id)
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
        and public.can_reach_work_order_files(w.org_id)
        and public.can_view_master_work_order(w.org_id)
    )
  );
