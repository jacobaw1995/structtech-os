# PILOT DAY 1 — RESULT, Wednesday 2026-10-07

Written by Track S at **`Wed Oct  7 18:44:38 EDT 2026`** (`TZ=America/New_York date`). Production
serving **`ab865f2`**, read from `/api/health`. Baseline:
`docs/PILOT_BASELINE_2026-10-07.md`. Shared surface: `docs/SHARED_SURFACE_SNAPSHOT_2026-10-07.md`.

**No G6 question is opened here. G6 is 2026-10-13. Today is evidence collection.**

---

# THE FOUR-TAP VERDICT: THE TEST DID NOT RUN.

**Not "both defenses worked." Not "dedup failed." Not "the pending state failed." A fourth answer the
question did not offer: nothing was tapped.**

```sql
select count(*) from check_ins
 where (created_at at time zone 'America/New_York')::date = '2026-10-07';   -- 0
select count(*) from special_trips
 where (recorded_at at time zone 'America/New_York')::date = '2026-10-07';  -- 0
select count(*) from field_events
 where (occurred_at at time zone 'America/New_York')::date = '2026-10-07';  -- 0
```

**Zero rows of every kind, in every table, for the whole of 2026-10-07.** The four-tap question is
unanswerable from data because there is no data. Both defenses — the pending state and the
idempotency token — **remain unexercised by a browser, exactly as they were last night.**

**The last human activity in the app was yesterday:**

| last 3 field events | EDT | who |
|---|---|---|
| `packet_opened` | **2026-10-06 10:20:01** | Anderson Reyes |
| `page_ready` | 2026-10-06 09:27:26 | Anderson Reyes |
| `packet_opened` | 2026-10-06 09:27:16 | Anderson Reyes |

*(Anderson's `last_sign_in_at` is 2026-10-04 00:31:35 — sessions persist, so Tuesday's events came
from that still-live session rather than a new sign-in. Jacob 2026-10-03 23:48:21; Isaac
2026-07-20 15:36:44.)*

---

## 1 · WHAT RAN

**The monitor, and nothing else.** Every log line retained — seven in total — is either the front-door
monitor's sweep at 18:01 or Track S's own `/api/health` call at 18:44 while writing this.

| EDT | path | level |
|---|---|---|
| 18:44:39.56 | `GET /api/health` | info ← **Track S, this session** |
| 18:01:29.97 | `GET /api/health` | info |
| 18:01:28.30 | `GET /roadmap/frontdoor-monitor-nonexistent-token` | **error** |
| 18:01:27.08 | `GET /login` | info |
| 18:01:26.93 | `GET /` | info |
| 18:01:26.69 | `GET /login` | info |
| 18:01:24.67 | `GET /` | info |

**Zero requests to any `/field/` or `/w/` path in the retained window.**

## 2 · WHAT WAS WRITTEN

**Nothing.** Every baseline number is byte-for-byte unchanged — see §5.

## 3 · WHAT FAILED

**One error-level line, and it is expected by design, not a defect.**

```
GET /roadmap/frontdoor-monitor-nonexistent-token
[roadmap] refused for token (restricted): 42501: permission denied for function fetch_roadmap_by_token
```

Verified rather than assumed: `fetch_roadmap_by_token`'s `proacl` is
`postgres=X | authenticated=X | service_role=X` — **`anon` has no EXECUTE, deliberately**, which is
why it is not among the five anon-reachable definer functions. The route knows: its own comment at
`src/app/roadmap/[token]/page.tsx:22` says *"a logged-out request lands in the `restricted` branch"*,
and Track X already removed the detail that branch used to render. **The monitor is unauthenticated,
so it lands there on every run. Nothing is broken.**

### 🔴 But it is worth one finding of its own

**The monitor's front-door check emits an error-level line on every single run, by construction.** On
a one-hour log budget that means **the only surviving error in the window is a self-inflicted false
positive**, and anyone reading these logs cold would start by investigating it. The probe could use a
path that does not trip a `42501`, or the route could log that branch at `info`. Not a pilot-day
change; recorded.

## 4 · WHAT WE COULD NOT SEE — and this is the R10 evidence

**EARLIEST RETRIEVABLE RUNTIME LOG TIMESTAMP: `2026-10-07 18:01:24.67 EDT`.**

That number is the answer. **Everything before 18:01 today is already unrecoverable** — the entire
working day, start to finish.

Measured, not assumed:
- `since: 24h` → **refused**: *"The hobby plan does not retain runtime logs for the requested time range."*
- `since: 60m` → **refused**, same error.
- `since: 50m` → **succeeded**, window `21:56:21Z → 22:46:21Z` = **17:56 → 18:46 EDT**.
- `group_by: requestPath` over that window → **one group, one event.**
- The CLI request-log reader (`vercel logs`), which returns status-bearing request records rather than
  observability events, returned **7 logs, earliest 18:01:24.67**.

**So "clean" and "expired" are not confused here: the window is CLEAN, and the window is 45 minutes
long on a day that was 12 hours long.** Had a check-in failed at 09:15 this morning, there would be
nothing left of it by 10:16 — no row, because a failed write leaves none, and no log.

**R10 FAILS on exactly this, and R10 is a purchase, not code.** It is item 2 on
`docs/controller/JACOBS_LIST.md`.

### One correction to how R10 has been framed

**Not all error evidence expires in an hour.** `get_runtime_errors` reads a *pre-aggregated* error
table, and it answered a **24-hour** query and returned a cluster whose `first` is
**2026-09-09T00:44:28Z** — a month of history. So:

- **raw runtime logs: 1 hour** (the R10 problem, unchanged),
- **aggregated error clusters: ~30 days, name + count + routes + first/last seen + a sample message.**

