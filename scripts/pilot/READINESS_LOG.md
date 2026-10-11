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

---

# 2026-09-28, EVENING — SECOND READING THE SAME DAY, AND THE PILOT DATE IS CONTESTED

**Verify the clock before the date.** `TZ=America/New_York date` reads **Mon Sep 28 22:32 EDT 2026**.
It is 02:32 UTC on the 29th, so anything reading a UTC clock calls today Tuesday. It is Monday. This is
the trap CLAUDE.md names, and it caught a directive today.

## THE PILOT DATE — the repo and the directive disagree, and the repo was verified twice

| Source | Pilot day 1 | Working days from today |
|---|---|---|
| `docs/GATES.md`, re-dated **twice** on 2026-09-28, "checked, not accepted" by Track S, every day-of-week re-derived | **Mon Oct 26** | **21** |
| Today's directive | Wed Oct 7 | 8 |

**Not reconciled here, because it is not mine to reconcile.** `docs/GATES.md` is Track S's file and
§7.1 says dates get contradicted the same way counts do. Recorded so the contradiction is visible in
the one file that is supposed to make re-baselining falsifiable. **The directive itself said to
re-read this log rather than trust its dates**, so the readings below are dated, not counted down.

Note the directive's characterisation is also contradicted: the gates were re-dated twice in one day,
but they did **not** return to where they started — Oct 7 → ~Oct 19 → **Oct 26**, each move outward.

## Reading — 2026-09-28 evening. NOTHING MOVED since the morning reading.

`ANSWERED 6 of 11 checks; 5 UNANSWERED: R4, R5, R6, R7, R8` · `NOT READY: 4 FAIL, 5 UNDETERMINED, 2
PASS — of 11`. R1 `PASS 5d01b86` · R2 **FAIL absent, 6th reading** · R3 FAIL · R9 FAIL 0 · R10 FAIL
Hobby · R11 PASS. Control re-run: R4–R8 all execute, 4 PASS, R8.1 FAIL on 0 files (which is R9, which
is R2).

