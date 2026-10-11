-- ROLLBACK for 20261011053800_migration_watch_cron.sql
-- Written BEFORE the migration. Track S, 2026-10-11.
--
-- Unschedules the job, drops the function, drops the watermark table.
-- DOES NOT drop the pg_cron extension: it was installed as a separate, earlier
-- act in the same session and other things may come to depend on it. Dropping an
-- extension to undo one job is the shape rule 32 warns about.
-- DOES NOT touch vault.secrets. The webhook secret is Jacob's, created by him at
-- 2026-10-11 00:36:04 EDT, and no migration of ours should remove a credential
-- a human placed.
--
-- ⚠ RUNNING THIS BLINDS THE LEDGER WATCH. After it, a migration from either
-- party applies with nothing watching — which is the exact state that cost 34
-- hours on 2026-10-07. The Node monitor at scripts/pilot/migration-watch.mjs
-- still exists and still works, but it only runs when somebody runs it, which is
-- a note rather than a step (CLAUDE.md 38).

begin;

-- Unschedule BY NAME. cron.unschedule(text) raises if the job does not exist, so
-- the existence check is explicit rather than suppressed — an IF EXISTS here
-- would make "already gone" and "never mine" indistinguishable (rule 2's shape,
-- and the reason the org-files rollback was rewritten on 2026-10-08).
do $$
begin
  if exists (select 1 from cron.job where jobname = 'migration-watch') then
    perform cron.unschedule('migration-watch');
    raise notice 'UNSCHEDULED: migration-watch';
  else
    raise notice 'ALREADY GONE: no cron job named migration-watch (nothing unscheduled)';
  end if;
end $$;

drop function if exists public.migration_watch_tick();
drop table if exists public.migration_watch_state;

-- VERIFY, never trust the success response (rule 3).
select (select count(*) from cron.job where jobname='migration-watch') as jobs_remaining,
       (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
          where n.nspname='public' and p.proname='migration_watch_tick') as function_remaining,
       (select count(*) from information_schema.tables
          where table_schema='public' and table_name='migration_watch_state') as table_remaining,
       (select count(*) from pg_extension where extname='pg_cron') as pg_cron_still_installed,
       (select count(*) from vault.secrets where name='migration_watch_webhook') as secret_untouched;

commit;
