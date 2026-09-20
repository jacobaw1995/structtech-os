#!/usr/bin/env bash
# Proves supabase/proposals/20260919_x_w1_20_qc_items.sql on a THROWAWAY local
# PostgreSQL cluster. Never touches Supabase.  Track X, X-W1.20, 2026-09-19.
#   bash scripts/pilot/qc-items-fixture/run.sh
# Reuses the live-helper mirror from scripts/storage/org-files-fixture/schema.sql
# (my_org_ids, has_capability, can_view_master_work_order, auth.uid — verbatim from
# the live project), then loads the proposal verbatim and runs the suite against it
# and two mutants that MUST be caught.
# exit 0 = proposal passes and both mutants fail.
set -uo pipefail
export LC_ALL="${LC_ALL:-C}"
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../../.." && pwd)"
PROPOSAL="$ROOT/supabase/proposals/20260919_x_w1_20_qc_items.sql"
MIRROR="$ROOT/scripts/storage/org-files-fixture/schema.sql"
PG_BIN="${PG_BIN:-$(dirname "$(command -v initdb)")}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/qc-items-fixture.XXXXXX")"; PORT="${FIXTURE_PORT:-5496}"
trap '"$PG_BIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1; rm -rf "$WORK"' EXIT
"$PG_BIN/initdb" -D "$WORK/data" -U fixture --auth=trust >/dev/null || exit 1
"$PG_BIN/pg_ctl" -D "$WORK/data" -o "-p $PORT -k $WORK -c listen_addresses=''" -l "$WORK/log" start -w >/dev/null || { cat "$WORK/log"; exit 1; }
PSQL=("$PG_BIN/psql" -h "$WORK" -p "$PORT" -U fixture -X -q -v ON_ERROR_STOP=1)

OA=aaaaaaaa-0000-0000-0000-000000000001; OB=bbbbbbbb-0000-0000-0000-000000000002
OFFICE_A=a0000000-0000-0000-0000-00000000000f; CREW_A=a0000000-0000-0000-0000-0000000000c1
OWNER_B=b0000000-0000-0000-0000-00000000000b
WO_A=aaaa0000-0000-0000-0000-000000000ade; WO_A_MASTER=aaaa0000-0000-0000-0000-000000000a57
WO_B=bbbb0000-0000-0000-0000-000000000bde
REF=0123456789abcdef

load() {
  DB="$1"
  "${PSQL[@]}" -d postgres -c "create database $DB" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$MIRROR" >/dev/null || exit 1
  "${PSQL[@]}" -d "$DB" >/dev/null <<SQL || exit 1
create table public.organizations (id uuid primary key);
insert into public.organizations values ('$OA'), ('$OB');
insert into public.org_members values
  ('$OA','$OFFICE_A','office','{"view_master_work_order":true}'),
  ('$OA','$CREW_A','field','{"view_master_work_order":false}'),
  ('$OB','$OWNER_B','owner','{}');
insert into public.work_orders values ('$WO_A','$OA','trade'), ('$WO_A_MASTER','$OA','master'), ('$WO_B','$OB','trade');
SQL
  "${PSQL[@]}" -d "$DB" -f "$2" >/dev/null || { echo "proposal failed to load: $2"; exit 1; }
  "${PSQL[@]}" -d "$DB" -c "insert into public.qc_items (org_id, work_order_id, requirement_key, kind, photo_ref, actor_id) values ('$OA','$WO_A','seeded_trade','photo','$REF','$CREW_A'), ('$OA','$WO_A_MASTER','seeded_master','photo','$REF','$OFFICE_A'), ('$OB','$WO_B','seeded_other_org','photo','$REF','$OWNER_B')" >/dev/null || exit 1
}
as() { local who="$1" role=authenticated claims=""
  case "$who" in anon) role=anon;; nobody) ;; *) claims="set local request.jwt.claims = '{\"sub\":\"$who\",\"role\":\"authenticated\"}';";; esac
  local out; out=$("${PSQL[@]}" -d "$DB" -t -A -c "begin; $claims set local role $role; $2; rollback;" 2>&1)
  if [ $? -ne 0 ]; then echo "ERR:$(echo "$out" | grep -o 'ERROR:.*' | head -1 | sed -E 's/^ERROR: +//' | cut -c1-70)"; else echo "$out" | tail -1; fi
}
RESULTS=""
check() { local v=FAIL; case "$3" in ERR:*) [[ "$4" == "$3"* ]] && v=PASS;; *) [ "$3" = "$4" ] && v=PASS;; esac
  printf '%-14s %-4s %-60s expected=%-36s got=%s\n' "$1" "$v" "$2" "$3" "$4"; RESULTS+="$1 $v"$'\n'; }
