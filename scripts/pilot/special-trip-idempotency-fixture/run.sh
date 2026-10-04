#!/usr/bin/env bash
# MUTATION TEST for 20261004225242_a_resent_special_trip_is_the_same_trip.
# A mirror of scripts/pilot/check-in-idempotency-fixture/run.sh, because the
# migrations are mirrors.
#
# One transaction, ROLLED BACK. Nothing is written. Every call under test is made
# as the REAL field account that signed in at 00:31 and wrote today's check-in,
# so a refusal would be a real refusal.
#
# Rule 22: the mutant attacks the LAST text that defines the function, and the
# mutation is ASSERTED present in prosrc before it is relied on.
# Rule 24/26: every phase prints the SIZE of what it examined beside its result.
set -euo pipefail
cd "$(dirname "$0")/../../.."
set -a; . ./.env.local >/dev/null 2>&1; set +a
BODY="$(cat scripts/pilot/special-trip-idempotency-fixture/migration_body.sql)"
FIELD_USER='e1cd8efd-574f-4d6e-9007-f3c31edad0e9'
WO='d76d8664-3337-4e2c-a898-b3b5bae32415'

psql "$SUPABASE_DB_URL" -P pager=off -v ON_ERROR_STOP=1 <<SQL
begin;

\echo '### BEFORE'
select count(*) as special_trips_before, count(*) filter (where true) as denominator from public.special_trips;

-- ============ APPLY THE MIGRATION BODY ============
$BODY

\echo '### UNIQUE INDEXES NOW (expect pkey + the partial one)'
select i.relname, pg_get_indexdef(idx.indexrelid) as def
from pg_index idx join pg_class i on i.oid=idx.indexrelid join pg_class t on t.oid=idx.indrelid
where t.relname='special_trips' and idx.indisunique order by i.relname;

select set_config('role','authenticated',true);
select set_config('request.jwt.claims','{"sub":"$FIELD_USER","role":"authenticated"}',true);

\echo '### PHASE 1 — FOUR RESENDS, ONE TOKEN, NO DATE (the sharp edge: the date defaults to New York today, so nothing else distinguishes them). Expect 1 row.'
do \$\$
declare v_ids uuid[] := '{}'; i int;
begin
  for i in 1..4 loop
    v_ids := v_ids || public.record_special_trip('$WO'::uuid, 'material_wrong', null, 'wrong colour ridge', 'trip-token-aaaaaaaa');
  end loop;
  raise notice 'PHASE 1: 4 calls, % distinct ids, % rows with that token, THE COUNT IS % (the number the panel produces)',
    (select count(distinct x) from unnest(v_ids) x),
    (select count(*) from public.special_trips where client_token='trip-token-aaaaaaaa'),
    (select count(*) from public.special_trips);
end \$\$;

\echo '### PHASE 2 — CONTROL THAT SUCCEEDS. A genuine second trip, same day, SAME REASON, new token. A natural key would have refused this one.'
do \$\$
declare v_id uuid;
begin
  v_id := public.record_special_trip('$WO'::uuid, 'material_wrong', null, 'second run, same reason', 'trip-token-bbbbbbbb');
  raise notice 'PHASE 2: accepted = %, count now % (must be 2 — this is the case the natural key would have scored as 1)',
    (v_id is not null), (select count(*) from public.special_trips);
end \$\$;

\echo '### PHASE 3 — THE DEPLOYED PANEL, which sends NO token. Must behave exactly as before.'
do \$\$
declare i int;
begin
  for i in 1..4 loop
    perform public.record_special_trip('$WO'::uuid, 'access', '2026-10-06'::date, null);
  end loop;
  raise notice 'PHASE 3: 4 tokenless calls -> % rows (4 = unchanged, rule 5b)',
    (select count(*) from public.special_trips where client_token is null);
end \$\$;

\echo '### PHASE 4 — A BLANK TOKEN IS NO TOKEN. Two blanks must not collapse, or the count sticks at 1 forever.'
do \$\$
declare i int;
begin
  for i in 1..2 loop
    perform public.record_special_trip('$WO'::uuid, 'weather', '2026-10-05'::date, null, '   ');
  end loop;
  raise notice 'PHASE 4: 2 blank-token calls -> % rows on that date, % carrying a token',
    (select count(*) from public.special_trips where occurred_on='2026-10-05'),
    (select count(*) from public.special_trips where occurred_on='2026-10-05' and client_token is not null);
