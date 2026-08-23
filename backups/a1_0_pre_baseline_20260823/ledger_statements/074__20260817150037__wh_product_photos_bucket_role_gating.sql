-- CP3 photo pipeline step 1 — role-gate writes to the product-photos bucket.
--
-- Before: any authenticated user could INSERT/UPDATE/DELETE product photos
-- (migration 08 granted the whole `authenticated` role). A signed-in retail
-- customer could delete catalog imagery. This narrows writes to admin|assistant
-- via my_wh_role(), matching the catalog RLS pattern from migration 12.
--
-- DELETE is deliberately granted to admin|assistant (not admin-only, as it is for
-- catalog rows): replacing a photo requires removing the old object, and the admin
-- photo UI must be usable by assistants. A photo that cannot be deleted cannot be
-- replaced.
--
-- Public read is retained unchanged — the bucket is public and the storefront
-- reads image_url URLs anonymously.

drop policy if exists "product-photos auth insert" on storage.objects;
drop policy if exists "product-photos auth update" on storage.objects;
drop policy if exists "product-photos auth delete" on storage.objects;

create policy "product-photos role insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'product-photos' and public.my_wh_role() in ('admin','assistant'));

create policy "product-photos role update" on storage.objects
  for update to authenticated
  using      (bucket_id = 'product-photos' and public.my_wh_role() in ('admin','assistant'))
  with check (bucket_id = 'product-photos' and public.my_wh_role() in ('admin','assistant'));

create policy "product-photos role delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'product-photos' and public.my_wh_role() in ('admin','assistant'));
