#!/usr/bin/env bash
# A4.6 VEHICLE-REFUSAL FIXTURE — the mutant attacks the text that actually runs.
# Track S · 2026-10-01. §7.1 RULE 20 / CLAUDE.md rule 22.
#
# Object under test: public.assign_crew_to_work_order. The LAST file defining it is
# supabase/migrations/<version>_crew_vehicle_refusal.sql, and that is what is mutated.
#
#   PHASE 1  assert against what the database holds        -> must PASS
#   PHASE 2  with the refusal deleted                      -> must FAIL
#   PHASE 3  mutant reach: the refusal must be GONE from the live body
# All three run inside transactions that roll back. Nothing is written.
set -uo pipefail
cd "$(dirname "$0")/../../.."
[ -f .env.local ] || { echo "STOPPED: .env.local not found (by filename; no contents read)"; exit 2; }
DB=$(grep -E '^SUPABASE_DB_URL=' .env.local | head -1 | sed 's/^SUPABASE_DB_URL=//; s/#.*//' | tr -d ' ')
[ -n "$DB" ] || { echo "STOPPED: SUPABASE_DB_URL is not set in .env.local"; exit 2; }
TARGET=$(ls -1 supabase/migrations/*_crew_vehicle_refusal.sql 2>/dev/null | tail -1)
[ -n "$TARGET" ] || { echo "STOPPED: no *_crew_vehicle_refusal.sql in supabase/migrations"; exit 2; }
echo "MUTATING: $TARGET   (the LAST file defining assign_crew_to_work_order)"

read -r -d '' ASSERT <<'SQL'
do $$
declare
  v_org uuid := 'e0851ad8-35d6-4e17-b267-6cd35cb6f713';
  v_office uuid; v_wo uuid; v_crew uuid; v_p uuid;
  r jsonb; v_hint text; v_outcome text;
begin
  select user_id into v_office from public.org_members where org_id=v_org and role='office';
  select id into v_wo from public.work_orders where org_id=v_org and kind='trade' and voided_at is null limit 1;
  update public.organizations set policy = policy || '{"enforce_stage_gating": true}'::jsonb where id=v_org;
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_office::text,'role','authenticated')::text, true);
  v_crew := public.create_crew(v_org,'FIXTURE crew no vehicle');
  v_p := public.create_crew_person(v_org,'Fixture Person',null,null,null,false,null,null);
  perform public.add_crew_member(v_crew, v_p, true);
  -- The outcome is RECORDED and JUDGED after the handler, so the fixture's own raise
  -- cannot be caught by its own handler and re-reported as the wrong cause.
  begin
    r := public.assign_crew_to_work_order(v_wo, v_crew, 'tear-off');
    v_outcome := format('ASSIGNED with vehicle_state=%s', r->>'vehicle_state');
  exception when others then
    get stacked diagnostics v_hint = PG_EXCEPTION_HINT;
    v_outcome := format('REFUSED with hint [%s]', coalesce(v_hint,'(none)'));
  end;
  perform set_config('role','postgres',true);
  if v_outcome = 'REFUSED with hint [crew_has_no_vehicle]' then
    raise notice 'ASSERTION PASSED: %', v_outcome;
  else
    raise exception 'ASSERTION FAILED: % — expected REFUSED with hint [crew_has_no_vehicle]', v_outcome;
  end if;
end $$;
SQL

run_assert () { { echo "begin;"; [ -n "$1" ] && cat "$1"; echo "$ASSERT"; echo "rollback;"; } | psql "$DB" -X -q -v ON_ERROR_STOP=1 2>&1; }

echo; echo "── PHASE 1 · against what the database actually holds"
OUT=$(run_assert ""); RC=$?
echo "$OUT" | grep -E 'NOTICE|ERROR' | sed 's/^psql[^ ]* //'
[ $RC -eq 0 ] || { echo "RESULT: NOT PROVED — the real object already fails the assertion."; exit 1; }

echo; echo "── PHASE 2 · with the mutant (the crew_has_no_vehicle refusal deleted)"
MUT=$(mktemp); trap 'rm -f "$MUT"' EXIT
python3 - "$TARGET" "$MUT" <<'PY'
import re,sys
src=open(sys.argv[1]).read()
pat = re.compile(r"\n  if coalesce\(public\.tenant_enforces_stage_gating.*?\n  end if;\n", re.S)
out,n = pat.subn("\n", src)
if n != 1:
    print("MUTANT DID NOT APPLY: matched %d times, expected 1" % n, file=sys.stderr); sys.exit(3)
open(sys.argv[2],'w').write(out)
PY
[ $? -eq 0 ] || { echo "RESULT: NOT PROVED — the mutation could not be built."; exit 1; }
OUT=$(run_assert "$MUT"); RC=$?
echo "$OUT" | grep -E 'NOTICE|ERROR' | sed 's/^psql[^ ]* //'
[ $RC -ne 0 ] || { echo "RESULT: NOT PROVED — THE MUTANT PASSED. The assertion cannot fail."; exit 1; }

echo; echo "── PHASE 3 · mutant reach: is the refusal actually gone from the live body?"
REACH=$({ echo "begin;"; cat "$MUT"; echo "select case when prosrc ~ 'crew_has_no_vehicle' then 'STILL PRESENT' else 'GONE' end from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='assign_crew_to_work_order';"; echo "rollback;"; } | psql "$DB" -X -q -tA -v ON_ERROR_STOP=1 2>&1 | tr -d ' ')
echo "  live body after the mutant applies: $REACH"
[ "$REACH" = "GONE" ] || { echo "RESULT: NOT PROVED — the mutation did not reach the object the database ends up with."; exit 1; }

echo; echo "RESULT: PROVED — passes on the real object, FAILS on the mutant, and the mutant lands"
echo "        on the text the database actually runs."
