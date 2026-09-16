#!/usr/bin/env bash
# Proves supabase/proposals/20260915_x_w1_15_org_files_policies.sql on a THROWAWAY
# local PostgreSQL cluster. Never touches Supabase.  Track X, X-W1.15, 2026-09-15.
#
#   bash scripts/storage/org-files-fixture/run.sh
#
# Runs the same suite four times:
#   before   no org-files policy (production today)   -> every org-files read is empty
#   proposal the file above, loaded verbatim            -> every test must PASS
#   mutant-entity   proposal minus the work-order join  -> must FAIL (crew reaches a master's file)
#   mutant-tenant   minus the join AND the my_org_ids line -> must FAIL (org B reads org A)
# A suite that passes a mutant proves nothing, so a mutant that passes fails this script.
# exit 0 = proposal passes and both mutants are caught; 1 = otherwise.
set -uo pipefail
export LC_ALL="${LC_ALL:-C}"  # postgres refuses to start with an unset/invalid locale on macOS
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
POLICY="$ROOT/supabase/proposals/20260915_x_w1_15_org_files_policies.sql"
PG_BIN="${PG_BIN:-$(dirname "$(command -v initdb)")}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orgfiles-fixture.XXXXXX")"
PORT="${FIXTURE_PORT:-5499}"
trap '"$PG_BIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1; rm -rf "$WORK"' EXIT

"$PG_BIN/initdb" -D "$WORK/data" -U fixture --auth=trust >/dev/null || exit 1
"$PG_BIN/pg_ctl" -D "$WORK/data" -o "-p $PORT -k $WORK -c listen_addresses=''" -l "$WORK/log" start -w >/dev/null || { cat "$WORK/log"; exit 1; }
PSQL=("$PG_BIN/psql" -h "$WORK" -p "$PORT" -U fixture -X -q -v ON_ERROR_STOP=1)

OA=aaaaaaaa-0000-0000-0000-000000000001; OB=bbbbbbbb-0000-0000-0000-000000000002
OWNER_A=a0000000-0000-0000-0000-00000000000a; OFFICE_A=a0000000-0000-0000-0000-00000000000f
CREW_A=a0000000-0000-0000-0000-0000000000c1; MEMBER_A_NOMASTER=a0000000-0000-0000-0000-0000000000e0
OWNER_B=b0000000-0000-0000-0000-00000000000b
WO_A_MASTER=aaaa0000-0000-0000-0000-000000000a57; WO_A_TRADE=aaaa0000-0000-0000-0000-000000000ade
WO_B_TRADE=bbbb0000-0000-0000-0000-000000000bde

# as <who> <sql>: run inside a rolled-back transaction as that caller; print the value or ERR:<message>.
as() {
  local who="$1" sql="$2" role=authenticated claims=""
  if [ "$who" = anon ]; then role=anon; else claims="set local request.jwt.claims = '{\"sub\":\"$who\",\"role\":\"authenticated\"}';"; fi
  local out
  out=$("${PSQL[@]}" -d "$DB" -t -A -c "begin; $claims set local role $role; $sql; rollback;" 2>&1)
  if [ $? -ne 0 ]; then echo "ERR:$(echo "$out" | grep -o 'ERROR:.*' | head -1 | sed -E 's/^ERROR: +//' | cut -c1-80)"; else echo "$out" | tr -d '\n'; fi
}
read_org() { as "$1" "select coalesce(string_agg(split_part(name,'/',4), ',' order by name), '-') from storage.objects where bucket_id = 'org-files'"; }
del()      { as "$1" "with d as (delete from storage.objects where bucket_id = 'org-files' and name like '%/$2' returning 1) select count(*) from d"; }
ins()      { as "$1" "insert into storage.objects (bucket_id, name) values ('org-files', '$2') returning 'inserted'"; }
upd()      { as "$1" "with u as (update storage.objects set name = '$2' where bucket_id = 'org-files' and name like '%/$3' returning 1) select count(*) from u"; }

