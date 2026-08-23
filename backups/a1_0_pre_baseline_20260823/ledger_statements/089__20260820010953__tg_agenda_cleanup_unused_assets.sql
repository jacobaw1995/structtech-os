-- Cleanup. The bot-assets bucket was created for a font-hosting approach that proved
-- unnecessary (the fonts ship inside the function bundle), so drop its policies. Also
-- drop the http extension enabled only to verify the deployed function from Postgres.
drop policy if exists "bot_assets_seed_write" on storage.objects;
drop policy if exists "bot_assets_public_read" on storage.objects;
drop extension if exists http;
