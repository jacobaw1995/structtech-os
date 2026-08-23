-- CP3 photo pipeline step 1, corrective follow-up.
--
-- The previous migration narrowed ALL writes to product-photos to admin|assistant.
-- That would have regressed the shop's checkout spec-file uploader, which writes
-- customer roof-scope files into this same bucket under the `specs/` prefix
-- (windy-hill-configurator.js uploadSpecFiles(), ~:4197). Before that migration any
-- authenticated user could insert there; this restores exactly that capability,
-- scoped to the `specs/` prefix, so catalog photo paths stay staff-only.
--
-- Deliberately unchanged, and flagged for Jacob rather than "fixed" here:
--   * anon still cannot upload spec files. It could not before either — which is
--     consistent with product-photos holding 0 objects, i.e. the guest-checkout
--     spec upload has never succeeded in production.
--   * customer spec files live in a PUBLIC bucket and are handed out via
--     getPublicUrl(). A private `spec-files` bucket already exists and is unused.
--     Re-routing them is a behavior change (and roadmap item 6, "file upload
--     improvement"), so it is NOT done here.

create policy "product-photos spec upload" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'product-photos' and name like 'specs/%');
