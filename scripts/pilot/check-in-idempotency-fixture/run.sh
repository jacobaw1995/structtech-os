#!/usr/bin/env bash
# MUTATION TEST for 20261004213144_a_repeat_tap_is_the_same_check_in.
#
# Everything runs inside ONE transaction that is ROLLED BACK. Nothing is written.
# The calls are made as the REAL field user who wrote the live check-in at
# 16:51 EDT today, so a refusal would be a real refusal.
#
# Rule 22: the mutant attacks the LAST text that defines the object — the
# function body this migration installs — and each phase prints the SIZE of what
# it examined beside its result (rule 24/26), so a zero cannot pass for a pass.
set -euo pipefail
cd "$(dirname "$0")/../../.."
set -a; . ./.env.local >/dev/null 2>&1; set +a
BODY="$(cat scripts/pilot/check-in-idempotency-fixture/migration_body.sql)"
FIELD_USER='e1cd8efd-574f-4d6e-9007-f3c31edad0e9'
WO='d76d8664-3337-4e2c-a898-b3b5bae32415'

psql "$SUPABASE_DB_URL" -P pager=off -v ON_ERROR_STOP=1 <<SQL
begin;

\echo '### BEFORE'
select count(*) as check_ins_before from public.check_ins;

-- ============ APPLY THE MIGRATION BODY ============
$BODY

\echo '### THE CONSTRAINT NOW EXISTS'
select i.relname, idx.indisunique, pg_get_indexdef(idx.indexrelid) as def
from pg_index idx join pg_class i on i.oid=idx.indexrelid join pg_class t on t.oid=idx.indrelid
where t.relname='check_ins' and idx.indisunique;

-- Become the roofer for every call under test.
select set_config('role','authenticated',true);
select set_config('request.jwt.claims','{"sub":"$FIELD_USER","role":"authenticated"}',true);

\echo '### PHASE 1 — FOUR TAPS, ONE TOKEN. The real object. Expect 1 row, 1 distinct id.'
do \$\$
declare v_ids uuid[] := '{}'; i int;
begin
  for i in 1..4 loop
    v_ids := v_ids || public.create_check_in('$WO'::uuid, 'Anderson Reyes', null, '2026-10-07'::date, 8, 'ridge cap', null, null, 'tap-token-aaaaaaaa');
  end loop;
  raise notice 'PHASE 1: 4 calls made, % distinct ids returned, % rows with that token',
    (select count(distinct x) from unnest(v_ids) x),
    (select count(*) from public.check_ins where client_token='tap-token-aaaaaaaa');
end \$\$;

\echo '### PHASE 2 — CONTROL THAT SUCCEEDS. A deliberate second check-in, new token.'
do \$\$
declare v_id uuid;
begin
  v_id := public.create_check_in('$WO'::uuid, 'Anderson Reyes', null, '2026-10-07'::date, 2, 'second trip', null, null, 'tap-token-bbbbbbbb');
  raise notice 'PHASE 2: new token accepted = %, rows on 2026-10-07 now %',
    (v_id is not null), (select count(*) from public.check_ins where check_in_date='2026-10-07');
end \$\$;

\echo '### PHASE 3 — THE DEPLOYED UI, which sends NO token. Must behave exactly as before.'
do \$\$
declare i int;
begin
  for i in 1..4 loop
    perform public.create_check_in('$WO'::uuid, 'Anderson Reyes', null, '2026-10-06'::date, 8, 'no token sent', null, null);
  end loop;
  raise notice 'PHASE 3: 4 tokenless calls -> % rows (4 = unchanged, backward compatible)',
    (select count(*) from public.check_ins where check_in_date='2026-10-06' and client_token is null);
end \$\$;

\echo '### PHASE 4 — BLANK TOKEN IS NO TOKEN. Two blanks must NOT collapse onto each other.'
do \$\$
declare i int;
begin
  for i in 1..2 loop
    perform public.create_check_in('$WO'::uuid, 'Anderson Reyes', null, '2026-10-05'::date, 1, 'blank token', null, null, '   ');
  end loop;
  raise notice 'PHASE 4: 2 blank-token calls -> % rows, % of them with a non-null token',
    (select count(*) from public.check_ins where check_in_date='2026-10-05'),
    (select count(*) from public.check_ins where check_in_date='2026-10-05' and client_token is not null);
