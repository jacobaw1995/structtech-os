-- Re-host the two SYSTEM hero images off the sunset project.
-- These were not in the "four category photos" count — they live on wh_systems,
-- not wh_categories, and they are the two largest images on the storefront's
-- system chooser. Bytes were downloaded from the sunset project and re-uploaded
-- unchanged, so the storefront looks identical.
update public.wh_systems s
   set hero_image_url = 'https://ejlhrykcdfcyeooooodx.supabase.co/storage/v1/object/public/product-photos/systems/'
                        || s.slug || '.jpg'
 where exists (
   select 1 from storage.objects o
    where o.bucket_id = 'product-photos'
      and o.name = 'systems/' || s.slug || '.jpg'
 );
