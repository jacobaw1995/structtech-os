# Pilot readiness — the log of readings

Track X. Started 2026-09-25 (America/New_York), because the 2026-09-25 directive asked for each item as
MOVED or NOT MOVED **since its last reading, with the date of that reading** — and the readings existed only
in end-of-day reports, which no later session can read. That is the same failure `docs/GATES.md` names for
dates: a reading nobody can retrieve cannot be contradicted. One line per item per reading, appended.

Readings come from `node scripts/pilot/pilot-readiness.mjs` (read-only; exit 0 ready / 1 not ready / 2
undetermined).

| Item | 2026-09-16 (first run) | 2026-09-18 | 2026-09-23 | 2026-09-25 | 2026-09-27 | 2026-09-28 | Moved? |
|---|---|---|---|---|---|---|---|
| R1 production answers | PASS | PASS | PASS `a04a42b` | PASS `d40440e` | PASS `5d01b86` | PASS `5d01b86` | **MOVED** — redeployed again |
| R2 `ORG_FILES_ENABLED` in Vercel Production | FAIL absent | FAIL | FAIL | FAIL | **FAIL absent** | **FAIL absent** | NOT MOVED, **12 days** |
| R3 pilot crew named | FAIL no config | FAIL | FAIL | FAIL | **FAIL no config** | **FAIL no config** | NOT MOVED, **12 days** |
| R4 crew have accounts / have signed in | *(never ran)* | *(never ran)* | *(never ran)* | *(never ran)* | **UNDETERMINED, now visible** | UNDETERMINED | **MOVED — it is now reported** |
| R5 crew see a job | *(never ran)* | *(never ran)* | *(never ran)* | *(never ran)* | **UNDETERMINED, now visible** | UNDETERMINED | **MOVED — it is now reported** |
| R6 crew cannot reach a master | *(never ran)* | *(never ran)* | *(never ran)* | *(never ran)* | **UNDETERMINED, now visible** | UNDETERMINED | **MOVED — it is now reported** |
| R7 crew see no estimate | *(never ran)* | *(never ran)* | *(never ran)* | *(never ran)* | **UNDETERMINED, now visible** | UNDETERMINED | **MOVED — it is now reported** |
| R8 crew can open office files | *(never ran)* | *(never ran)* | *(never ran)* | *(never ran)* | **UNDETERMINED, now visible** | UNDETERMINED | **MOVED — it is now reported** |
| R9 office uploaded roof data | FAIL 0 objects | FAIL 0 | FAIL 0 | FAIL 0 | **FAIL 0** | **FAIL 0** | NOT MOVED — run 1 did **not** move it |
| R10 logs outlive the day | FAIL Hobby | FAIL Hobby | FAIL Hobby | FAIL Hobby | **FAIL Hobby** | **FAIL Hobby** | NOT MOVED, 12 days |
| R11 field events recorded | (not yet a check) | PASS | PASS | PASS | **PASS** | **PASS** | NOT MOVED since it passed |

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


---

# 2026-09-28 — THE PILOT MOVED, AND FIVE ITEMS CHANGED MEANING

**Decision of record (Jacob, 2026-09-28): the pilot moves from 2026-10-07 to approximately 2026-10-19**, to
build the full job scope sheet first. Recorded as a cost.

**Nothing in `pilot-readiness.mjs` mentions a date.** Every check reads state, so the run is byte-identical
either side of the slip and the summary line is unchanged. **That is exactly the drift risk:** a report that
cannot notice the goalposts moved will keep printing the same verdict against a different question. The five
below are the items whose MEANING changed, written down so the re-baselining is not silent.

| Item | Meaning on 2026-10-07 | Meaning on ~2026-10-19 |
|---|---|---|
| **R2 / R8 / R9** file layer | a pilot-day prerequisite, 9 days out | **EARLIER, not later.** The scope sheet's §5 and §6 carry photo references, and R4 of `docs/SCOPE_SHEET_SPEC.md` gives an *internal* photo "different standing" from an external one. The internal path is `ORG_FILES_ENABLED`, which is off. It is now a prerequisite of the thing being built **now**, not of the pilot |
| **R3** crew named | 9 days of slack on an item stalled 12 days | 21 days of slack on the same stalled item. Slack on something that has not moved in twelve days is how a decision becomes a drift |
| **R4** crew signed in | all-time check; crew last signed in 2026-09-20, 17 days before | **The check cannot see this.** R4 asks "ever", so it answers PASS at 17 days and PASS at 29 days. A check whose answer cannot change with time cannot detect staleness, and the slip is a change in time |
| **R5** crew see a job | the run-1 schedule block (2026-09-29 → 09-30) was already dead by pilot day — 7 days stale | 19 days stale. Measured as the crew: **0 jobs on both dates.** Also note R5 and the screen disagree by construction — R5 counts RLS-reachable trades (**5**), `fetch_field_jobs` counts blocks with `end_date >= today` (**0**) |
| **R10** log retention | 1 hour of runtime logs on pilot day | unchanged in kind, but **12 more days** of scope-sheet building and further golden-path runs whose runtime evidence evaporates hourly |

**R6 and R7 do not change meaning — they are structural** — but they are point-in-time facts with a shelf
life, and twelve extra days is twelve more days of migrations that could regress them. Re-measured today
after `20260927152418_one_name_per_person` and `20260927153148_class_b_provenance`: **still 0 masters and 0
estimates reachable as the crew.**

## Rot checks, 2026-09-28 — what was proved before and is still true

Run because the slip means proved things sit unused for twelve more days.

| Proved | When | Still true? |
|---|---|---|
| No accidental function overloads (rule 1) | — | **YES** — 0 overloaded names in `public`, across the whole schema. Positive control: same query shape against `pg_catalog` returns `max=22, min=22, in_range=16` |
| `org-files` storage policies, 4/4 against the live Storage API | 2026-09-16 | **YES** — all three `org-files` policies present (`read`, `insert`, `delete`), helper `can_reach_work_order_files(uuid)` intact |
| House grant standard (rule 8 amendment) | 2026-09-14 | **YES** — of the 7 newest tables, `authenticated` holds no TRUNCATE and `anon` holds nothing |
| A4.8 adoption calibration | 2026-09-23 | **YES** — 11 of 11 counters FIRED |
| Crew isolation R6/R7 | 2026-09-27 | **YES** — re-measured after two migrations |

**One caution about the calibration output, recorded because it misled me for a minute.** `--calibrate`
prints an INSTRUMENT STATE block reading "8 of 8 event kinds" — that is the **seeded fixture**, not
production. Production's live reading for 2026-09-27 is **4 of 8**: `signed_in`, `work_order_opened`,
`packet_opened`, `page_ready`. The same function printing two different databases' states is a trap worth
naming rather than fixing quietly.

**And the live reading of run 1 says something the row counts do not.** The events on 2026-09-27 were
produced by `09a25143` — **Jacob's own account, the tenant owner** — and the funnel reads **`0 of 1 crew
signed in`**. The crew account has not signed in since 2026-09-20. Run 1 drove eleven steps; **it did not
drive the crew screen as a crew member**, which is the one thing rule 17 says the field surface is accepted
on.
