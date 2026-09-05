-- ROLLBACK for 20260904_drop_anon_deal_files_all.
-- Captured from pg_policy on the LIVE database 2026-09-04 BEFORE the drop,
-- via format() over pg_get_expr — not retyped (§7.1 Rule 1, and rule 2's
-- "copy the signature, never retype it" applied to a policy).
--
-- RESTORING THIS RE-OPENS ANONYMOUS SELECT/INSERT/UPDATE/DELETE ON THE
-- ENTIRE deal-files BUCKET. It exists to make the change reversible, not
-- because reversing it would ever be correct.
create policy "anon deal files all" on storage.objects as permissive for all to anon
  using ((bucket_id = 'deal-files'::text)) with check ((bucket_id = 'deal-files'::text));
