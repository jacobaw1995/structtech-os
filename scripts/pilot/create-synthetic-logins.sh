#!/usr/bin/env bash
# Creates the two synthetic logins for "ZZ SYNTHETIC Field Test" (e0851ad8-…) — one crew, one office — and
# writes their credentials to the Track X and Track U worktrees. PRINTS NO SECRET: the service-role key and
# both passwords live only in this process, 0600 temp files it deletes, and the two gitignored files below.
#
#   X: /Users/jacobwalker/Coding/structtech-os-X/.env.proof.local
#        PROOF_ORG_ID · PROOF_TRADE_WORK_ORDER_ID · PROOF_CREW_EMAIL · PROOF_CREW_PASSWORD
#        PROOF_OFFICE_EMAIL · PROOF_OFFICE_PASSWORD      (what scripts/storage/org-files-live-proof.mjs reads)
#   U: /Users/jacobwalker/Coding/structtech-os-U/.env.proof.local
#        PROOF_CREW_EMAIL · PROOF_CREW_PASSWORD · FIELD_TEST_EMAIL · FIELD_TEST_PASSWORD   (crew only)
#
# THE KEY comes from SUPABASE_SERVICE_ROLE_KEY in the environment, or from that line in
# /Users/jacobwalker/Coding/structtech-os/.env.local. It does NOT come from the Supabase CLI: on 2026-09-18
# the CLI was logged in to an account that is not a member of the org owning this project, and refused (403).
#
# Addresses are on the reserved .invalid TLD (RFC 2606): they cannot resolve and cannot receive mail.
# Memberships are attached afterwards by Track S, by email (not a secret) — this script creates logins only.
#
# EVERY FAILURE IS ONE NAMED SENTENCE AND A NON-ZERO EXIT. No external command's output is used before its exit
# status and HTTP status have been checked. Exit 2 = refused before anything was created; 1 = failed part-way
# (the sentence says what exists).
set -uo pipefail

REF=ejlhrykcdfcyeooooodx
URL="https://$REF.supabase.co"
ORG_ID=e0851ad8-35d6-4e17-b267-6cd35cb6f713
TRADE_WO_ID=6af911f6-5c60-4041-9a4f-582f5f08434e
CREW_EMAIL="proof-crew@zz-synthetic-field-test.invalid"
OFFICE_EMAIL="proof-office@zz-synthetic-field-test.invalid"
KEY_FILE=/Users/jacobwalker/Coding/structtech-os/.env.local
X_FILE=/Users/jacobwalker/Coding/structtech-os-X/.env.proof.local
U_FILE=/Users/jacobwalker/Coding/structtech-os-U/.env.proof.local

fail() { echo "STOPPED: $2" >&2; exit "$1"; }

for tool in curl python3 openssl git; do
  command -v "$tool" >/dev/null 2>&1 || fail 2 "$tool is not installed, and this script needs it."
done

umask 077
TMP=$(mktemp -d) || fail 2 "could not create a private temp directory."
trap 'rm -rf "$TMP"' EXIT

# ---- refuse to overwrite existing credentials ------------------------------------------------------------
for f in "$X_FILE" "$U_FILE"; do
  [ -d "$(dirname "$f")" ] || fail 2 "the worktree $(dirname "$f") does not exist."
  if [ -e "$f" ] && grep -q '^PROOF_CREW_PASSWORD=' "$f"; then
    fail 2 "$f already holds PROOF_CREW_PASSWORD — the logins were created before; nothing was changed."
  fi
done

# ---- the key: environment first, then the named file. Never printed. -------------------------------------
KEY="${SUPABASE_SERVICE_ROLE_KEY:-}"
if [ -z "$KEY" ]; then
  [ -r "$KEY_FILE" ] || fail 2 "SUPABASE_SERVICE_ROLE_KEY is not set and $KEY_FILE cannot be read."
  KEY=$(sed -n 's/^[[:space:]]*SUPABASE_SERVICE_ROLE_KEY[[:space:]]*=[[:space:]]*//p' "$KEY_FILE" | tail -1 | tr -d '"'"'"' \r')
  [ -n "$KEY" ] || fail 2 "SUPABASE_SERVICE_ROLE_KEY is not set, and $KEY_FILE has no SUPABASE_SERVICE_ROLE_KEY line."
fi
case "$KEY" in
  eyJ*.*.*|sb_secret_*) ;;
  *) fail 2 "the SUPABASE_SERVICE_ROLE_KEY found does not look like a service-role or secret key (wrong value pasted?)." ;;
esac

# Headers go through a 0600 file so the key never appears in a process listing.
{ echo "apikey: $KEY"
  case "$KEY" in eyJ*) echo "Authorization: Bearer $KEY";; esac
  echo "Content-Type: application/json"; } > "$TMP/headers"

