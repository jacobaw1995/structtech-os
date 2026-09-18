#!/usr/bin/env bash
# Proves supabase/proposals/20260917_x_w1_19_field_events.sql on a THROWAWAY local
# PostgreSQL cluster. Never touches Supabase.  Track X, X-W1.19, 2026-09-17.
#   bash scripts/pilot/field-events-fixture/run.sh
# Reuses the live-helper mirror from scripts/storage/org-files-fixture/schema.sql
# (my_org_ids, has_capability, can_view_master_work_order, auth.uid — verbatim
# from the live project), adds organizations, loads the proposal verbatim, and runs
# the suite against the proposal and two mutants that MUST be caught.
# exit 0 = proposal passes and both mutants fail.
set -uo pipefail
export LC_ALL="${LC_ALL:-C}"
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../../.." && pwd)"
PROPOSAL="$ROOT/supabase/proposals/20260917_x_w1_19_field_events.sql"
MIRROR="$ROOT/scripts/storage/org-files-fixture/schema.sql"
PG_BIN="${PG_BIN:-$(dirname "$(command -v initdb)")}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/field-events-fixture.XXXXXX")"; PORT="${FIXTURE_PORT:-5498}"
trap '"$PG_BIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1; rm -rf "$WORK"' EXIT
"$PG_BIN/initdb" -D "$WORK/data" -U fixture --auth=trust >/dev/null || exit 1
"$PG_BIN/pg_ctl" -D "$WORK/data" -o "-p $PORT -k $WORK -c listen_addresses=''" -l "$WORK/log" start -w >/dev/null || { cat "$WORK/log"; exit 1; }
PSQL=("$PG_BIN/psql" -h "$WORK" -p "$PORT" -U fixture -X -q -v ON_ERROR_STOP=1)

OA=aaaaaaaa-0000-0000-0000-000000000001; OB=bbbbbbbb-0000-0000-0000-000000000002
OFFICE_A=a0000000-0000-0000-0000-00000000000f; CREW_A=a0000000-0000-0000-0000-0000000000c1
OWNER_B=b0000000-0000-0000-0000-00000000000b; BOTH=ab000000-0000-0000-0000-0000000000ab
WO_A=aaaa0000-0000-0000-0000-000000000ade; WO_B=bbbb0000-0000-0000-0000-000000000bde

load() {
  DB="$1"
  "${PSQL[@]}" -d postgres -c "create database $DB" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$MIRROR" >/dev/null || exit 1
  "${PSQL[@]}" -d "$DB" >/dev/null <<SQL || exit 1
create table public.organizations (id uuid primary key);
insert into public.organizations values ('$OA'), ('$OB');
insert into public.org_members values
  ('$OA','$OFFICE_A','office','{"view_master_work_order":true,"view_field":true}'),
  ('$OA','$CREW_A','field','{"view_master_work_order":false,"view_field":true}'),
  ('$OB','$OWNER_B','owner','{}'),
  ('$OA','$BOTH','field','{"view_master_work_order":false}'),
  ('$OB','$BOTH','field','{"view_master_work_order":false}');
insert into public.work_orders values ('$WO_A','$OA','trade'), ('$WO_B','$OB','trade');
SQL
  "${PSQL[@]}" -d "$DB" -f "$2" >/dev/null || { echo "proposal failed to load: $2"; exit 1; }
  # one event per org, written as the owner of the table, so reads have something to refuse
  "${PSQL[@]}" -d "$DB" -c "insert into public.field_events (org_id, actor_id, event, work_order_id) values ('$OA','$CREW_A','work_order_opened','$WO_A'), ('$OB','$OWNER_B','work_order_opened','$WO_B')" >/dev/null || exit 1
}
as() { # who sql  -> value or ERR:<message>
  local who="$1" role=authenticated claims=""
  case "$who" in anon) role=anon;; nobody) ;; *) claims="set local request.jwt.claims = '{\"sub\":\"$who\",\"role\":\"authenticated\"}';";; esac
  local out; out=$("${PSQL[@]}" -d "$DB" -t -A -c "begin; $claims set local role $role; $2; rollback;" 2>&1)
  if [ $? -ne 0 ]; then echo "ERR:$(echo "$out" | grep -o 'ERROR:.*' | head -1 | sed -E 's/^ERROR: +//' | cut -c1-70)"; else echo "$out" | tail -1; fi   # the LAST statement's value
}
rec() { as "$1" "select public.record_field_event($2)"; }
RESULTS=""
check() { local v=FAIL; case "$3" in ERR:*) [[ "$4" == "$3"* ]] && v=PASS;; *) [ "$3" = "$4" ] && v=PASS;; esac
  printf '%-15s %-4s %-62s expected=%-34s got=%s\n' "$1" "$v" "$2" "$3" "$4"; RESULTS+="$1 $v"$'\n'; }
