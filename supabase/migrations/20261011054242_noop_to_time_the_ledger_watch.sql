-- A DELIBERATELY TRIVIAL NO-OP, APPLIED TO TIME THE LEDGER WATCH.
-- 2026-10-11, Track S. Track X's specification: the only test that covers
-- scheduling and delivery together is a real row appearing, so this is a real
-- row. Everything else is a bound.
--
-- IT CHANGES NOTHING. One COMMENT on a table that already exists and already
-- has that comment's subject. No DDL that alters a type, a constraint, a grant
-- or a row. Chosen so that if this file is ever replayed against a restore it
-- cannot do harm, and so that a reader who finds it in the ledger is not left
-- wondering what it did.
--
-- THE ROLLBACK IS "NOTHING", AND THAT IS WHY THERE IS NO ROLLBACK FILE: there is
-- no state to return. Stated rather than omitted, because a missing rollback
-- normally means somebody skipped a step.

comment on table public.migration_watch_state is
  'One row. The highest supabase_migrations.schema_migrations version already reported, plus the consecutive delivery-failure count. Advanced only on HTTP 2xx. (Comment re-stated by 20261011054242, a no-op applied to time the ledger watch.)';
