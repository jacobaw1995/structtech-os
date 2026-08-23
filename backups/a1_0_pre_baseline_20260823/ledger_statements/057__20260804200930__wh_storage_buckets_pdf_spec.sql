-- WINDY HILL — private storage buckets in target.
-- pdf-files: process-order writes work-order PDFs via service role; reads are 72h signed
--   URLs (pre-signed, need no policy). No anon/authenticated policy = service-role only.
-- spec-files: created for parity; the shop currently uploads spec files to product-photos.
--   Wiring uploads here (with an upload policy) is Priority 6 — left policy-less (private) until then.
-- product-photos intentionally NOT created here: images serve from legacy for launch;
--   copy + image_url rewrite is a pre-sunset dependency (on Jacob's tracker).
insert into storage.buckets (id, name, public)
values ('pdf-files', 'pdf-files', false),
       ('spec-files', 'spec-files', false)
on conflict (id) do nothing;
