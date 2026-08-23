-- Retire the last FOR ALL TO public policy carrying my_org_ids(), and scope the
-- read policy to authenticated so no anon request can reach my_org_ids() here.
--
-- PRE-STATE (recorded verbatim so this is reversible):
--   "wh_team_members admin write"  FOR ALL    TO public
--       USING/WITH CHECK: (org_id IN (SELECT my_org_ids())) AND (my_wh_role() = 'admin')
--   "wh_team_members org read"     FOR SELECT TO public
--       USING:            (org_id IN (SELECT my_org_ids()))
--
-- CALLER AUDIT (done first, per instruction):
--   my_wh_role() is the ONLY database object that reads wh_team_members, and it
--   is SECURITY DEFINER, so it bypasses RLS and never evaluates these policies.
--   The only application caller is loadRole() in windy-hill-admin.html, which
--   calls the my_wh_role() RPC behind a getSession() guard. Nothing in the shop,
--   the account page, or the three Edge Functions touches the table. The admin's
--   "Team" view reads wh_drivers, a different table.
--   => No application code path reads this table under RLS. These policies were
--      unreachable from our code both before and after the other build's sweep.
--
-- WHY NARROW ANYWAY: the shape is the one that took the shop down on 20 Aug.
--   A FOR ALL policy applies to SELECT as well as writes, so its my_org_ids()
--   call is evaluated on every read. anon lost EXECUTE on my_org_ids() in the
--   other build's sweep (20260820133834), which turns that evaluation into a
--   hard 42501. Verified live before this migration: an anon SELECT on
--   wh_team_members returns 401 / 42501 "permission denied for function
--   my_org_ids", not zero rows.
--
--   Both policies are scoped here, not just the FOR ALL one. Narrowing only the
--   write policy would leave "org read" TO public still calling my_org_ids() on
--   anon SELECT, so the 42501 would survive untouched. anon has no business
--   reading this table and has no anon-read policy, so authenticated is correct.
--
-- Writes preserved exactly: the original ALL policy had USING and an identical
-- WITH CHECK, so the split applies the same expression to both.
-- No table data is read or written by this migration.

drop policy if exists "wh_team_members admin write" on public.wh_team_members;

create policy "wh_team_members admin insert" on public.wh_team_members
  for insert to authenticated
  with check (org_id in (select public.my_org_ids()) and public.my_wh_role() = 'admin');

create policy "wh_team_members admin update" on public.wh_team_members
  for update to authenticated
  using      (org_id in (select public.my_org_ids()) and public.my_wh_role() = 'admin')
  with check (org_id in (select public.my_org_ids()) and public.my_wh_role() = 'admin');

create policy "wh_team_members admin delete" on public.wh_team_members
  for delete to authenticated
  using (org_id in (select public.my_org_ids()) and public.my_wh_role() = 'admin');

drop policy if exists "wh_team_members org read" on public.wh_team_members;

create policy "wh_team_members org read" on public.wh_team_members
  for select to authenticated
  using (org_id in (select public.my_org_ids()));
