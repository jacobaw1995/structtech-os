# Pilot readiness — the log of readings

Track X. Started 2026-09-25 (America/New_York), because the 2026-09-25 directive asked for each item as
MOVED or NOT MOVED **since its last reading, with the date of that reading** — and the readings existed only
in end-of-day reports, which no later session can read. That is the same failure `docs/GATES.md` names for
dates: a reading nobody can retrieve cannot be contradicted. One line per item per reading, appended.

Readings are produced by `node scripts/pilot/pilot-readiness.mjs` (read-only; exit 0 ready / 1 not ready /
2 undetermined). **R4–R8 do not appear below because they have never run**: each is asked *as a named crew
member*, and R3 — nobody named — short-circuits them. Six of the eleven checks are unexercised, which is not
the same as passing.

| Item | 2026-09-16 (first run) | 2026-09-18 | 2026-09-23 | 2026-09-25 | Moved? |
|---|---|---|---|---|---|
| R1 production answers | PASS | PASS | PASS `a04a42b` | PASS `d40440e` | **MOVED** — production redeployed |
| R2 `ORG_FILES_ENABLED` in Vercel Production | FAIL absent | FAIL | FAIL | FAIL absent | NOT MOVED, 9 days |
| R3 pilot crew named | FAIL no config | FAIL | FAIL | FAIL no config | NOT MOVED, 9 days |
| R9 office uploaded roof data | FAIL 0 objects | FAIL 0 | FAIL 0 | FAIL 0 | NOT MOVED, 9 days |
| R10 logs outlive the day | FAIL Hobby | FAIL Hobby | FAIL Hobby | FAIL Hobby | NOT MOVED, 9 days |
| R11 field events recorded | (not yet a check) | PASS | PASS | PASS | NOT MOVED since it passed |
| BMR crew members (`role=field`) | — | — | **0** | **0** | NOT MOVED |
| `crew_memberships` rows, all orgs | — | — | — | **0** | first reading |

R2's four-in-a-row is the one to read twice. It is not a check that keeps failing for a new reason each
time; it is one switch nobody has flipped, and it has been the same switch since the storage policies were
proved against the live Storage API on 2026-09-16.