RESULTS=""
check() { # suite name expected actual
  local verdict=FAIL
  case "$3" in
    ERR:*) [[ "$4" == "$3"* ]] && verdict=PASS ;;   # an expected refusal matches on its message prefix
    *)     [ "$3" = "$4" ] && verdict=PASS ;;
  esac
  printf '%-14s %-4s %-58s expected=%-38s got=%s\n' "$1" "$verdict" "$2" "$3" "$4"
  RESULTS+="$1 $verdict"$'\n'
}

RLS="ERR:new row violates row-level security policy"
suite() { # suite-name, expectations-for (before|after)
  local s="$1" mode="$2" a
  if [ "$mode" = before ]; then
    for who in OWNER_A OFFICE_A CREW_A MEMBER_A_NOMASTER OWNER_B anon; do check "$s" "read org-files as $who" "-" "$(read_org "${!who:-anon}")"; done
    check "$s" "office inserts a trade work order file" "$RLS" "$(ins "$OFFICE_A" "$OA/office-uploads/$WO_A_TRADE/new.jpg")"
  else
    check "$s" "T1 A owner reads A's files, not B's"         "n1-roof-A-trade.jpg,n2-plan-A-master.pdf" "$(read_org "$OWNER_A")"
    check "$s" "T2 B owner reads B only (not A, not forged)"   "n3-roof-B-trade.jpg" "$(read_org "$OWNER_B")"
    check "$s" "T3 A crew reads the trade file, not the master" "n1-roof-A-trade.jpg" "$(read_org "$CREW_A")"
    check "$s" "T4 A office reads both A files"              "n1-roof-A-trade.jpg,n2-plan-A-master.pdf" "$(read_org "$OFFICE_A")"
    check "$s" "T5 member with master switched off = crew"   "n1-roof-A-trade.jpg" "$(read_org "$MEMBER_A_NOMASTER")"
    check "$s" "T6 anon reads nothing"                        "-" "$(read_org anon)"
    check "$s" "T7 crew cannot delete the roof file"          "0" "$(del "$CREW_A" n1-roof-A-trade.jpg)"
    check "$s" "T8 office can delete the roof file"           "1" "$(del "$OFFICE_A" n1-roof-A-trade.jpg)"
    check "$s" "T9 member (master off) cannot delete"         "0" "$(del "$MEMBER_A_NOMASTER" n1-roof-A-trade.jpg)"
    check "$s" "T10 B owner cannot delete A's file"            "0" "$(del "$OWNER_B" n1-roof-A-trade.jpg)"
    check "$s" "T11 B owner cannot delete the forged file"     "0" "$(del "$OWNER_B" n4-forged.jpg)"
    check "$s" "T12 office uploads to an A trade work order"   "inserted" "$(ins "$OFFICE_A" "$OA/office-uploads/$WO_A_TRADE/new.jpg")"
    check "$s" "T13 office uploads to an A master work order"  "inserted" "$(ins "$OFFICE_A" "$OA/work-order-docs/$WO_A_MASTER/new.pdf")"
    check "$s" "T14 crew cannot upload"                        "$RLS" "$(ins "$CREW_A" "$OA/office-uploads/$WO_A_TRADE/new.jpg")"
    check "$s" "T15 A prefix naming B's work order refused"     "$RLS" "$(ins "$OFFICE_A" "$OA/office-uploads/$WO_B_TRADE/new.jpg")"
    check "$s" "T16 B prefix written by A office refused"       "$RLS" "$(ins "$OFFICE_A" "$OB/office-uploads/$WO_B_TRADE/new.jpg")"
    check "$s" "T17 uncovered category refused"                 "$RLS" "$(ins "$OFFICE_A" "$OA/estimate-pdfs/$WO_A_TRADE/new.pdf")"
    check "$s" "T18 extra path depth refused"                   "$RLS" "$(ins "$OFFICE_A" "$OA/office-uploads/$WO_A_TRADE/sub/new.jpg")"
    check "$s" "T19 malformed name refused, no cast error"      "$RLS" "$(ins "$OFFICE_A" "not-a-uuid/office-uploads/x/new.jpg")"
    check "$s" "T20 owner cannot move a file into B's prefix"   "0" "$(upd "$OWNER_A" "$OB/office-uploads/$WO_B_TRADE/moved.jpg" n1-roof-A-trade.jpg)"
  fi
  # CONTROLS — identical in every suite.
  check "$s" "C1 anon still reads product-photos"   "p1.jpg" "$(as anon "select coalesce(string_agg(split_part(name,'/',2), ','), '-') from storage.objects where bucket_id = 'product-photos'")"
  check "$s" "C2 crew still reads product-photos"   "p1.jpg" "$(as "$CREW_A" "select coalesce(string_agg(split_part(name,'/',2), ','), '-') from storage.objects where bucket_id = 'product-photos'")"
  check "$s" "C3 owner still cannot read pdf-files" "-"      "$(as "$OWNER_A" "select coalesce(string_agg(name, ','), '-') from storage.objects where bucket_id = 'pdf-files'")"
  check "$s" "C4 full-table scan raises nothing"    "ok"     "$(as "$OWNER_A" "select 'ok' from (select count(*) from storage.objects) x")"
}