**R2 is now the whole of the remaining file-layer story.** It blocks R8 and R9, it is three minutes of
work (`JACOBS_LIST.md` #9), and it has been absent on 09-16, 09-23, 09-25, 09-27 and twice on 09-28.

## A DEFECT IN MY OWN INSTRUMENT, FOUND AND FIXED TODAY

**The UNEXERCISED marker said "recorded here" and measured "recorded anywhere".** Two questions, one
query. They gave the same answer for a month and diverged for the first time on 2026-09-27, when
golden-path run 1 wrote `work_order_opened`, `packet_opened` and `page_ready` **in the synthetic
tenant** — which silently removed the marker from **Brothers Metal Roofing's** report, where those
kinds have still never fired.

**Measured, not reasoned.** BMR's report printed `0 of 0 crew opened a work order` with **no marker**,
reading as a measurement, on the strength of activity in a disposable test tenant.

Counters are now graded in three states: **fired here** (a real measurement) · **UNEXERCISED HERE**
(the path works, nothing in this tenant has used it) · **UNEXERCISED ANYWHERE** (measures nothing).
INSTRUMENT STATE now prints both scopes — today, BMR reads `ANYWHERE 4 of 8`, `IN THIS TENANT 1 of 8`.

**Shown the defect before being trusted (rules 20 and 22).** A second, quiet tenant is seeded in the
fixture so the grading has something to grade, and four regression checks were added. Reverting
`everSeenInOrg` to the old global query — the mutation verified present in the file that actually runs
— makes **3 of the 4 fail**. The fourth passes under both implementations by design: it guards against
*over*-marking an exercised stage, so it is not a discriminator and is not counted as one.
Calibration restored: **15 of 15 FIRED.**

---

# 2026-09-29 — C0 CLOSED, AND A4.8 GETS ITS THREE MEASURES

## C0 — the gates contradiction is RESOLVED. Entry closed.

**Cause: I merged before the revert landed.** My 2026-09-28 reading was of `6372d7f`, which was the
second re-dating. `9df1c64` reverted it and `be5a698` corrected a label; both were on main by this
morning. Nothing was wrong with the reading — it was of a superseded file.

**Confirmed from the file at `ee3036f`** (GATES.md last touched by `be5a698`), not from a directive:

- **Field pilot day 1: Wed Oct 7.** ✔
- **G11 carries NO DATE in BOTH tables** — table 1 (the gates): `BLOCKED — NO DATE`; table 2 (measured
  against the tracker): `G11 · NO DATE · Stripe billing live`. **The two tables agree.** ✔

**Checked against itself as well as against the directive (§7.1 RULE 21).** All **8 of 8**
day-of-week labels in the file are correct: Oct 6 Tue, Oct 13 Tue, Oct 16 Fri, Oct 24 Sat, Oct 25 Sun,
Oct 29 Thu, Oct 31 Sat, Oct 7 Wed. The file's *"Eight working days from this revert"* is correct **from
the revert** — `9df1c64` was authored Mon 2026-09-28 22:44 EDT, and 09-28→10-07 inclusive is 8 working
days. **From today it is 7.**

**The 2026-09-28 entry above is closed.** The pilot is Wed Oct 7 and the "21 working days" in it is
void.

## C1 — A4.8's three measures now exist, and most of them are UNDEFINED

`opens` · `completionRate` · `timeToComplete` are built, each printing its denominator.

**A RATE WITH A ZERO DENOMINATOR RENDERS `UNDEFINED`, NEVER 0%.** They are different claims about a
roof: 0% says work was assigned and none was done; undefined says none was assigned. The distinction is
enforced in both directions — a real denominator with a zero numerator still renders **0%**, so
"always print UNDEFINED" fails the suite too.

**Calibration 22 of 22 FIRED**, up from 15, including four new zero-denominator checks. **Mutant test
(rules 20, 22):** collapsing `rate()`'s undefined branch to `{pct: 0}` — mutation verified present in
the file that runs — fails exactly the two checks that exist to catch it.

**Two of my own errors, found by running it:** I predicted `time-to-complete` = 55 min (13:05→14:00)
and the correct answer is **660** (03:00→14:00) — the measure takes the *first* open of the day and the
fixture has a deliberate dawn open. The counter was right and the prediction wrong (rule 21), and the
mechanism generalises: a crew member who opens a job at dawn and checks in after lunch scores the whole
morning. And my "renders as undefined" assertion tested `!includes("0%")` against text that
deliberately ends *"Not 0%."* — a test failing on its own explanatory string.

## C2 — what R10 needs

**One line:** R10 needs the Vercel team off **Hobby**; **Pro at $20/user/month** flips it, because
runtime-log retention goes **1 hour → 1 day** (Vercel docs, read 2026-09-29), and the check passes any
plan that is not `hobby`.

**$20 is not the whole of it, in two directions.** *Thin:* 1 day barely outlives a pilot day looked at
the following morning — **Observability Plus** is the 30-day option and is a separate add-on. *Wider:*
Hobby is documented non-commercial/personal-use, so a paid client pilot on it is a **terms** problem as
well as an observability one, and the readiness check does not measure that at all. Nothing was bought.

## C4 — the grace-time test cannot be run by me, AND IT HAS ALREADY HAPPENED ONCE

**Why it cannot be run:** its pass condition is *an email arriving at an address, at a time*. I have no
access to that inbox, no Healthchecks credential (no such variable name exists in either env file), and
changing Period/Grace on a live alerting system is a config change to the thing that pages someone.

**But the item has now been re-measured, without touching anything.** The dead-man ping fires only on a
successful scheduled run (`DEADMAN_PING_URL`, confirmed set as a repo secret). Over the 60 scheduled
runs from 2026-09-18 to 2026-09-29, **one gap exceeded the 8-hour alert threshold** (1h period + 7h
grace):

> **2026-09-28, 06:59:37Z → 22:05:19Z — a 15.1-hour gap. The alert window opened at 14:59Z = 10:59 EDT.**

**And the mechanism is not the obvious one.** There was a failed run at 15:33Z, but the threshold was
crossed **34 minutes before that run even started** — GitHub simply did not run the cron between 06:59Z
and 15:33Z. So the window opened from **schedule drift, not from a detected fault**: if alerting works,
the email said the site was down while the site was fine. That is what a 7-hour grace exists to absorb
and it did not, because 29 of the 31 inter-ping gaps in this window already exceed 4 hours — the
"hourly" cron delivers roughly every 5–6 hours.

**The question for Jacob is now free and specific, and it replaces the test:** *did a Healthchecks
"down" email arrive on Monday 2026-09-28 at about 11:00 EDT?* **Yes** closes §6.9 with a real arrival
time. **No** is the finding the test was meant to produce. **Either way this is delivery-independent —
delivery has been ARMED since 09-19 and is still not alerting.**

---

# 2026-09-30 — §6.9 CLOSED AS A PASS. ALERTING IS PROVED.

**Date verified `Wed Sep 30 20:20:29 EDT 2026`.** Today's directive is headed Thursday 2026-10-01; it is
Wednesday. 20:20 EDT is 00:20 UTC, the same rollover CLAUDE.md names, and the second directive in three
days to carry it.

## §6.9 — PROVED, with the arrival on the record

Open since 2026-09-11. **Closed 2026-09-30 as a PASS.** The test was never run deliberately; the system
ran it on itself and the email exists:

| | |
|---|---|
| **DOWN** | **Mon 28 Sep 2026 10:59:51 -0400** |
| **UP** | **Mon 28 Sep 2026 18:05:35 -0400**, downtime 7h 05m |
| **Destination** | **`jacob@structtek.com`** — *not* the gmail |
| Counter at the two emails | Total pings 70 → 71 since Sep 15 |

**Delivery and alerting are now both PROVED, and they were proved separately.** Delivery ARMED
2026-09-19; alerting by the arrival above.

**THE MAILBOX IS PART OF THE FINDING.** The controller swept the gmail, found nothing, and published a
wrong conclusion from it. The alert went to `jacob@structtek.com`. **A negative result from the wrong
container is not a negative result** — rule 18 (state the axis) in its plainest form, and the axis here
was *which inbox*.

**My 2026-09-29 prediction was right to the minute.** I computed the window opened at 14:59:37Z from
the run history; the DOWN email is stamped 14:59:51Z. **14 seconds.**

## The defect the pass exposes — the alert was CORRECT and the site was FINE

Measured over **156 scheduled runs, 2026-09-03 → 2026-09-30**.

**Gap distribution between successive dead-man pings** (a ping is sent only on a successful scheduled
run):

| Window | n gaps | median | p90 | max | >4h | >8h (current threshold) |
|---|---|---|---|---|---|---|
| **Sep 15 → Sep 30** (the check's lifetime) | **84** | **4.62 h** | **6.27 h** | **15.10 h** | 48 of 84 | **1** |
| Sep 5 → Sep 30 (since the ping step existed) | 145 | 4.14 h | 6.16 h | 15.10 h | 79 of 145 | **3** |

**Alert windows across the whole measured period: 3** — 2026-09-07 (10.2 h), 2026-09-13 (9.6 h),
2026-09-28 (15.1 h). **Only the last fell inside the check's lifetime**, so only one produced an email.
**One alert in the fifteen days the check has existed; three in the twenty-six days the ping has
existed.** That is not a pager anybody has learned to ignore — but it is also one false alarm per two
weeks, and on Oct 7 a false "down" is a phone call during a roof.

**The cause is schedule drift, not a fault.** The threshold was crossed at 14:59Z and the only failing
run that day started at 15:33Z — **34 minutes later**. GitHub simply did not run the cron between
06:59Z and 15:33Z. A monitor advertised as hourly delivers at a **median of 4.62 h**.

**Cross-check, and a correction to my own first pass.** I first compared 85 successful runs (to Sep 30)
against a counter snapshotted on Sep 28 and called the 14-run difference "small deltas". Wrong
comparison. Counted to the moment of each email: **75 and 76 successful runs** against Healthchecks'
**70 and 71**. The residual 5 is exactly the number of successful runs on Sep 15 itself, so a check
created partway through that day explains it precisely — **arithmetically available, not confirmed**,
because I cannot read the creation time.

## What Period and Grace would NOT have alerted — and why I do not recommend them

| Setting | Threshold | Alerts in the window | Worst-case detection delay |
|---|---|---|---|
| Period 1h + Grace 7h (**current**) | 8 h | 1 | 8 h |
| Period 1h + Grace 11h | 12 h | 1 | 12 h |
| Period 1h + Grace 14h | 15 h | 1 | 15 h |
| **Period 1h + Grace 15h** | **16 h** | **0** | **16 h** |

**Grace 15h is the first setting that would have stayed quiet, and it buys 0.90 h of headroom over the
worst observed gap — less than one median drift event (4.62 h).** So the next slightly worse drift
re-alerts, and the price is a **16-hour** worst-case detection delay: a front door that fails at 6 p.m.
is reported at 10 a.m. On a pilot day that is not monitoring.

### RECOMMENDATION: move the ping off GitHub Actions cron. Do not widen the thresholds.

- **Widening — cost:** detection falls to 16 h worst case, it does not actually stop the alarms (0.90 h
  of margin against a 4.62 h median), and the monitor stops being able to tell anyone about Oct 7 on
  Oct 7. It is free and it buys nothing durable.
- **Moving — cost:** one external scheduler that runs when it says it will (a cron-as-a-service hitting
  the same ping URL, or Vercel Cron if the team is on Pro — which R10 wants anyway). Setup is tens of
  minutes, it is a new dependency, and **it is Jacob's to configure, not mine.** In exchange Period 1h
  + Grace 1h becomes honest and detection drops from 8 h to ~2 h.
- The workflow's own comments already reached this conclusion on 2026-09-04: *"if hourly delivers no
  better, the answer is an external scheduler, not a cron."* The data since then says hourly delivers
  **4.62 h**.

## C3 — readiness, re-run whole. NOTHING MOVED.

`ANSWERED 6 of 11 checks; 5 UNANSWERED: R4–R8` · `NOT READY: 4 FAIL, 5 UNDETERMINED, 2 PASS — of 11`.
R1 **PASS `b52c163`** (moved — production redeployed) · R2 FAIL · R3 FAIL · R9 FAIL 0 objects · R10 FAIL
Hobby · R11 PASS. Every item was **run**, not inferred.

**`ORG_FILES_ENABLED`: TENTH READING. Absent in production, preview AND development** — production holds
5 names, preview 2, development 0, and it is in none of them. **First measured 2026-09-16; 14 days open.**

**Crew scoping re-measured, because `20260929153659_crew_scoped_field_jobs` changed `fetch_field_jobs`
and rule 15 says call it rather than read it.** Called as the synthetic `field` member: **1 job on
2026-09-30, 0 on 2026-10-07.** Control R4–R8 all still execute: 4 PASS, R6 and R7 still 0 masters and 0
estimates. `crews` 0, `crew_memberships` 0 — the scoping is built and off, as its commit says.

**R10 — should it be split?** **Yes: a plan check and a terms check.** They have different owners and
different failure modes — retention is an observability number, and Hobby's non-commercial clause
against a paying client is a contractual one that no amount of retention fixes. Left there, as asked.

---

# 2026-10-05 — TWO DAYS OUT. THE FLAG MOVED AND IT IS STILL OFF.

Date verified `Mon Oct  5 14:01:48 EDT 2026`. Last reading 2026-09-30.

## THE FINDING: `ORG_FILES_ENABLED` IS SET, THE FEATURE IS DARK, AND R2 WENT GREEN

**Eleventh reading. It MOVED** — present in production for the first time since 09-16, and production
redeployed 19 h ago at `97fc598`, so the variable is in the running build.

**Its value is not `"true"`.** Asserted without ever printing it: 11 characters after quote-stripping,
**no lowercase letters, and no `true` substring in any casing**. The app tests
`process.env.ORG_FILES_ENABLED === "true"`, so `orgFilesEnabled()` returns **false** and A4.7 is still
off on the crew's job screen.

**And R2 PASSED on it**, because R2 checks names. **A false green is worse than a red:** a red is a
task, a green is a decision to stop looking. For eleven days R2 measured the only thing that had moved,
and the first time it moved, R2 reported success on a feature nobody can use.

**Closed by R2b**, added today: every flag whose app semantics are `=== "true"` has its VALUE verified.
The value is pulled to a temp file, asserted, then overwritten and deleted in a `finally` — including on
the error path, because a secrets file left behind by a crashed check is worse than the bug it hunts.
Only the verdict is reported. **It fires correctly in both directions on real data: `AUTH_EMAIL_ENABLED`
PASSES (it really is `"true"`) and `ORG_FILES_ENABLED` FAILS** — so the check is not merely pessimistic.

> **Jacob — one edit:** set `ORG_FILES_ENABLED` in Vercel → Settings → Environment Variables →
> Production to exactly `true`: four lowercase letters, no quotes, no spaces. Then redeploy. R2b will
> flip to PASS, and it is the check to watch, not R2.

## Reading — 2026-10-05. NOW 12 ITEMS.

`ANSWERED 7 of 12; 5 UNANSWERED: R4–R8` · `NOT READY: 4 FAIL, 5 UNDETERMINED, 3 PASS — of 12`.

| Item | 09-30 | 10-05 | Moved? |
|---|---|---|---|
| R1 | PASS `b52c163` | **PASS `97fc598`** | MOVED — redeployed |
| R2 names | FAIL absent | **PASS** | MOVED — **and it is a false green** |
| **R2b values** | *(did not exist)* | **FAIL** | NEW — the check that tells the truth |
| R3 crew named | FAIL | FAIL | NOT MOVED — needs `pilot.config.json`, Jacob's |
| R4–R8 | UNDETERMINED | UNDETERMINED | NOT MOVED — R3 names nobody |
| R9 office uploads | FAIL 0 | FAIL 0 | NOT MOVED — downstream of R2b |
| R10 retention | FAIL Hobby | **FAIL Hobby** | NOT MOVED — plan re-read today, still Hobby |
| R11 | PASS | PASS | — |

## The other two the controller could not see

**Vercel plan: HOBBY.** Unchanged. R10's retention failure and the separate non-commercial-terms
problem both still stand, and BMR is a paying client.

**The Healthchecks ping STILL RIDES GITHUB ACTIONS CRON.** `cron: '23 * * * *'`, workflow untouched
since 2026-09-13. Re-measured over 177 scheduled runs:

| Window | n gaps | median | p90 | max | >8h |
|---|---|---|---|---|---|
| **Since 09-30** | 23 | **5.61 h** | 6.96 h | **7.37 h** | **0** |
| Check lifetime (Sep 15→now) | 103 | 4.74 h | 6.28 h | 15.10 h | 1 |

**The median has WORSENED, 4.62 h → 5.61 h, and the worst gap since 09-30 is 7.37 h against an 8 h
threshold — 38 minutes of margin.** A false "down" on Wednesday is now a coin-flip away, and it pages a
phone during a roof.

## THE CREW ARRIVED, AND THE PILOT ALREADY HAD ITS FIRST REAL SESSION

**BMR now has 1 `field` member, 1 `crews` row and 1 `crew_memberships` row.** Jacob's Oct 1 item is
done. Two `field` logins now exist in the database where there was one.

**And a real roofer used it on 2026-10-04.** Every funnel stage for BMR that day is a measurement, with
no UNEXERCISED marker anywhere: `signed in 1 of 1` · `opened a work order 1 of 1` · `page became usable
1 of 1` · `recorded something 1 of 1`. Time-to-complete **2 minutes**.

## C3 — THE DEDUP DRIFT, MEASURED. IT IS ZERO, AND THE PREMISE INVERTS.

**`completionRate` does not read `field_events`.** It reads `public.check_ins` with
`count(distinct work_order_id)`. `funnel.recorded` counts distinct ACTOR; `timeToComplete` takes
`min(occurred_at)`. **No counter in the instrument reads a raw `check_in_saved` count**, so a duplicated
event cannot move any of them.

**Proved on seeded behaviour rather than argued:** the fixture now contains a second `check_in_saved`
for the same actor, work order and `subject_ref`, 40 s after the first. Completion rate, `recorded` and
time-to-complete are all unchanged — and a fourth check asserts the duplicate **is** present, so the
three are not vacuous. **Calibration 26 of 26 FIRED.**

**On production data the drift is zero for a second reason, and it is the more interesting one.** The 8
`check_in_saved` events in the database have **8 DISTINCT `subject_ref`s, not one repeated** — all from
the roofer, within 4 seconds on 2026-10-04, before `6a85e6a` wired the idempotency token. They were
eight **separate** check-ins, of which **one survives** (the other seven went with the voided fake-lead
chain). A dedup resend returns the *same* id; these returned eight. **The mechanism the worry describes
has never fired in production: 0 repeated subject_refs out of 8 events.**

**Recommendation: neither fix, for the counters — but record the dedup distinctly anyway, for the
report.** Counting distinct `subject_ref` would change nothing (they are already distinct) and would
silently hide a real retry when one happens. The thing actually worth having on Wednesday is the ability
to tell *"one crew member fighting bad signal"* from *"eight check-ins, seven deleted"* — and today
those two look identical. That is a distinct `outcome` code on the resend, not a change to a counter.
**Not built: C1 and C2 came first, as instructed.**

---

# 2026-10-05, SECOND SESSION — R2b GETS A THIRD VERDICT, BECAUSE MY FIRST RED WAS FALSE

Date verified `Mon Oct  5 17:04:56 EDT 2026`.

## THE CORRECTION, AND IT IS MINE

**This morning I reported `ORG_FILES_ENABLED` as "SET BUT NOT \"true\"" and told Jacob to go and edit
it. That was wrong.** The variable had been typed **Sensitive** in Vercel, which means `vercel env pull`
writes the literal string `[SENSITIVE]` in place of the value. That string is **exactly 11 characters,
has no lowercase letter, and contains no "true" in any casing** — which is precisely the shape I
measured and reported as a wrong value.

**A false red sends a human to a settings page to fix something that is not broken.** Mine did.

**Measured now:** `ORG_FILES_ENABLED` is readable, 4 characters, `=== "true"` → **true**. R2b **PASSES**,
and the feature is live.

## THE THIRD VERDICT

`UNREADABLE`, keyed on `value === '[SENSITIVE]'` — **the literal, not its shape.** Matching on length 11
or "no lowercase" would be matching coincidences of this one placeholder: `DEVELOPMENT` is also 11
uppercase characters and is a genuinely wrong value. Keying on the literal also **fails closed** — if
Vercel ever reworded the placeholder, the check drops into FAIL, which is the safe direction.

Its message names the variable and names the fix, and **the fix is not "edit the value"**: a sensitive
variable's value cannot be read or corrected in place. It must be removed and recreated as a normal
variable, then redeployed. A message saying "wrong value" invites exactly the action that cannot work.

**Precedence:** a genuinely wrong value outranks an unreadable one — a defect in the app beats a gap in
what the check can see.

**And the summary was taught the new verdict in the same change.** `UNREADABLE` now joins `UNDETERMINED`
as *not answered*; otherwise an unreadable check would have counted as ANSWERED, which is the identical
defect fixed on 2026-09-27 when R4–R8 did not run and the last line could not say so. **A new verdict is
not finished until the line that counts verdicts knows it exists.**

**Shown the defect, on real production keys (rule 20), not on a stub:**

| Control | Key | Verdict |
|---|---|---|
| A — genuinely Sensitive | `RESEND_API_KEY` | **UNREADABLE**, and the summary read `6 UNANSWERED: R2b(unreadable), R4…R8` |
| B — readable but not "true" | `EMAIL_FROM` (39 chars) | **FAIL**, not UNREADABLE |

The two branches are distinguished on live data, so the third verdict is not a blanket softening of the
red.

## THE SWEEP — axis stated, and what the axis cannot see

**Axis: source that reads an env value and compares it to an expected string literal.** Containers:
`src/`, `scripts/`, `.github/`, repo root. **Positive control fired** — the sweep found both sites R2b
already knows about before I trusted anything else it said.

**THE AXIS WAS TOO NARROW ON ITS OWN AND I WIDENED IT THREE TIMES.** A `===` sweep cannot see a
presence-only gate, a shell test, or an env read that goes through a helper.

**And the finding that decides all of them: `[SENSITIVE]` NEVER REACHES A RUNTIME.** Vercel's Sensitive
typing restricts *reading the value back*; the deployment still receives the real value — proved by
production being live at `a35b783` with the feature on. So **every site that reads `process.env` in a
deployed runtime is safe**, and the only exposure is tooling that reads a **pulled** file.

| Site | Reads | Would `[SENSITIVE]` be misreported? |
|---|---|---|
| `src/lib/storage/work-order-files-states.ts:109` | runtime env | **No** — real value at runtime |
| `src/lib/auth/reset-states.ts:173` | runtime env | **No** — same |
| `scripts/monitor/frontdoor-monitor.mjs:71` (`MONITOR_SELFTEST === '1'`) | CI/local env | **No** — never pulled from Vercel |
| **`scripts/email/verify-email-send.mjs:92`** | `RESEND_API_KEY` from **`.env.local`** | **YES — and it is the same class of false red.** A placeholder key is a syntactically valid bearer token, so Resend answers 4xx and the script reports **`rejected` — "the request is wrong; retrying won't help"** — when the key is fine |
| `scripts/pilot/db.mjs:20,24` | `SUPABASE_DB_URL` from `.env.local` | **No — fails safe.** The key is not in Vercel at all, so a pull removes it and `dbAvailable()` reports "not available", which the readiness check renders UNDETERMINED |
| `scripts/storage/org-files-live-proof.mjs:32`, `scripts/probe-storage-front-door.mjs:29` | `.env.local` / `.env.proof.local` | **No** — would fail loudly on a malformed URL/key |
| local `npm run dev` | `.env.local` | **No** — crashes on `new URL("[SENSITIVE]")`. Loud, not silent |

**The hazard that makes those reachable at all:** `vercel env pull` **defaults to `.env.local`** and
**overwrites it**. One bare `vercel env pull` would replace the working local file — losing
`SUPABASE_DB_URL`, which is not stored in Vercel — and write `[SENSITIVE]` for the three sensitive keys.
**Reported, not fixed**, per instruction. The cheap guard would be for the scripts that read `.env.local`
to refuse a `[SENSITIVE]` value with the same sentence R2b now uses.

## THE TWO `NEXT_PUBLIC_` KEYS — typed Sensitive, and it buys nothing

`NEXT_PUBLIC_SUPABASE_ANON_KEY`, `NEXT_PUBLIC_SUPABASE_URL` and `RESEND_API_KEY` all pull as
`[SENSITIVE]` today. **The directive's list is exactly right; nothing has changed.**

**Does typing them Sensitive break anything that reads them? No.** Production is live and serving at
`a35b783`; the runtime gets real values, and `NEXT_PUBLIC_` vars are inlined at build time from the real
values, not from a pull.

**Are they secrets? The anon key is designed not to be — RLS is the control, not obscurity. But measured
in this build they are not even shipped:** 0 of 44 client chunks contain either value; 3 of 98 **server**
chunks do. Positive control: 3 of 44 client chunks contain `__next`, so the search works. The reason is
that nothing in a client component imports the browser Supabase client — its only importers are lib
files. **So marking them Sensitive protects values that are currently server-only anyway, at the cost of
making them unreadable to our own tooling.**

**Is any check blind to them? Yes, completely.** R2's `REQUIRED_ENV` is `ORG_FILES_ENABLED`,
`AUTH_EMAIL_ENABLED`, `RESEND_API_KEY`, `EMAIL_FROM`; R2b's flag list is the first two. **Neither
`NEXT_PUBLIC_` key is named by any readiness item** — if one were deleted tomorrow, no check here would
notice, and the first sign would be a production page failing to construct a Supabase client.

**Recommendation, not a change — production env edits are not mine:** recreate the two `NEXT_PUBLIC_`
variables as normal variables (the anon key is public by design and the URL is in every request), leave
`RESEND_API_KEY` Sensitive since it genuinely is a secret and R2b now reports it honestly, and add both
`NEXT_PUBLIC_` names to R2's `REQUIRED_ENV` so their absence is visible.

---

# 2026-10-11 — THE 38 MINUTES WAS A FACT ABOUT EIGHT DAYS IN SEPTEMBER

**Controller ruling, recorded here because this file is where the bad figure
lives: A MARGIN MEASURED ON A CHOSEN WINDOW IS A FACT ABOUT THE WINDOW.**

The line above dated 2026-09-30 reads *"the worst gap since 09-30 is 7.37 h
against an 8 h threshold — 38 minutes of margin."* **Every number in it is
correctly computed and the sentence is false of the instrument.** It is true of
2026-09-30→10-08 and of nothing wider. Quoted in six controller directives.

**The full window, measured 2026-10-11 — and every figure now carries its
container, because that is the only thing that stops this recurring:**

| | over 2026-09-03→2026-10-10, n=188 gaps |
|---|---|
| median | **4.49 h** |
| p90 | **6.33 h** |
| p99 | **14.98 h** |
| **MAX** | **21.71 h** |
| **margin at the MAX vs the 8 h threshold** | **−822 minutes** |
| alert windows (gap > 8 h) | **6** |

**Not 38 minutes of margin. Negative by thirteen and a half hours.**

**And a SEVENTH window is open right now and is not in that six** — a closed gap
needs a later success to measure against, so an ongoing outage is invisible to
the count that is supposed to report outages. Last successful scheduled run
**2026-10-10 03:12 EDT; 22.5 hours ago; threshold breached 14.5 hours ago.** That
is my own outage, still open at the time of writing.

## The source fix

`scripts/pilot/cron-drift-figures.mjs` emits every percentile with its window **on
the same line**, so a quoted line is still true. A header the reader may not copy
is not enough — rule 39 is that the caveat does not travel with the number, so the
container has to be *in* the number. **Paste its output here rather than typing a
median by hand; a hand-typed median is how the 38 minutes got in.**

It lives in `scripts/pilot/`, not `scripts/monitor/`, because it shells out to
`gh` and that directory is asserted to need no external binary — the same rule
that my misplaced file broke on 2026-10-09, applied this time before making the
mistake rather than after.

## Did Healthchecks actually alert? What the instrument says, and what it cannot

**I cannot query Healthchecks.** No API key exists in any env file or in the repo,
and `DEADMAN_PING_URL` is a GitHub secret whose value is unreadable by me and by
any workflow log, by design. That is the missing instrument, named rather than
worked around. **Jacob's mailbox reading is the independent one and should stay
independent.**

**What I can bound from my own data, which is narrower than the question and
more than nothing:**

| window | could it have alerted? |
|---|---|
| 09-07 (10.2 h) · 09-13 (9.6 h) | **NO — the check did not exist.** Its own counter reads "Total pings 70 → 71 **since Sep 15**" |
| **09-28 (15.1 h)** | **YES, CONFIRMED SENT** — DOWN 10:59:51 EDT, UP 18:05:35, to jacob@structtek.com |
| 10-04 (21.7 h) · 10-06 (11.3 h) · 10-06→07 (15.0 h) | **UNKNOWN to me.** No ping was sent during any of them, so the 8 h threshold was exceeded in all three; whether Healthchecks delivered is the half I cannot see |
| the open seventh | **UNKNOWN**, same reason |

So of six: **two could not have alarmed, one provably did, three are unmeasurable
from here.** The question "fired and nobody read it, or never fired at all" is
answerable for exactly one of the six from this side.
