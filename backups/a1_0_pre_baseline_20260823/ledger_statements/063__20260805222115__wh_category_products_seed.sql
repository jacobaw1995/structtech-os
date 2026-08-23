BEGIN;

INSERT INTO public.wh_category_products (category_id, product_id)
SELECT c.id, p.id
FROM public.wh_products p
CROSS JOIN LATERAL unnest(p.compatible_systems) AS cs(slug)
JOIN public.wh_systems s    ON s.slug = cs.slug
JOIN public.wh_categories c ON c.system_id = s.id AND c.catalog_section = p.catalog_section
WHERE p.active
ON CONFLICT (category_id, product_id) DO NOTHING;

INSERT INTO public.wh_category_products (category_id, product_id)
SELECT c.id, p.id
FROM public.wh_products p
JOIN public.wh_categories c ON c.catalog_section = 'fastener' AND c.slug IN ('ag-fasteners','ss-fasteners')
WHERE p.active AND p.catalog_section = 'fastener'
  AND COALESCE(cardinality(p.compatible_systems), 0) = 0
ON CONFLICT (category_id, product_id) DO NOTHING;

INSERT INTO public.wh_category_products (category_id, product_id)
SELECT c.id, p.id
FROM public.wh_products p
JOIN public.wh_categories c ON c.slug = 'ag-underlayment'
WHERE p.active AND p.catalog_section = 'underlayment'
ON CONFLICT (category_id, product_id) DO NOTHING;

INSERT INTO public.wh_category_products (category_id, product_id)
SELECT c.id, p.id
FROM public.wh_products p
JOIN public.wh_categories c ON c.slug = 'Fascia'
WHERE p.active AND p.name ILIKE 'Fascia Trim%'
ON CONFLICT (category_id, product_id) DO NOTHING;

INSERT INTO public.wh_category_products (category_id, product_id)
SELECT c.id, p.id
FROM public.wh_products p
JOIN public.wh_categories c ON c.slug = 'Soffit'
WHERE p.active AND p.name ILIKE '%Soffit%'
ON CONFLICT (category_id, product_id) DO NOTHING;

INSERT INTO public.wh_category_products (category_id, product_id)
SELECT c.id, p.id
FROM public.wh_products p
JOIN public.wh_categories c ON c.slug = 'pipe-boots-ag'
WHERE p.active AND p.catalog_section = 'misc' AND p.name ~* 'boot'
ON CONFLICT (category_id, product_id) DO NOTHING;

COMMIT;