load() { # db-name, policy-sql-file-or-empty
  DB="$1"
  "${PSQL[@]}" -d postgres -c "create database $DB" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/schema.sql" >/dev/null || exit 1
  "${PSQL[@]}" -d "$DB" -f "$HERE/data.sql" >/dev/null || exit 1
  if [ -n "$2" ]; then "${PSQL[@]}" -d "$DB" -f "$2" >/dev/null || { echo "policy file failed to load: $2"; exit 1; }; fi
}

echo "== before: no org-files policy (production today) =="
load before ""; suite before before
echo "== proposal: $POLICY =="
load proposal "$POLICY"; suite proposal after
echo "== mutant-entity: work-order join removed =="
perl -0pe 's/\n\s+and exists \(\n.*?\n\s+\)\n/\n/sg' "$POLICY" > "$WORK/mutant-entity.sql"
grep -c "and exists" "$WORK/mutant-entity.sql" | xargs echo "  (exists clauses left in mutant: expect 0 →"; echo "   )"
load mutant_entity "$WORK/mutant-entity.sql"; suite mutant-entity after
echo "== mutant-tenant: work-order join AND my_org_ids line removed =="
grep -v "my_org_ids" "$WORK/mutant-entity.sql" > "$WORK/mutant-tenant.sql"
load mutant_tenant "$WORK/mutant-tenant.sql"; suite mutant-tenant after

echo "== the 9/03 cast, for the record: guarded and unguarded =="
DB=proposal
for variant in unguarded guarded; do
  guard=""; [ "$variant" = guarded ] && guard="and (storage.foldername(name))[1] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\$'"
  "${PSQL[@]}" -d postgres -c "drop database if exists cast_$variant" >/dev/null
  load "cast_$variant" ""
  "${PSQL[@]}" -d "cast_$variant" -c "create policy \"9/03 org read\" on storage.objects for select to authenticated using (bucket_id = 'org-files' $guard and ((storage.foldername(name))[1])::uuid in (select my_org_ids()))" >/dev/null
  echo "  $variant: owner reads product-photos -> $(as "$OWNER_A" "select coalesce(string_agg(name, ','), '-') from storage.objects where bucket_id = 'product-photos'")"
  echo "  $variant: owner reads org-files      -> $(as "$OWNER_A" "select count(*) from storage.objects where bucket_id = 'org-files'")"
done

fail() { echo "$RESULTS" | grep -c "^$1 FAIL"; }
echo "------------------------------------------------------------------------"
echo "before: $(fail before) fail · proposal: $(fail proposal) fail · mutant-entity: $(fail mutant-entity) fail · mutant-tenant: $(fail mutant-tenant) fail"
if [ "$(fail before)" -eq 0 ] && [ "$(fail proposal)" -eq 0 ] && [ "$(fail mutant-entity)" -gt 0 ] && [ "$(fail mutant-tenant)" -gt 0 ]; then
  echo "PROVED: proposal passes every test, and the suite catches both weakened policies."; exit 0
fi
echo "NOT PROVED."; exit 1
