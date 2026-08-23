-- Retire legacy stock-length dropdown model (see 07_wh-retire-length-tables.sql).
-- Child first (references parent), then parent. Nothing external depends on either.
BEGIN;
DROP TABLE IF EXISTS public.wh_product_lengths;
DROP TABLE IF EXISTS public.wh_length_options;
COMMIT;