rec() { as "$1" "select case when public.record_qc_item($2) is null then 'null' else 'recorded' end"; }
suite() { local s="$1"
  check "$s" "Q1 crew records a photo requirement on their trade job" "recorded" "$(rec "$CREW_A" "'$WO_A','valley_flashing','photo','$REF'")"
  check "$s" "Q2 crew records a count"                                "recorded" "$(rec "$CREW_A" "'$WO_A','ridge_cap_rivets','count',null,42")"
  check "$s" "Q3 crew records a sweep confirmation"                   "recorded" "$(rec "$CREW_A" "'$WO_A','magnet_sweep','confirm'")"
  check "$s" "Q4 crew cannot record against another org's job"        "ERR:that work order is not one you can record against" "$(rec "$CREW_A" "'$WO_B','valley_flashing','photo','$REF'")"
  check "$s" "Q5 crew cannot record against a master they cannot see" "ERR:that work order is not one you can record against" "$(rec "$CREW_A" "'$WO_A_MASTER','valley_flashing','photo','$REF'")"
  check "$s" "Q6 office CAN record against that master"               "recorded" "$(rec "$OFFICE_A" "'$WO_A_MASTER','valley_flashing','photo','$REF'")"
  check "$s" "Q7 no identity records nothing"                         "ERR:not signed in" "$(rec nobody "'$WO_A','magnet_sweep','confirm'")"
  check "$s" "Q8 anon cannot call the function"                       "ERR:permission denied for function record_qc_item" "$(rec anon "'$WO_A','magnet_sweep','confirm'")"
  check "$s" "Q9 a photo requirement needs a photo"                   "ERR:new row for relation \"qc_items\" violates check" "$(rec "$CREW_A" "'$WO_A','valley_flashing','photo'")"
  check "$s" "Q10 a customer name cannot enter as a requirement key"  "ERR:new row for relation \"qc_items\" violates check" "$(rec "$CREW_A" "'$WO_A','Smith residence','photo','$REF'")"
  check "$s" "Q11 a filename cannot enter as a photo reference"       "ERR:new row for relation \"qc_items\" violates check" "$(rec "$CREW_A" "'$WO_A','valley_flashing','photo','Smith-roof.jpg'")"
  check "$s" "Q12 a price cannot enter as a count"                    "ERR:new row for relation \"qc_items\" violates check" "$(rec "$CREW_A" "'$WO_A','ridge_cap_rivets','count',null,1234000")"
  check "$s" "Q13 re-recording leaves ONE live row"                   "1" "$(as "$CREW_A" "select public.record_qc_item('$WO_A','magnet_sweep','confirm'); select public.record_qc_item('$WO_A','magnet_sweep','confirm'); select count(*) from public.qc_items where requirement_key='magnet_sweep' and cleared_at is null")"
  check "$s" "Q14 …and keeps the earlier one as history"              "2" "$(as "$CREW_A" "select public.record_qc_item('$WO_A','magnet_sweep','confirm'); select public.record_qc_item('$WO_A','magnet_sweep','confirm'); select count(*) from public.qc_items where requirement_key='magnet_sweep'")"
  check "$s" "Q15 clearing removes the live row"                      "0" "$(as "$CREW_A" "select public.record_qc_item('$WO_A','magnet_sweep','confirm'); select public.clear_qc_item('$WO_A','magnet_sweep'); select count(*) from public.qc_items where requirement_key='magnet_sweep' and cleared_at is null")"
  check "$s" "Q16 crew reads their own job's row (seeded)"            "seeded_trade" "$(as "$CREW_A" "select string_agg(requirement_key, ',' order by requirement_key) from public.qc_items")"
  check "$s" "Q17 office reads the trade AND the master rows"         "seeded_master,seeded_trade" "$(as "$OFFICE_A" "select string_agg(requirement_key, ',' order by requirement_key) from public.qc_items")"
  check "$s" "Q18 B's owner reads only B's row"                       "seeded_other_org" "$(as "$OWNER_B" "select string_agg(requirement_key, ',' order by requirement_key) from public.qc_items")"
  check "$s" "Q19 direct INSERT refused (writes go through the RPC)"  "ERR:permission denied for table qc_items" "$(as "$CREW_A" "insert into public.qc_items (org_id, work_order_id, requirement_key, kind, photo_ref, actor_id) values ('$OA','$WO_A','valley_flashing','photo','$REF','$CREW_A')")"
  check "$s" "Q20 UPDATE refused"                                     "ERR:permission denied for table qc_items" "$(as "$CREW_A" "update public.qc_items set requirement_key='x'")"
  check "$s" "Q21 anon reads nothing"                                 "ERR:permission denied for table qc_items" "$(as anon "select count(*) from public.qc_items")"
  check "$s" "Q22 no column can hold free text"                       "0" "$(as nobody "select count(*) from information_schema.columns c where c.table_schema='public' and c.table_name='qc_items' and (c.data_type in ('json','jsonb') or (c.data_type in ('text','character varying') and not exists (select 1 from pg_constraint k join pg_attribute a on a.attrelid=k.conrelid and a.attnum = any(k.conkey) where k.conrelid='public.qc_items'::regclass and k.contype='c' and a.attname=c.column_name)))")"
}
echo "== proposal =="; load proposal "$PROPOSAL"; suite proposal
echo "== mutant-reach: the work-order reachability test removed =="
perl -0pe "s/\n    and w\.org_id in \(select public\.my_org_ids\(\)\)\n    and \(w\.kind = 'trade' or public\.can_view_master_work_order\(w\.org_id\)\)//" "$PROPOSAL" > "$WORK/m1.sql"
load m_reach "$WORK/m1.sql"; suite mutant-reach
echo "== mutant-evidence: the evidence-matches-kind constraint removed =="
node -e 'const fs=require("fs");const t=fs.readFileSync(process.argv[1],"utf8");const i=t.indexOf("constraint qc_items_evidence_matches_kind check (");const j=t.indexOf("\n  ),",i);if(i<0||j<0){console.error("mutant anchor missing");process.exit(1)}fs.writeFileSync(process.argv[2], t.slice(0,i)+"constraint qc_items_evidence_matches_kind check (true"+t.slice(j))' "$PROPOSAL" "$WORK/m2.sql" || exit 1
  grep -c "check (true" "$WORK/m2.sql" | xargs echo "  (neutralised constraints in mutant, expect 1:"; echo "  )"
load m_evidence "$WORK/m2.sql"; suite mutant-evidence
fail() { echo "$RESULTS" | grep -c "^$1 FAIL"; }
echo "------------------------------------------------------------------------"
echo "proposal: $(fail proposal) fail · mutant-reach: $(fail mutant-reach) fail · mutant-evidence: $(fail mutant-evidence) fail"
if [ "$(fail proposal)" -eq 0 ] && [ "$(fail mutant-reach)" -gt 0 ] && [ "$(fail mutant-evidence)" -gt 0 ]; then echo "PROVED"; exit 0; fi
echo "NOT PROVED"; exit 1