**That is strictly less than a log line** — no request id, no timing, no surrounding context, and
only for errors that throw. But it is not nothing, and "we can see nothing after an hour" was too
strong. The one cluster it holds: that same roadmap/monitor line, **count=4, 4 users, last seen
2026-10-07T22:01:28Z.**

## 5 · BEFORE → AFTER, every baseline query re-run verbatim

| measurement | filter | BEFORE (10-06 20:3x) | AFTER (10-07 18:4x) | |
|---|---|---|---|---|
| `check_ins` total | `count(*)` | 1 | **1** | unchanged |
| …with a `client_token` | `where client_token is not null` | 0 | **0** | unchanged |
| …in BMR | `where org_id='9d32b5a9-…'` | 1 | **1** | unchanged |
| `special_trips` total | `count(*)` | 0 | **0** | unchanged |
| …with a `client_token` | `where client_token is not null` | 0 | **0** | unchanged |
| `field_events` total | `count(*)` | 74 | **74** | unchanged |
| …distinct `subject_ref` | `count(distinct subject_ref)` | 8 | **8** | unchanged |
| …non-null `subject_ref` | `where subject_ref is not null` | 8 | **8** | unchanged |
| …in BMR | `where org_id='9d32b5a9-…'` | 52 | **52** | unchanged |
| `org-files` objects | `where bucket_id='org-files'` | 1 | **1** | unchanged (surviving only — CLAUDE.md 34) |
| schedule blocks covering 2026-10-07 | `start_date<='2026-10-07' and end_date>='2026-10-07'`, grouped on `w.voided_at is null` | 2 — 1 LIVE, 1 VOIDED | **2 — 1 LIVE, 1 VOIDED** | unchanged |
| crew assignments on the pilot WO | `where work_order_id='d76d8664-…'` | 1 | **1** | unchanged |

**Twelve measurements, twelve unchanged.** The baseline was taken correctly and it has nothing to
diff against.

### Task 2 d/e, answered on their own terms

- **`check_in_saved` events today: 0.** The drift X measured as zero on 10-05 **is still zero, and
  for a reason that proves nothing** — there were no resends because there were no sends. The
  instrument was not exercised (CLAUDE.md 20: a zero from an instrument that was never shown a defect).
- **Today's field events with a NULL `subject_ref`: 0 of 0.** The 66-of-74 observation from last
  night stands untested today. It remains true of the historical set, and the conclusion it supports
  is unchanged: **`subject_ref` is populated only by events that have a subject** — `check_in_saved`,
  `file_opened`, `packet_opened` — **so it is not a count of activity and should not be read as one.**

---

## 6 · WHICH DONE-WHENS THE DAY EXERCISED

**None.** No Done-when was exercised, because the surface was not used.

What the day *did* establish, which is worth keeping:

| | |
|---|---|
| ✅ **Production stayed up all day** | the monitor's 18:01 sweep got 200s on `/`, `/login`, `/api/health`; `/api/health` answers now |
| ✅ **The shared surface held where it mattered** | the three `org-files` policies are unchanged from last night's reading |
| ✅ **The anon-reachable definer count did not move** | 5, all five explicitly granted |
| ❌ **Nothing about the field surface was tested** | by anyone, at any point today |

## 7 · WHAT CANNOT BE GRADED FROM DATA — and the screen act that would grade it

**Every one of these needs a person on a phone. None can be settled by a query.**

| # | question | the screen act |
|---|---|---|
| 1 | **Does a check-in land, and does it say so?** | Open the job as the `field` role, fill a check-in, tap Submit **once**. Expect **"Check-in saved."** and one new row. Then verify `select count(*) from check_ins where client_token is not null` = **1** |
| 2 | **Does the four-tap guard hold?** | Same form, tap Submit **four times**. Expect **one** row, one confirmation, no error. **The failure shape to look for is new rows with a NULL token** — duplicate tokens are impossible by the partial unique index |
| 3 | **Does a special trip record in ≤2 taps?** | Open "Log a special trip", tap one reason. Expect one `special_trips` row carrying a token |
| 4 | **Does the office file open on the phone?** | Tap the file on the job screen. **Expect the photo to open** (the link re-signs at 60 s per click) |
| 5 | **Does the thumbnail survive the afternoon?** | Leave the packet open **more than an hour**, then look at the thumbnail without reloading. **Expect it to be broken** — its URL lives one hour and is baked into the delivered HTML. **This is known, not a defect, and not an abort criterion** |
| 6 | **Are two chips grey?** | Open the work order in the office. **Expect Materials AND Sign-off grey** — `material_items` = 0 and `sign_off_at` NULL on both trade and master |

**Item 1 is the one that matters.** Items 2–6 are cheap once a session is open.

---

## 8 · THE THING THAT DID HAPPEN TODAY, AND IT WAS NOT THE PILOT

**A migration was applied to this shared database at 08:38:37 EDT this morning** —
`20261007123837 wh_pdf_files_staff_read_and_delivery_claim`, Material Matrix's. It added a tenth
`storage.objects` policy and two functions.

**The pilot-day rule said no migration from any track for any reason.** Track S wrote that rule last
night **and wrote beside it that it needed sending, because Material Matrix was not reading the
runbook.** The note was right and was not acted on in time. **No blame attaches to MM, who were not
told.** Full detail, with the measurements and the three moved numbers, is in
`docs/SHARED_SURFACE_SNAPSHOT_2026-10-07.md`.

**Nothing it changed touches the field surface** — their policy is scoped to their own bucket and
their own role helper, the three `org-files` policies are untouched, and the anon-reachable count
held at 5. **So the pilot was not harmed by it.** That is luck plus good scoping, not a control.
