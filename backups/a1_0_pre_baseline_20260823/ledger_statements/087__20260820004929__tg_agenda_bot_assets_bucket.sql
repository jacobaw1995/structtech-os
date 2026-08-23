-- Public, read-only bucket holding the subset Inter fonts the agenda-card renderer
-- needs. Public read is intentional: these are OFL-licensed font files, and the edge
-- function fetches them anonymously on cold start.
insert into storage.buckets (id, name, public)
values ('bot-assets', 'bot-assets', true)
on conflict (id) do update set public = true;

drop policy if exists "bot_assets_public_read" on storage.objects;
create policy "bot_assets_public_read"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'bot-assets');

-- Temporary write grant so the fonts can be uploaded once, revoked immediately after.
drop policy if exists "bot_assets_seed_write" on storage.objects;
create policy "bot_assets_seed_write"
  on storage.objects for insert
  to anon
  with check (bucket_id = 'bot-assets');