# call METHOD PATH [BODYFILE] → sets HTTP (status code) and leaves the body in $TMP/out. Never exits on its own.
call() {
  local args=(-sS -o "$TMP/out" -w '%{http_code}' -X "$1" "$URL$2" -H @"$TMP/headers")
  [ $# -ge 3 ] && args+=(--data-binary @"$3")
  HTTP=$(curl "${args[@]}" 2>"$TMP/curl.err"); local rc=$?
  [ $rc -eq 0 ] || HTTP="curl-$rc"
}
# field NAME → reads one key from the JSON in $TMP/out; prints nothing (and returns 1) if it is not there.
field() {
  python3 - "$1" "$TMP/out" <<'PY' 2>/dev/null
import json, sys
try:
    v = json.load(open(sys.argv[2])).get(sys.argv[1])
except Exception:
    sys.exit(1)
if not v: sys.exit(1)
print(v)
PY
}

# ---- prove the key works, harmlessly, before creating anything -------------------------------------------
call GET "/auth/v1/admin/users?per_page=1"
case "$HTTP" in
  200) ;;
  curl-*) fail 2 "could not reach $URL (curl exit ${HTTP#curl-}) — check the network; nothing was created." ;;
  401|403) fail 2 "the project refused the key (HTTP $HTTP) — it is not this project's service-role/secret key; nothing was created." ;;
  *) fail 2 "the auth admin API answered HTTP $HTTP to a read — nothing was created." ;;
esac

# ---- passwords, generated here and never printed ---------------------------------------------------------
gen() { local p; p=$(openssl rand -base64 48 2>/dev/null | tr -d '/+=\n' | cut -c1-32); [ ${#p} -eq 32 ] && echo "$p"; }
CREW_PW=$(gen) || true;   [ -n "$CREW_PW" ]   || fail 2 "openssl could not generate a password; nothing was created."
OFFICE_PW=$(gen) || true; [ -n "$OFFICE_PW" ] || fail 2 "openssl could not generate a password; nothing was created."

# create EMAIL PASSWORD → prints the new user's id; on failure prints one named sentence and returns 1.
create() {
  EMAIL="$1" PW="$2" python3 -c 'import json,os; print(json.dumps({"email":os.environ["EMAIL"],"password":os.environ["PW"],"email_confirm":True}))' \
    > "$TMP/body" 2>/dev/null || { echo "could not build the request for $1"; return 1; }
  call POST "/auth/v1/admin/users" "$TMP/body"
  rm -f "$TMP/body"
  case "$HTTP" in
    200|201) local id; id=$(field id) && { echo "$id"; return 0; }
             echo "the API accepted $1 but returned no user id"; return 1 ;;
    422) echo "$1 already exists — delete it in the dashboard (Authentication → Users) or run the teardown, then re-run"; return 1 ;;
    curl-*) echo "could not reach the API while creating $1"; return 1 ;;
    *) local why; why=$(field msg || field message || field error_code || echo "no reason given")
       echo "creating $1 was refused (HTTP $HTTP: $why)"; return 1 ;;
  esac
}

CREW_ID=$(create "$CREW_EMAIL" "$CREW_PW") || fail 2 "$CREW_ID; nothing was created."
echo "created crew login   $CREW_EMAIL  ($CREW_ID)"
OFFICE_ID=$(create "$OFFICE_EMAIL" "$OFFICE_PW") || fail 1 "$OFFICE_ID. The crew login $CREW_EMAIL WAS created; no credential file was written."
echo "created office login $OFFICE_EMAIL ($OFFICE_ID)"

# ---- write the two files, then prove they are gitignored — by name only -----------------------------------
{ echo "PROOF_ORG_ID=$ORG_ID"; echo "PROOF_TRADE_WORK_ORDER_ID=$TRADE_WO_ID"
  echo "PROOF_CREW_EMAIL=$CREW_EMAIL"; echo "PROOF_CREW_PASSWORD=$CREW_PW"
  echo "PROOF_OFFICE_EMAIL=$OFFICE_EMAIL"; echo "PROOF_OFFICE_PASSWORD=$OFFICE_PW"; } >> "$X_FILE" \
  || fail 1 "both logins exist but $X_FILE could not be written."
{ echo "PROOF_CREW_EMAIL=$CREW_EMAIL"; echo "PROOF_CREW_PASSWORD=$CREW_PW"
  echo "FIELD_TEST_EMAIL=$CREW_EMAIL"; echo "FIELD_TEST_PASSWORD=$CREW_PW"; } >> "$U_FILE" \
  || fail 1 "both logins exist and $X_FILE was written, but $U_FILE could not be."
unset KEY CREW_PW OFFICE_PW

for f in "$X_FILE" "$U_FILE"; do
  echo "$f: $(grep -o '^[A-Z_]*=' "$f" | tr -d '=' | tr '\n' ' ')"
  if git -C "$(dirname "$f")" check-ignore -q "$f"; then echo "  gitignored: yes"; else echo "  gitignored: NO — do not commit this file"; fi
done
echo "DONE. Next: Track S attaches $CREW_EMAIL as field and $OFFICE_EMAIL as office in the synthetic org."
