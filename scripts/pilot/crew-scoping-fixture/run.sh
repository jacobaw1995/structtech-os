#!/usr/bin/env bash
# CREW SCOPING FIXTURE — and the mutant attacks the text that actually runs.
# Track S · 2026-09-29. §7.1 RULE 20 / CLAUDE.md rule 22.
#
# THE OBJECT UNDER TEST is public.fetch_field_jobs, and the LAST FILE THAT DEFINES IT is
# supabase/migrations/<version>_crew_scoped_field_jobs.sql. The mutant is applied to THAT
# file, because in a layered migration the last definition wins and a test that patches an
# earlier layer tests nothing.
#
# Three phases, all inside transactions that roll back. Nothing is written.
#   PHASE 1  assert against what the database actually holds        -> must PASS
#   PHASE 2  apply the MUTANT (the crew_not_assigned refusal deleted) -> must FAIL
#   PHASE 3  prove the mutant reached the object: after applying it, the live body must NOT
#            contain the refusal. A mutant that never landed is not a mutant.
set -uo pipefail
cd "$(dirname "$0")/../../.."
[ -f .env.local ] || { echo "STOPPED: .env.local not found (by filename; no contents read)"; exit 2; }
DB=$(grep -E '^SUPABASE_DB_URL=' .env.local | head -1 | sed 's/^SUPABASE_DB_URL=//; s/#.*//' | tr -d ' ')
[ -n "$DB" ] || { echo "STOPPED: SUPABASE_DB_URL is not set in .env.local"; exit 2; }

TARGET=$(ls -1 supabase/migrations/*_crew_scoped_field_jobs.sql 2>/dev/null | tail -1)
[ -n "$TARGET" ] || { echo "STOPPED: no *_crew_scoped_field_jobs.sql in supabase/migrations"; exit 2; }
echo "MUTATING: $TARGET   (the LAST file defining fetch_field_jobs)"

ORG=e0851ad8-35d6-4e17-b267-6cd35cb6f713   # the disposable synthetic tenant

# The assertion: with the switch ON and the caller on no crew, the call must REFUSE with
# hint 'crew_not_assigned'. Returning rows — or returning an empty array — is a FAIL.
read -r -d '' ASSERT <<'SQL'
do $$
declare
  v_org uuid := 'e0851ad8-35d6-4e17-b267-6cd35cb6f713';
  v_field uuid; v_today date := (now() at time zone 'America/New_York')::date;
  v_hint text; v jsonb; v_outcome text;
begin
  select user_id into v_field from public.org_members where org_id=v_org and role='field';
  update public.organizations set policy = policy || '{"scope_field_jobs_to_crew": true}'::jsonb where id=v_org;
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_field::text,'role','authenticated')::text, true);
  -- The outcome is RECORDED here and JUDGED after the handler. Judging inside it meant the
  -- fixture's own 'ASSERTION FAILED' raise — a P0001 with no hint — was caught by its own
  -- handler and re-reported as "refused with hint []". The verdict was right and the printed
  -- CAUSE was wrong, which is the one thing an instrument must never do.
  begin
    v := public.fetch_field_jobs(v_org, v_today);
    v_outcome := format('RETURNED %s row(s)', jsonb_array_length(v));
  exception when others then
    get stacked diagnostics v_hint = PG_EXCEPTION_HINT;
    v_outcome := format('REFUSED with hint [%s]', coalesce(v_hint,'(none)'));
  end;
  perform set_config('role','postgres',true);

  if v_outcome = 'REFUSED with hint [crew_not_assigned]' then
    raise notice 'ASSERTION PASSED: %', v_outcome;
  else
    raise exception 'ASSERTION FAILED: % — expected REFUSED with hint [crew_not_assigned]', v_outcome;
  end if;
end $$;
SQL

run_assert () {  # $1 = extra sql applied first (the mutant), or empty
  { echo "begin;"; [ -n "$1" ] && cat "$1"; echo "$ASSERT"; echo "rollback;"; } \
    | psql "$DB" -X -q -v ON_ERROR_STOP=1 2>&1
}

echo
echo "── PHASE 1 · against what the database actually holds"
OUT=$(run_assert ""); RC=$?
echo "$OUT" | grep -E 'NOTICE|ERROR' | sed 's/^psql[^ ]* //'
[ $RC -eq 0 ] || { echo "RESULT: NOT PROVED — the real object already fails the assertion."; exit 1; }

echo
echo "── PHASE 2 · with the mutant (the crew_not_assigned refusal deleted)"
MUT=$(mktemp); trap 'rm -f "$MUT"' EXIT
python3 - "$TARGET" "$MUT" <<'PY'
import re,sys
src=open(sys.argv[1]).read()
# Delete the refusal itself, leaving the count query — the exact defect this fixture exists
# to catch: an unassigned caller falls through and receives an EMPTY ARRAY.
pat = re.compile(r"\n    if v_crew_count = 0 then\n.*?\n    end if;\n", re.S)
out, n = pat.subn("\n", src)
if n != 1:
    print("MUTANT DID NOT APPLY: pattern matched %d times, expected 1" % n, file=sys.stderr); sys.exit(3)
open(sys.argv[2],'w').write(out)
PY
[ $? -eq 0 ] || { echo "RESULT: NOT PROVED — the mutation could not be built."; exit 1; }
OUT=$(run_assert "$MUT"); RC=$?
echo "$OUT" | grep -E 'NOTICE|ERROR' | sed 's/^psql[^ ]* //'
[ $RC -ne 0 ] || { echo "RESULT: NOT PROVED — THE MUTANT PASSED. The assertion cannot fail, so it proves nothing."; exit 1; }

echo
echo "── PHASE 3 · mutant reach: after applying the mutant, is the refusal actually gone?"
REACH=$({ echo "begin;"; cat "$MUT"; echo "select case when prosrc ~ 'crew_not_assigned' then 'STILL PRESENT' else 'GONE' end from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fetch_field_jobs';"; echo "rollback;"; } \
  | psql "$DB" -X -q -tA -v ON_ERROR_STOP=1 2>&1 | tr -d ' ')
echo "  live body after the mutant applies: $REACH"
[ "$REACH" = "GONE" ] || { echo "RESULT: NOT PROVED — the mutation did not reach the object the database ends up with."; exit 1; }

echo
echo "RESULT: PROVED — the assertion passes on the real object, FAILS on the mutant, and the"
echo "        mutant demonstrably lands on the text the database actually runs."
