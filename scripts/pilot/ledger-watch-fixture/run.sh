#!/usr/bin/env bash
# MUTATION TEST for public.migration_watch_tick()'s ONE comparison.
# Track S, 2026-10-11. Everything runs in a transaction that is ROLLED BACK.
#
# WHAT THIS COVERS AND WHAT IT DOES NOT, stated because a fixture whose limits
# are unstated gets trusted past them:
#   · COVERS   the comparison — that a genuinely new ledger row selects the
#              alerting branch, and that flipping `>` to `<` makes it stop.
#   · DOES NOT COVER delivery. The POST is not exercised here. Delivery is
#              proved only by a real row plus a reachable endpoint, and on
#              2026-10-11 the stored secret was not a URL, so the combined
#              scheduling+delivery test is INCOMPLETE and is reported as such.
#   · DOES NOT COVER scheduling. That was measured separately from
#              cron.job_run_details: ticks at :00 of every minute, 14-87 ms.
set -uo pipefail
cd "$(dirname "$0")/../../.."
set -a; . ./.env.local >/dev/null 2>&1; set +a

psql "$SUPABASE_DB_URL" -P pager=off -v ON_ERROR_STOP=1 <<'SQL'
begin;
-- Make a new row exist for the duration, so the fixture does not depend on the
-- ledger happening to be ahead of the watermark when it is run.
update public.migration_watch_state set watermark = '0' where id;

\echo '── PHASE 1 · the REAL comparison must fire'
do $$
declare v_max text; v_wm text; v_alerting boolean; v_rows bigint;
begin
  select max(version), count(*) into v_max, v_rows from supabase_migrations.schema_migrations;
  select watermark into v_wm from public.migration_watch_state where id;
  v_alerting := v_max is not null and v_max > v_wm;
  raise notice 'PHASE 1: ledger_max=% watermark=% -> alerting=%  (% ledger rows examined)', v_max, v_wm, v_alerting, v_rows;
  if not v_alerting then raise exception 'PHASE 1 FAILED: the real comparison did not fire'; end if;
  raise notice 'PHASE 1 PASS';
end $$;

\echo '── PHASE 2 · THE MUTANT, applied to the LAST definition (rule 22)'
create or replace function public.migration_watch_tick()
returns text language plpgsql security definer set search_path to 'public','extensions' as $f$
declare v_max text; v_wm text; v_alerting boolean;
begin
  select watermark into v_wm from public.migration_watch_state where id;
  select max(version) into v_max from supabase_migrations.schema_migrations;
  -- MUTATION: comparison flipped from > to <
  v_alerting := v_max is not null and v_max < v_wm;
  return case when v_alerting then 'alerting' else 'quiet' end;
end $f$;

select position('MUTATION: comparison flipped' in p.prosrc) > 0 as mutant_installed
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='migration_watch_tick';

do $$
declare v text;
begin
  v := public.migration_watch_tick();
  if v = 'quiet' then
    raise notice 'MUTANT-REACH OK: flipped comparison reports QUIET on a new row — PHASE 1 can fail, so it means something';
  else
    raise notice 'MUTANT-REACH FAILED: the mutant still alerted — PHASE 1 would pass for a function that always fires';
  end if;
end $$;
rollback;
SQL

echo "--- after rollback, in a NEW connection ---"
psql "$SUPABASE_DB_URL" -At -c "select case when prosrc ~ 'MUTATION' then 'MUTANT STILL PRESENT - BAD' when prosrc ~ 'v_max > v_watermark' then 'REAL function restored' else 'unexpected' end from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='migration_watch_tick';"
psql "$SUPABASE_DB_URL" -At -c "select 'watermark restored: '||watermark from public.migration_watch_state;"