end \$\$;

reset role;

-- ============ MUTANT A: remove the FAST PATH, keep the index ============
\echo '### MUTANT A — the pre-check deleted. The exception handler alone must still hold.'
create or replace function public.create_check_in(
  p_work_order_id uuid, p_crew_name text, p_schedule_block_id uuid default null::uuid,
  p_check_in_date date default null::date, p_hours numeric default null::numeric,
  p_materials_used text default null::text, p_blockers text default null::text,
  p_crew_id uuid default null::uuid, p_client_token text default null::text)
returns uuid language plpgsql security definer set search_path to 'public' as \$f\$
declare v_org_id uuid; v_check_in_id uuid; v_token text;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');
  v_token := nullif(btrim(p_client_token), '');
  -- MUTATION: the fast-path SELECT is gone.
  begin
    insert into public.check_ins (org_id, work_order_id, crew_id, crew_name, check_in_date, hours, client_token)
    values (v_org_id, p_work_order_id, p_crew_id, coalesce(nullif(btrim(p_crew_name),''),'(crew)'),
            coalesce(p_check_in_date,(now() at time zone 'America/New_York')::date), p_hours, v_token)
    returning id into v_check_in_id;
  exception when unique_violation then
    select id into v_check_in_id from public.check_ins where org_id=v_org_id and client_token=v_token;
    if v_check_in_id is null then raise; end if;
  end;
  return v_check_in_id;
end \$f\$;

\echo 'ASSERT the mutation is what the database ended up with (rule 22):'
select position('MUTATION: the fast-path SELECT is gone' in p.prosrc) > 0 as mutant_a_is_installed
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='create_check_in';

select set_config('role','authenticated',true);
select set_config('request.jwt.claims','{"sub":"$FIELD_USER","role":"authenticated"}',true);
do \$\$
declare i int;
begin
  for i in 1..4 loop
    perform public.create_check_in('$WO'::uuid, 'Anderson Reyes', null, '2026-10-08'::date, 8, null, null, null, 'tap-token-cccccccc');
  end loop;
  raise notice 'MUTANT A: 4 taps, one token, no pre-check -> % rows (1 = the handler holds; the two layers are independent)',
    (select count(*) from public.check_ins where client_token='tap-token-cccccccc');
end \$\$;
reset role;

-- ============ MUTANT B: remove the fast path AND the index ============
\echo '### MUTANT B — both layers removed. THE DUPLICATE MUST COME BACK, or this suite proves nothing.'
drop index public.check_ins_client_token_uniq;
select set_config('role','authenticated',true);
select set_config('request.jwt.claims','{"sub":"$FIELD_USER","role":"authenticated"}',true);
do \$\$
declare i int; v_n int;
begin
  for i in 1..4 loop
    perform public.create_check_in('$WO'::uuid, 'Anderson Reyes', null, '2026-10-09'::date, 8, null, null, null, 'tap-token-dddddddd');
  end loop;
  select count(*) into v_n from public.check_ins where client_token='tap-token-dddddddd';
  raise notice 'MUTANT B: 4 taps, one token, no guard at all -> % rows', v_n;
  if v_n <> 4 then
    raise notice 'MUTANT-REACH FAILED: the duplicate did NOT reproduce, so the suite is not testing what it claims';
  else
    raise notice 'MUTANT-REACH OK: this is the exact defect the migration prevents, reproduced on demand';
  end if;
end \$\$;
reset role;

\echo '### NOTHING IS KEPT'
rollback;
SQL
echo "--- after rollback, measured in a NEW connection ---"
psql "$SUPABASE_DB_URL" -At -c "select 'check_ins rows: '||count(*) from public.check_ins;" \
  -c "select 'client_token column exists: '||count(*) from information_schema.columns where table_schema='public' and table_name='check_ins' and column_name='client_token';"
