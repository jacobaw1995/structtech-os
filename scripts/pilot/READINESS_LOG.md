# Pilot readiness — the log of readings

Track X. Started 2026-09-25 (America/New_York), because the 2026-09-25 directive asked for each item as
MOVED or NOT MOVED **since its last reading, with the date of that reading** — and the readings existed only
in end-of-day reports, which no later session can read. That is the same failure `docs/GATES.md` names for
dates: a reading nobody can retrieve cannot be contradicted. One line per item per reading, appended.

Readings come from `node scripts/pilot/pilot-readiness.mjs` (read-only; exit 0 ready / 1 not ready / 2
undetermined).

| Item | 2026-09-16 (first run) | 2026-09-18 | 2026-09-23 | 2026-09-25 | 2026-09-27 | Moved? |
|---|---|---|---|---|---|---|
| R1 production answers | PASS | PASS | PASS `a04a42b` | PASS `d40440e` | PASS `5d01b86` | **MOVED** — redeployed again |
| R2 `ORG_FILES_ENABLED` in Vercel Production | FAIL absent | FAIL | FAIL | FAIL | **FAIL absent** | NOT MOVED, **11 days** |
| R3 pilot crew named | FAIL no config | FAIL | FAIL | FAIL | **FAIL no config** | NOT MOVED, **11 days** |
| R4 crew have accounts / have signed in | *(never ran)* | *(never ran)* | *(never ran)* | *(never ran)* | **UNDETERMINED, now visible** | **MOVED — it is now reported** |
| R5 crew see a job | *(never ran)* | *(never ran)* | *(never ran)* | *(never ran)* | **UNDETERMINED, now visible** | **MOVED — it is now reported** |
| R6 crew cannot reach a master | *(never ran)* | *(never ran)* | *(never ran)* | *(never ran)* | **UNDETERMINED, now visible** | **MOVED — it is now reported** |
| R7 crew see no estimate | *(never ran)* | *(never ran)* | *(never ran)* | *(never ran)* | **UNDETERMINED, now visible** | **MOVED — it is now reported** |
| R8 crew can open office files | *(never ran)* | *(never ran)* | *(never ran)* | *(never ran)* | **UNDETERMINED, now visible** | **MOVED — it is now reported** |
| R9 office uploaded roof data | FAIL 0 objects | FAIL 0 | FAIL 0 | FAIL 0 | **FAIL 0** | NOT MOVED — run 1 did **not** move it |
| R10 logs outlive the day | FAIL Hobby | FAIL Hobby | FAIL Hobby | FAIL Hobby | **FAIL Hobby** | NOT MOVED, 11 days |
| R11 field events recorded | (not yet a check) | PASS | PASS | PASS | **PASS** | NOT MOVED since it passed |

**Summary line, 2026-09-27: `ANSWERED 6 of 11 checks; 5 UNANSWERED: R4, R5, R6, R7, R8` · `NOT READY: 4
FAIL, 5 UNDETERMINED, 2 PASS — of 11`.** Before today it read `NOT READY: 4 FAIL, 0 UNDETERMINED, 2 PASS`.

## What changed in the instrument today, and why it needed changing

**R4–R8 were not failing. They did not exist.** They are asked *as a named crew member*; R3 names nobody,
so the loop that records them never ran, nothing was recorded, and the summary counted six items as if six
were all there were. Eleven days of NOT READY were reported that way, and the five missing were the only
ones that ask what a crew member **can actually reach** — the rest ask about configuration.

They now record UNDETERMINED with the reason, per this file's own rule that a check which cannot run is
UNDETERMINED and never PASS, and the summary states its denominator.

## Positive control, 2026-09-27 — the five can fire (rule 20)

Recording UNDETERMINED is worth nothing if the checks are broken underneath. Run against the **synthetic
tenant and its `field` member** through `PILOT_CONFIG` (a control path, never the repo's config, and the
synthetic crew is **not** named as pilot crew):

```
PASS R4.1 signed in at least once
PASS R5.1 5 live trade work order(s) visible to them
PASS R6.1 cannot reach a master work order — 0 visible
PASS R7.1 sees no estimate (no $ in the field) — 0 visible
FAIL R8.1 can open roof data / photos — 0 file(s) visible to them
ANSWERED 11 of 11 checks
```

**All five executed and produced facts.** R8.1's FAIL is not the crew being blocked: R9 reads 0 objects in
the whole bucket, so there is nothing to see. R9 exists to tell those two apart, and here it does.

**This is measured at the data layer** — asked as that user through live RLS — **not on the rendered
screen** (§7.1 rule 17). R6 and R7 are the strongest results: as a real `field` member, 0 masters and 0
estimates are reachable.

**And R5's 5 is not the number on the crew's screen.** R5 counts trade work orders *reachable through RLS*;
the screen calls `fetch_field_jobs`, which returns only blocks with `end_date >= today` — **1** today. The
two answer different questions and will disagree whenever work is scheduled or expired.
