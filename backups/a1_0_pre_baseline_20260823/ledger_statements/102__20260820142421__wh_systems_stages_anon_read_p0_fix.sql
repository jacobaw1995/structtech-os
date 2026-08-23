-- P0 FIX — restore anonymous catalog reads.
--
-- wh_systems and wh_stages each carried ONE write policy declared
-- `FOR ALL TO public` whose expression calls my_org_ids(). Because ALL includes
-- SELECT, an anonymous read had to evaluate it — and another build's migration
-- 20260820133834 revoked anon EXECUTE on every security-definer function in
-- public, my_org_ids included. Result: 401 / 42501 on the storefront's
-- wh_systems read, which aborts the whole catalog load.
--
-- This narrows both policies to the command-specific shape every other WH
-- catalog table already uses, scoped TO authenticated so an anonymous write is
-- refused at the role rather than inside my_org_ids(). Confined to WH-owned
-- tables; nothing belonging to the other build is touched.
--
-- Reads are already covered by separate policies on both tables and are NOT
-- modified here:
--   "wh_systems anon read"          SELECT to anon    (active = true)
--   "Authenticated read wh_systems" SELECT to public  (auth.role()='authenticated')
--   "wh_stages anon read"           SELECT to anon    (active = true)
--   "Authenticated read wh_stages"  SELECT to public  (auth.role()='authenticated')
--
-- The explicit begin/commit from the draft is dropped: the migration runner
-- supplies its own transaction.

-- ── wh_systems ─────────────────────────────────────────────────────────────
drop policy if exists "WH org write wh_systems" on public.wh_systems;

create policy "wh_systems org insert" on public.wh_systems
  for insert to authenticated
  with check (org_id in (select public.my_org_ids()));

create policy "wh_systems org update" on public.wh_systems
  for update to authenticated
  using      (org_id in (select public.my_org_ids()))
  with check (org_id in (select public.my_org_ids()));

create policy "wh_systems org delete" on public.wh_systems
  for delete to authenticated
  using (org_id in (select public.my_org_ids()));

-- ── wh_stages ──────────────────────────────────────────────────────────────
drop policy if exists "WH org write wh_stages" on public.wh_stages;

create policy "wh_stages org insert" on public.wh_stages
  for insert to authenticated
  with check (org_id in (select public.my_org_ids()));

create policy "wh_stages org update" on public.wh_stages
  for update to authenticated
  using      (org_id in (select public.my_org_ids()))
  with check (org_id in (select public.my_org_ids()));

create policy "wh_stages org delete" on public.wh_stages
  for delete to authenticated
  using (org_id in (select public.my_org_ids()));