end \$\$;

\echo '### PHASE 5 — DEDUPLICATION MUST NOT ANSWER AN INVALID CALL. A bad reason, WITH a token, is still refused BY NAME.'
do \$\$
declare v_before int; v_after int;
begin
  select count(*) into v_before from public.special_trips;
  begin
    perform public.record_special_trip('$WO'::uuid, 'because_i_said_so', null, null, 'trip-token-eeeeeeee');
    raise notice 'PHASE 5: NOT REFUSED — defect';
  exception when others then
    select count(*) into v_after from public.special_trips;
    raise notice 'PHASE 5: refused by name -> % | rows before % after % (unchanged)', sqlerrm, v_before, v_after;
  end;
end \$\$;
reset role;

-- ============ MUTANT A: remove the FAST PATH, keep the index ============
\echo '### MUTANT A — pre-check deleted. The unique_violation handler alone must still hold.'
create or replace function public.record_special_trip(
  p_work_order_id uuid, p_reason_code text, p_occurred_on date default null::date,
  p_note text default null::text, p_client_token text default null::text)
returns uuid language plpgsql security definer set search_path to 'public' as \$f\$
declare v_org_id uuid; v_actor_id uuid; v_id uuid; v_token text;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');
  select id into v_actor_id from public.profiles where id = auth.uid();
  v_token := nullif(btrim(p_client_token), '');
  -- MUTATION: the fast-path SELECT is gone.
  begin
    insert into public.special_trips (org_id, work_order_id, reason_code, occurred_on, note, recorded_by, client_token)
    values (v_org_id, p_work_order_id, p_reason_code,
            coalesce(p_occurred_on,(now() at time zone 'America/New_York')::date),
            nullif(btrim(coalesce(p_note,'')),''), v_actor_id, v_token)
    returning id into v_id;
  exception when unique_violation then
    select id into v_id from public.special_trips where org_id=v_org_id and client_token=v_token;
    if v_id is null then raise; end if;
  end;
  return v_id;
end \$f\$;

\echo 'ASSERT the mutation is what the database ended up with (rule 22):'
select position('MUTATION: the fast-path SELECT is gone' in p.prosrc) > 0 as mutant_a_installed
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='record_special_trip';

select set_config('role','authenticated',true);
select set_config('request.jwt.claims','{"sub":"$FIELD_USER","role":"authenticated"}',true);
do \$\$
declare i int;
begin
  for i in 1..4 loop
    perform public.record_special_trip('$WO'::uuid, 'rework', null, null, 'trip-token-cccccccc');
  end loop;
  raise notice 'MUTANT A: 4 resends, one token, no pre-check -> % rows (1 = the handler holds alone)',
    (select count(*) from public.special_trips where client_token='trip-token-cccccccc');
end \$\$;
reset role;

-- ============ MUTANT B: remove the fast path AND the index ============
\echo '### MUTANT B — both layers gone. THE DUPLICATE MUST COME BACK, or this suite proves nothing.'
drop index public.special_trips_client_token_uniq;
select set_config('role','authenticated',true);
select set_config('request.jwt.claims','{"sub":"$FIELD_USER","role":"authenticated"}',true);
do \$\$
declare i int; v_n int;
begin
  for i in 1..4 loop
    perform public.record_special_trip('$WO'::uuid, 'equipment', null, null, 'trip-token-dddddddd');
  end loop;
  select count(*) into v_n from public.special_trips where client_token='trip-token-dddddddd';
  raise notice 'MUTANT B: 4 resends, one token, no guard at all -> % rows', v_n;
  if v_n <> 4 then
    raise notice 'MUTANT-REACH FAILED: the duplicate did NOT reproduce, so the suite is not testing what it claims';
  else
    raise notice 'MUTANT-REACH OK: four trips on one day from one tap — the exact defect the migration prevents';
  end if;
end \$\$;
reset role;

\echo '### NOTHING IS KEPT'
rollback;
SQL
echo "--- after rollback, measured in a NEW connection ---"
psql "$SUPABASE_DB_URL" -At -c "select 'special_trips rows: '||count(*) from public.special_trips;" \
  -c "select 'client_token column exists: '||count(*) from information_schema.columns where table_schema='public' and table_name='special_trips' and column_name='client_token';"
