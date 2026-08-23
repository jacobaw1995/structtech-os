-- P0 follow-on — retire the last two FOR ALL TO public policies on live-catalog
-- tables, so no anonymous SELECT can ever be made to evaluate my_org_ids().
--
-- wh_category_products and wh_product_colors read fine today only because their
-- predicate is a NESTED subquery: Postgres's permissive-policy OR is satisfied
-- by the cheap `anon read` policy first, so my_org_ids() is never invoked.
-- wh_systems/wh_stages had the predicate at the top level and always evaluated
-- it, which is why they broke and these did not. That is short-circuit luck,
-- not design, and these are the two tables that serve the live catalog.
--
-- Reads stay covered by the existing SELECT policies, which are NOT touched:
--   "wh_category_products anon read"        SELECT to anon   (true)
--   "Authenticated read wh_category_products" SELECT to public (auth.role()='authenticated')
--   "wh_product_colors anon read"           SELECT to anon   (true)
--   "Authenticated read wh_product_colors"  SELECT to public (auth.role()='authenticated')
--
-- The original ALL policies carried a USING expression with a NULL WITH CHECK,
-- so Postgres reused USING as the check for INSERT/UPDATE. The split below
-- applies that same expression to both, preserving write behaviour exactly.
--
-- wh_save_catalog_family() is SECURITY DEFINER owned by postgres (the table
-- owner), so it bypasses RLS and is unaffected. The legacy admin's direct
-- writes (syncProductColors, toggleProductInCategory) run as `authenticated`
-- and are covered by the new policies.

-- ── wh_category_products ───────────────────────────────────────────────────
drop policy if exists "WH org write wh_category_products" on public.wh_category_products;

create policy "wh_category_products org insert" on public.wh_category_products
  for insert to authenticated
  with check (category_id in (
    select c.id from public.wh_categories c
     where c.org_id in (select public.my_org_ids())));

create policy "wh_category_products org update" on public.wh_category_products
  for update to authenticated
  using (category_id in (
    select c.id from public.wh_categories c
     where c.org_id in (select public.my_org_ids())))
  with check (category_id in (
    select c.id from public.wh_categories c
     where c.org_id in (select public.my_org_ids())));

create policy "wh_category_products org delete" on public.wh_category_products
  for delete to authenticated
  using (category_id in (
    select c.id from public.wh_categories c
     where c.org_id in (select public.my_org_ids())));

-- ── wh_product_colors ──────────────────────────────────────────────────────
drop policy if exists "WH org write wh_product_colors" on public.wh_product_colors;

create policy "wh_product_colors org insert" on public.wh_product_colors
  for insert to authenticated
  with check (product_id in (
    select p.id from public.wh_products p
     where p.org_id in (select public.my_org_ids())));

create policy "wh_product_colors org update" on public.wh_product_colors
  for update to authenticated
  using (product_id in (
    select p.id from public.wh_products p
     where p.org_id in (select public.my_org_ids())))
  with check (product_id in (
    select p.id from public.wh_products p
     where p.org_id in (select public.my_org_ids())));

create policy "wh_product_colors org delete" on public.wh_product_colors
  for delete to authenticated
  using (product_id in (
    select p.id from public.wh_products p
     where p.org_id in (select public.my_org_ids())));
