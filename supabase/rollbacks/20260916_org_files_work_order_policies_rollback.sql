-- ROLLBACK for the org-files work order policies (2026-09-16). Returns org-files to NO POLICY — closed to every
-- API caller, which is the state before. Remove any objects uploaded under these policies first if they must
-- not be orphaned (they stay in the bucket, unreadable).
drop policy if exists "org-files work order files read" on storage.objects;
drop policy if exists "org-files work order files insert" on storage.objects;
drop policy if exists "org-files work order files delete" on storage.objects;
drop function if exists public.can_reach_work_order_files(uuid);
