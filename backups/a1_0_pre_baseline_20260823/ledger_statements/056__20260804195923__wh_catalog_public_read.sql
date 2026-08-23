-- WINDY HILL — PUBLIC CATALOG READ (anon browsing). Adds anon SELECT (active rows)
-- to wh_* catalog; leaves authenticated-read + org-scoped write policies intact.

DROP POLICY IF EXISTS "wh_systems anon read"        ON public.wh_systems;
CREATE POLICY "wh_systems anon read"        ON public.wh_systems
  FOR SELECT TO anon USING (active = true);

DROP POLICY IF EXISTS "wh_stages anon read"         ON public.wh_stages;
CREATE POLICY "wh_stages anon read"         ON public.wh_stages
  FOR SELECT TO anon USING (active = true);

DROP POLICY IF EXISTS "wh_categories anon read"     ON public.wh_categories;
CREATE POLICY "wh_categories anon read"     ON public.wh_categories
  FOR SELECT TO anon USING (active = true);

DROP POLICY IF EXISTS "wh_products anon read"        ON public.wh_products;
CREATE POLICY "wh_products anon read"        ON public.wh_products
  FOR SELECT TO anon USING (active = true);

DROP POLICY IF EXISTS "wh_colors anon read"          ON public.wh_colors;
CREATE POLICY "wh_colors anon read"          ON public.wh_colors
  FOR SELECT TO anon USING (active = true);

DROP POLICY IF EXISTS "wh_length_options anon read"  ON public.wh_length_options;
CREATE POLICY "wh_length_options anon read"  ON public.wh_length_options
  FOR SELECT TO anon USING (active = true);

DROP POLICY IF EXISTS "wh_product_colors anon read"    ON public.wh_product_colors;
CREATE POLICY "wh_product_colors anon read"    ON public.wh_product_colors
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "wh_product_lengths anon read"   ON public.wh_product_lengths;
CREATE POLICY "wh_product_lengths anon read"   ON public.wh_product_lengths
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "wh_category_products anon read" ON public.wh_category_products;
CREATE POLICY "wh_category_products anon read" ON public.wh_category_products
  FOR SELECT TO anon USING (true);
