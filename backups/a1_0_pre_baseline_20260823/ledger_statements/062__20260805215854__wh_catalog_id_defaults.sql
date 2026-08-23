BEGIN;
ALTER TABLE public.wh_products   ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE public.wh_colors     ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE public.wh_categories ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE public.wh_stages     ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE public.wh_systems    ALTER COLUMN id SET DEFAULT gen_random_uuid();
COMMIT;
