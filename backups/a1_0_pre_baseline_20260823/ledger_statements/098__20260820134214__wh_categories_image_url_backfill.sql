-- CP3 photo pipeline step 3 — point wh_categories.image_url at WH's OWN Storage.
--
-- Guarded by an EXISTS against storage.objects, so a category only gets a URL if
-- the object is really there. The three admin-created categories (Soffit, Fascia,
-- pipe-boots-ag) have no photo anywhere and are deliberately left NULL — null is
-- what makes the storefront's convention fallback fire.
--
-- This also completes the sunset re-host: the four categories that pointed at
-- gnjpxtxufklhakobgzqv now point at ejlhrykcdfcyeooooodx. The bytes uploaded for
-- those four were downloaded FROM the sunset project, so the picture customers
-- see does not change.

update public.wh_categories c
   set image_url = 'https://ejlhrykcdfcyeooooodx.supabase.co/storage/v1/object/public/product-photos/catalog/'
                   || c.slug || '.jpg'
 where exists (
   select 1 from storage.objects o
    where o.bucket_id = 'product-photos'
      and o.name = 'catalog/' || c.slug || '.jpg'
 );