suite() { local s="$1"
  check "$s" "F1 crew records an open on their org's work order" "1" "$(rec "$CREW_A" "'$OA','work_order_opened','$WO_A'")"
  check "$s" "F2 crew cannot record into another org"             "ERR:not a member" "$(rec "$CREW_A" "'$OB','work_order_opened','$WO_B'")"
  check "$s" "F3 work order must belong to the named org"         "ERR:that work order" "$(rec "$OFFICE_A" "'$OA','work_order_opened','$WO_B'")"
  check "$s" "F4 signed_in writes one row per org of the person"  "2" "$(rec "$BOTH" "null,'signed_in'")"
  check "$s" "F5 no identity records nothing"                     "ERR:not signed in" "$(rec nobody "'$OA','work_order_opened','$WO_A'")"
  check "$s" "F6 anon cannot call the function"                   "ERR:permission denied for function record_field_event" "$(rec anon "'$OA','work_order_opened','$WO_A'")"
  check "$s" "F7 direct INSERT refused (writes go through the RPC)" "ERR:permission denied for table field_events" "$(as "$OFFICE_A" "insert into public.field_events (org_id, actor_id, event) values ('$OA','$OFFICE_A','signed_in')")"
  check "$s" "F8 UPDATE refused (append-only)"                    "ERR:permission denied for table field_events" "$(as "$OFFICE_A" "update public.field_events set event = 'signed_in'")"
  check "$s" "F9 DELETE refused (append-only)"                    "ERR:permission denied for table field_events" "$(as "$OFFICE_A" "delete from public.field_events")"
  check "$s" "F10 a price cannot enter as an outcome"             "ERR:new row for relation \"field_events\" violates check" "$(rec "$OFFICE_A" "'$OA','check_in_failed','$WO_A',null,'\$1,234.00'")"
  check "$s" "F11 a filename cannot enter as a subject"           "ERR:new row for relation \"field_events\" violates check" "$(rec "$OFFICE_A" "'$OA','file_opened','$WO_A','Smith roof.pdf'")"
  check "$s" "F12 an unknown event code is refused"               "ERR:new row for relation \"field_events\" violates check" "$(rec "$OFFICE_A" "'$OA','customer_called_jane'")"
  check "$s" "F13 office A reads A's event, not B's"               "$OA" "$(as "$OFFICE_A" "select string_agg(org_id::text, ',') from public.field_events")"
  check "$s" "F14 owner B reads B's event, not A's"               "$OB" "$(as "$OWNER_B" "select string_agg(org_id::text, ',') from public.field_events")"
  check "$s" "F15b crew reads no telemetry"                       "0" "$(as "$CREW_A" "select count(*) from public.field_events")"
  check "$s" "F13b a timing value records"                        "1" "$(rec "$OFFICE_A" "'$OA','page_ready','$WO_A',null,'ok',1830")"
  check "$s" "F15 anon reads nothing"                             "ERR:permission denied for table field_events" "$(as anon "select count(*) from public.field_events")"
  check "$s" "F16 no column can hold free text"                   "0" "$(as nobody "select count(*) from information_schema.columns c where c.table_schema='public' and c.table_name='field_events' and (c.data_type in ('json','jsonb') or (c.data_type in ('text','character varying') and not exists (select 1 from pg_constraint k join pg_attribute a on a.attrelid=k.conrelid and a.attnum = any(k.conkey) where k.conrelid='public.field_events'::regclass and k.contype='c' and a.attname=c.column_name)))")"
}
echo "== proposal =="; load proposal "$PROPOSAL"; suite proposal
echo "== mutant-membership: org membership check removed =="
perl -0pe "s/  if not coalesce\(p_org_id in \(select public.my_org_ids\(\)\), false\) then\n    raise exception 'not a member of that workspace';\n  end if;\n//" "$PROPOSAL" > "$WORK/m1.sql"
grep -c "not a member of that workspace" "$WORK/m1.sql" | xargs echo "  (membership checks left in mutant, expect 0:"; echo "  )"
load m_membership "$WORK/m1.sql"; suite mutant-membership
echo "== mutant-freetext: a jsonb meta column added =="
sed 's/^  occurred_at     timestamptz not null default now()$/  occurred_at     timestamptz not null default now(),\n  meta            jsonb null/' "$PROPOSAL" > "$WORK/m2.sql"
grep -c "meta            jsonb" "$WORK/m2.sql" | xargs echo "  (meta columns in mutant, expect 1:"; echo "  )"
load m_freetext "$WORK/m2.sql"; suite mutant-freetext
fail() { echo "$RESULTS" | grep -c "^$1 FAIL"; }
echo "------------------------------------------------------------------------"
echo "proposal: $(fail proposal) fail · mutant-membership: $(fail mutant-membership) fail · mutant-freetext: $(fail mutant-freetext) fail"
if [ "$(fail proposal)" -eq 0 ] && [ "$(fail mutant-membership)" -gt 0 ] && [ "$(fail mutant-freetext)" -gt 0 ]; then echo "PROVED"; exit 0; fi
echo "NOT PROVED"; exit 1
