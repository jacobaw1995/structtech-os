# RULINGS AND CORRECTIONS — week of 2026-10-05

Recorded by Track S on **`Thu Oct  8 13:58:21 EDT 2026`**. Production serving **`0a22464`**, read from
`/api/health`. Each item carries an observable trigger rather than a date.

---

## 1 · THE FREEZE BREACH — and the correction is to my own report

**Migration `20261007123837 wh_pdf_files_staff_read_and_delivery_claim` applied at 08:38:37 EDT on
Wednesday 2026-10-07**, inside the 6 AM – 8 PM window Material Matrix **had acknowledged three times.**

### ⚠ CORRECTION TO TRACK S's 2026-10-07 REPORT: THEY WERE TOLD.

My pilot-day report said *"the pilot-day no-migration rule was broken by the one party it was never
sent to"* and *"no blame attaches to Material Matrix, who were not told."* **That is wrong, and it is
wrong because I conflated two different things:**

- **The FREEZE** — a 6 AM–8 PM window — **was sent, and was acknowledged three times.**
- **The runbook's RULE ONE** — "no migration today, from any track, for any reason" — **was not sent.**
  That is the one I wrote on 2026-10-06 with the note *"the rule needs sending, not just writing."*

**I reasoned from the unsent rule to the conclusion that nothing had been sent.** Two instruments,
one conclusion drawn from the weaker. The breach is a breach of an agreed freeze, not a failure to
communicate.

### THE CONTROLLER'S RULING, which is about us and not about them

> **A FREEZE THAT DEPENDS ON ANOTHER PARTY'S COMPLIANCE IS NOT A CONTROL — IT IS A REQUEST WITH A
> CALENDAR ON IT.**

The evidence for the ruling is our own behaviour, not theirs:

- **Their change did no harm, and the reason is that their predicate was bucket-scoped** —
  `bucket_id = 'pdf-files' AND name ~~ 'work-orders/%' AND my_wh_role() IN (admin,assistant,driver)`.
  It cannot see `org-files`.
- **We learned it had landed 34 hours later, from an audit, not the same day from a monitor.** The
  instrument that found it was a human comparing two numbers in a snapshot file.
- **So the pilot was protected by their scoping and by luck — "scoping and luck, not a control" is my
  own sentence from Tuesday, and it is the finding.** A control would have told us at 08:39.

**TRIGGER: the next time a freeze is agreed.** A freeze is worth agreeing and worth nothing as
protection. The control that would make it one is an alarm on the ledger — `max(version)` changing
inside a window — which nothing currently watches. **Not built tonight; named.**

---

## 2 · THE PUBLIC-GRANT SURFACE — measured by Track X, re-verified here

**Every number below was re-measured independently before being recorded. All three match X exactly.**

```sql
select count(*) as total,
       count(*) filter (where has_function_privilege('anon',p.oid,'execute')) as anon_executable,
       count(*) filter (where has_function_privilege('anon',p.oid,'execute') and p.prosecdef) as anon_and_definer,
       count(*) filter (where has_function_privilege('anon',p.oid,'execute') and not p.prosecdef) as anon_and_invoker
from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public';
--  432 | 194 | 5 | 189
```

### 2a · "5 of 430 are anon-reachable" understated reachability by 189 functions

**194 of 432 public functions are anon-EXECUTE-able. The 5 is the SECURITY DEFINER *subset*, not the
reachable set.** The controller's figure was the right number for the wrong question: it answered
*how many anon-reachable functions bypass RLS*, which is the dangerous subset, and was read as *how
many anon can call*. **Both are worth knowing and they differ by 189.**

### 2b · CLOSED BY ACCIDENT, NOT BY A CONTROL

**189 functions carry a live PUBLIC execute grant** — `proacl is null`, or an acl whose first entry is
`=X/...` with no grantee before the `=`. **ALL 189 ARE SECURITY INVOKER. Zero are SECURITY DEFINER**
(measured; the split is 189 / 0).

They are harmless **only because a SECURITY INVOKER function runs as the caller, so RLS applies to it
normally.** That is rule 13's exact shape: an absence standing in for a control, with no owner and no
alarm.

> **TRIGGER: the day anyone converts one of those 189 to SECURITY DEFINER.** On that day the
> function stops being mediated by RLS and keeps its PUBLIC grant, and nothing in the build would
> notice. There is no check for this — not in `pilot-readiness.mjs`, not in any sweep.

### 2c · And the protection is a PROJECT-LEVEL DEFAULT, not our migration discipline

`pg_default_acl` for `objtype='f'`, resolved per schema — and **the two entries for `public` disagree
on `anon`, keyed on which role creates the function:**

| creating role | schema | function default acl | anon by default? |
|---|---|---|---|
| **`postgres`** | **`public`** | `postgres=X, authenticated=X, service_role=X` | **NO** |
| **`supabase_admin`** | **`public`** | `postgres=X, anon=X, authenticated=X, service_role=X` | **YES** |
| `postgres` | `storage` | `postgres=X, anon=X, authenticated=X, service_role=X` | **YES** |

**So whether a brand-new function in `public` is anon-callable depends on who created it, and that is
a project setting we did not author and do not own.** Our discipline — measured by X: **163 explicit
revokes across 55 of 76 files, against 509 `create function` statements** — is belt-and-braces on top
of it, and it covers 55 files of 76.

**⚠ THIS REFINES CLAUDE.md RULE 7's PREMISE AND THE REFINEMENT IS WORTH HOLDING CAREFULLY.** Rule 7
says every new security-definer function in `public` is anon-executable the moment it exists unless
the migration revokes it. **That is true for a function created by `supabase_admin` and NOT true for
one created by `postgres`** — which is what a migration applied as the ledger owner produces. Rule 7
stays exactly as it is, for two reasons: it is still right about the **`PUBLIC`** grant (neither
default grants PUBLIC, so the 189 come from somewhere else and `ALTER DEFAULT PRIVILEGES` genuinely
cannot remove it), and **a rule whose correctness depends on which role ran the migration is a rule
you follow unconditionally.**

> **TRIGGER: any change to project default privileges.** Nothing in this repo would detect one.

---

## 3 · R10's FRAMING WAS TOO STRONG — recorded rather than quietly dropped

Track S wrote, repeatedly, that on the Hobby plan **"we can see nothing after an hour."** **That was
wrong.** Measured 2026-10-07:

- **Raw runtime logs: 1 hour.** A `since: 24h` query and a `since: 60m` query were both **refused by
  the API** with the retention message; `50m` succeeded. **Earliest retrievable timestamp was
  18:01:24.67 EDT on a day that started twelve hours earlier.**
- **Aggregated error clusters: roughly a month.** `get_runtime_errors` answered a **24-hour** query
  and returned a cluster whose **first occurrence is 2026-09-09** — name, count, affected routes,
  first/last seen, and a sample message.

**Strictly less than a log line** — no request id, no timing, no surrounding context, **and errors
only, so a check-in that fails without throwing leaves nothing.** **R10 still FAILS and is still a
purchase, not code.** But the sentence was wrong and the correction belongs on the record, because the
difference between "nothing" and "errors only, for a month" changes what is worth asking after an
incident.

**TRIGGER: before anyone concludes an incident is unknowable.** Ask the aggregated table first.

---

## 4 · THE MONITOR POISONS ITS OWN EVIDENCE

The front-door probe requests `/roadmap/frontdoor-monitor-nonexistent-token`. That path lands in the
route's `restricted` branch, which **logs at error level**, because `anon` has no EXECUTE on
`fetch_roadmap_by_token` (verified: `proacl` is `postgres=X | authenticated=X | service_role=X`) and
the route catches the resulting `42501`.

**So the monitor emits an error-level line on every single run, by construction.** On a one-hour log
budget that means **the only surviving error in the window is a self-inflicted false positive.**
Measured on pilot day: 7 logs retained, exactly one at error level, and it was this.

> **Anyone reading those logs cold starts by investigating nothing.**

**RECOMMENDED, NOT MADE** — two options, the first preferred:

1. **Log that branch at `info`.** The `restricted` outcome is an expected state for a logged-out
   request, not an error; it is the only branch that fires for every anonymous visitor. One line in
   `src/app/roadmap/[token]/page.tsx`. Keeps the probe honest and stops the noise at the source.
2. **Point the probe at a path that does not trip a `42501`** — e.g. `/login`, which the monitor
   already checks. Cheaper but weaker: it stops testing that the roadmap route renders at all.

**TRIGGER: before anyone debugs from Vercel logs.** Until one of those lands, the first error in any
window is to be ignored until identified.

---

## 5 · Controller errors recorded as rules

**CLAUDE.md 35, 36, 37**, in the existing numbered format:

- **35 — NEVER STATE A SHA IN A DIRECTIVE. INSTRUCT THE READER TO READ IT.** Three directives this
  week carried a stale `main` (`bd181d3` while production served `ab865f2`).
- **36 — AN ENUMERATION OF OUTCOMES IS NOT A QUESTION. ASK WHAT HAPPENED.** The four-tap question
  offered three answers and the true one was a fourth: the test did not run.
- **37 — A COUNT IN AN INSTRUCTION MUST NOT EXCEED THE SET.** "Read the TEN functions in your
  ungated set" against a set of 14 — satisfiable by luck; at 8 it would not have been.

---

# CLOSING RULINGS — recorded 2026-10-08 19:49 EDT

## 6 · THE FREEZE: WHAT ACTUALLY HAPPENED, AND THE SYMMETRY IS THE FINDING

**Material Matrix answered in full, unprompted.** Their director **lifted the freeze verbally on
Wednesday morning, with real authority to do so.** Their engineer accepted the lift, **wrote "tell
StructTech in one line" as a CLOSING RECOMMENDATION rather than a step on the path**, and issued the
go. `20261007123837` applied at 08:38:37 EDT.

**Beside that, Track S's own Wednesday sentence:** I wrote Rule One into
`docs/PILOT_DAY_RUNBOOK_2026-10-07.md` on 2026-10-06 **and wrote beside it that it needed sending,
because Material Matrix was not reading the runbook.** The note was correct. **It was not acted on in
time.**

> **BOTH PARTIES COMMITTED THE IDENTICAL ERROR WITHIN 24 HOURS, AND THAT SYMMETRY IS THE FINDING —
> not either failure on its own.**

Each side wrote down the thing that would have prevented the problem, **in the correct words, as an
aside.** Neither put it on the path. A single-party failure invites a process fix aimed at that
party; **two independent instances of one shape in one day say the shape is the defect.** It is
recorded as CLAUDE.md 38 for exactly that reason.

**And the correction to my 2026-10-07 report stands as already recorded in §1 above: they WERE told.**
I conflated the freeze — sent and acknowledged three times — with the runbook's Rule One, which was
not sent, and reasoned from the weaker instrument to a conclusion about the stronger.

## 7 · ACCEPTED FROM MATERIAL MATRIX: THREE DROPS IN A ROLLBACK IS WORSE THAN ONE IN A MIGRATION

**Adopted whole.** Track S found four `DROP POLICY IF EXISTS … ON storage.objects` — three in a
rollback, one in a proposal — and **took comfort from "zero in applied migrations."**

**That was comfort from the wrong fact.** Material Matrix's reasoning, accepted:

> **A rollback is what gets run in a panic, by whoever is awake, without review.** A migration is
> read before it applies, in daylight, by someone who chose to open the file. **So an unscoped DROP
> is MORE dangerous in a rollback than in a migration, not less** — and three of them is three
> chances for the one that matters.

**We were relieved by the wrong fact.** The scoping shipped 2026-10-08 (`8aedef5`): each of the three
now asserts the policy exists **and** that its expression carries our own `bucket_id = 'org-files'`
term, with all three branches proved — including a decoy wearing our exact name over `product-photos`,
which the loop **refuses**.

**TRIGGER: any `DROP` in any file under `supabase/rollbacks/`.** It is held to a higher standard than
the same statement in a migration, for the reason above.

## 8 · THE TWO MECHANISMS — one per party, and neither is a note

**Theirs: a freeze file read by their apply path.** A lift becomes **a timestamped commit** rather
than a sentence in a meeting. Their engineer's "tell StructTech in one line" then has somewhere to
live that the apply path must pass through, instead of beside it.

**Ours: a monitor on `supabase_migrations.schema_migrations`.** **Track X builds it next.** The
shape is already measured: on 2026-10-07 the ledger's `max(version)` moved at 08:38:37 EDT and **we
learned 34 hours later, from an audit, not from an alarm.** A monitor on that one value would have
told us at 08:39. It is the control the freeze was standing in for.

**Both are CLAUDE.md 38 applied: a control that sits on the path that performs the action.**

### NO FREEZE IS IN FORCE NOW, AND NONE IS NEEDED

The pilot did not run; there is no live field data to protect this week; migrations are back in Track
S's lane and one shipped today. **Recording this so that a future reader does not find §1's freeze
language and infer a standing rule that no longer applies.** The next freeze gets the mechanism, not
the request.

---

# 9 · FRIDAY'S TWO MEASURED FACTS — and both correct something already written down

**Verified by Track S from `pg_available_extensions` on `Sat Oct 10 03:4x EDT 2026`, not accepted
from the controller's reading. All four figures match exactly.**

| extension | default version | installed version | state |
|---|---|---|---|
| **`pg_cron`** | **1.6.4** | — | **AVAILABLE, not installed** ✓ |
| **`pg_net`** | **0.20.0** | — | **AVAILABLE, not installed** ✓ |
| **`http`** | 1.6 | **1.6** | **INSTALLED** ✓ |
| **`supabase_vault`** | 0.3.1 | **0.3.1** | **INSTALLED** ✓ |
| *(context, unasked)* `pgsodium` | 3.1.8 | — | available, not installed |
| *(context, unasked)* `pg_graphql` | 1.5.11 | **1.5.11** | installed |

`pg_extension` holds **8** installed extensions; **neither `pg_cron` nor `pg_net` is among them.**
**Nothing was installed today** — see the standing instruction below.

## 9a · THE MONITOR'S DELIVERY PROBLEM DOES NOT REQUIRE VERCEL PRO

**`pg_cron` runs inside the database we already have, at minute granularity, on the free plan.**

**So the six-hour figure was a property of the GitHub Actions cron, not of the problem.** The
`READINESS_LOG.md` measurements — 23 gaps since 09-30, median **5.61 h**, p90 **6.96 h**, max
**7.37 h** against an 8 h threshold, **38 minutes of margin** — describe *that scheduler's drift*,
and they were being read as the cost of scheduling anything. **They are not.** A ledger watch on a
minute cadence has no drift budget to spend.

## 9b · A MONITOR THAT WATCHES A SYSTEM FROM INSIDE IT CANNOT REPORT THAT SYSTEM BEING DOWN

**This is the limit that decides where `pg_cron` fits and where it must not be used.**

- **FITS — the ledger watch.** The thing being watched is a row in
  `supabase_migrations.schema_migrations`, **inside the same database as the scheduler.** If the
  database is down there is no new migration to miss, so the blind spot is not a blind spot.
- **DOES NOT FIT — a dead-man ping.** *"os.structtek.com has not answered in N minutes"* cannot be
  raised by a job that stops running when the thing it watches stops. **The external monitor must
  stay external.**

### ⚠ CORRECTION TO THE THURSDAY NOTE THAT GAVE VERCEL PRO THREE REASONS

The Thursday entry listed Vercel Pro's costs as **log retention · log drains · non-commercial terms
· no Vercel Cron**, and the scheduler argument was read as applying generally.

**It applies only to the EXTERNAL monitors.** Corrected:

- **Vercel Pro keeps:** **1-hour log retention**, **no log drains**, and **non-commercial Hobby terms
  while serving a paying client.** Those are unchanged and `R10` still FAILS on the first two.
- **Vercel Pro loses:** the *scheduler* argument, for anything a `pg_cron` job could run — which is
  the ledger watch. It keeps the scheduler argument for the dead-man ping, by 9b.

**Jacob's list item 2 stands, on narrower grounds than it was written.**

## 9c · THE COST, AND IT IS WHY NOTHING IS INSTALLED TODAY

**`pg_cron` runs SQL. The existing monitor is Node.** So a `pg_cron` path is **a second
implementation in a second language** — against **Track X's own principle that what is exercised
should be what runs.** `scripts/monitor/migration-watch.mjs` (merged to main today) is the Node one;
a SQL twin would be a second thing to keep true, and the one that fires at 3 a.m. would be the one
nobody has read recently.

**X is designing against that constraint and has not reported. NOTHING IS INSTALLED TODAY, and
installing before the design exists is exactly the shape recorded as CLAUDE.md 38** — a control put
in place ahead of the path it is meant to sit on.

**TRIGGER for revisiting: Track X's design report.** Not a date.

## 9d · AND THE LEDGER MOVED FOUR TIMES WHILE THIS WAS BEING DISCUSSED

Measured today, `version > '20261008180116'`, stamps converted **once** from UTC:

| version | EDT | whose |
|---|---|---|
| `20261008235148` `wh_settings_read_admin_only` | **Thu 19:51:48** | Material Matrix |
| `20261009013905` `wh_order_drop_off_confirm_and_retract` | Thu 21:39:05 | Material Matrix |
| `20261009015711` `wh_orders_read_driver_sees_own_or_unclaimed` | Thu 21:57:11 | Material Matrix |
| `20261010073707` `wh_order_children_read_follow_the_order` | **Sat 03:37:07** | Material Matrix |

**Four, all theirs, none ours.** Ledger now **271 rows — 112 Material Matrix, 159 ours.**

**The first landed six minutes after Thursday's session read its clock at 19:45:39. The fourth landed
68 SECONDS AFTER THIS SESSION'S FIRST COMMAND.**

**R15 caught it on its first run on main, against a real event rather than a fixture** — which is the
positive control rule 20 asks for, supplied by reality instead of by a mutant. **Reported, not
investigated** (rule 9: a delta you did not cause is identified, not diagnosed). The surfaces that
would tell us whether it touched ours all PASS: **R12** 0 offenders of 231 definers, **R13**
`pg_default_acl` unchanged, **R14** 0 ours ungated.

---

# 10 · SUNDAY — THE LEDGER WATCH IS BUILT, AND ITS DELIVERY HALF IS NOT PROVED

**Track S, `Sun Oct 11 01:35–01:50 EDT 2026`.** `pg_cron` **1.6.4** installed; the detector built to
Track X's specification; **`20261011053800_migration_watch_cron`** applied 01:39:05 EDT.

## 10a · THE PRECONDITION PASSED AND WAS NOT SUFFICIENT

The directive's precondition — *does `vault.secrets` contain a row named `migration_watch_webhook`* —
**HELD.** One row, created **2026-10-11 00:36:04 EDT**, description "POST target for the migration
ledger monitor". **The value was never read or printed.**

**And the monitor still cannot deliver.** Measured, by shape only:

```
length=38 · scheme=(none) · path_segments=0 · has_trailing_slash=false
```

**38 characters, no URL scheme, no slashes — it is not a URL.** It is the identifier portion without
the host. `http_post` on it fails before any request is made.

**ISOLATED WITH A CONTROL, so this is not a guess about my own code:**
- `http_post('https://os.structtek.com/api/health', …)` → **HTTP 405.** A real response: transport
  works end to end.
- `http_post('aaaaaaaa-bbbb-…', …)` → **`Could not resolve host`** — a TRANSPORT failure, **the exact
  failure the monitor reports (`http=transport`)**.
- `http_set_curlopt` returns `t` for both options.

**So the mechanism is right and the stored value is not a URL.**

> **THE PRECONDITION CHECKED FOR A NAME AND THE CONTROL NEEDS A VALUE.** This is rules 28–29 in a new
> costume: presence is not usability, and a vault row's name tells you nothing about its contents.
> **A precondition on a credential should assert its SHAPE, not its existence** — here, that it starts
> `https://` and contains a host.

**THE ONE-LINE FIX, for Jacob, in the SQL editor — the full ping URL, not the identifier:**

```sql
select vault.update_secret(
  (select id from vault.secrets where name = 'migration_watch_webhook'),
  'https://hc-ping.com/<the-uuid-you-stored>'   -- scheme + host + path
);
```

**Until then the monitor behaves exactly as designed under delivery failure, which is the one thing
that could be proved:** the watermark is **held** and the consecutive-failure count **rises** — 6 and
climbing by 01:44 EDT. A failed POST does not lose the row.

## 10b · WHAT WAS PROVED, AND WHAT WAS NOT

| half | verdict | evidence |
|---|---|---|
| **Scheduling** | **MEASURED** | `cron.job_run_details`: ticks at **:00 of every minute**, runs 14–87 ms, 5 consecutive runs 01:40–01:44 |
| **Detection** | **MEASURED, 3 SECONDS** | no-op `20261011054242` ledgered at **T0 = 01:42:57 EDT**; the next tick ran at **01:43:00**; `alerting_branch_taken = t` asserted at that watermark |
| **Watermark held on failure** | **MEASURED** | watermark unchanged at `20261010075730` across 6 failed deliveries |
| **Delivery** | **NOT PROVED** | the stored secret is not a URL. **X's bound of ≤60 s + HTTP round trip remains a bound for this half** |

**THE 3 SECONDS IS A SAMPLE, NOT A PROPERTY, and the mechanism says why (rule 21):** a row lands at a
uniformly random point inside the minute, so detection latency is **uniform on (0, 60] s**. This trial
drew 3 s because the row landed 3 s before a tick. **Had it landed at 01:43:01 the same code would
have taken 59 s.** Expected ≈30 s, worst case 60 s, plus the round trip.

**THE COMBINED SCHEDULING+DELIVERY TEST — the only one X said matters — IS INCOMPLETE and is reported
as incomplete rather than as a partial pass.**

## 10c · THE MUTANT

`scripts/pilot/ledger-watch-fixture/run.sh`, rolled back. **PHASE 1** the real comparison fires on a
genuinely new row (274 ledger rows examined, size printed). **PHASE 2** the comparison is flipped
`>` → `<` **in the last definition of the function** (rule 22), the mutation is **asserted present in
`prosrc`**, and the mutant returns **`quiet`** on that same new row. **So PHASE 1 can fail, and
therefore means something.** Real function restored, verified in a new connection.

## 10d · R16 FAILED, I CAUSED IT, AND THE CHECK IS RIGHT

Installing `pg_cron` created the **`cron` schema**, which R16's expected boundary did not contain. **It
caught my own change within minutes, on its first run on main.**

**Verified independently:** `cron` grants **`anon` USAGE = false, `authenticated` USAGE = false** —
the same shape as `extensions` and `vault`. **The boundary moved in the safe direction**, and R16 is
right to refuse to decide that for itself.

**WHO CHANGED IT AND WHY: Track S, 2026-10-11 01:36:50 EDT, `create extension pg_cron` under the
controller's authorization, conditioned on the vault precondition.** The expected-boundary constant
lives in `scripts/pilot/pilot-readiness.mjs`, **which is Track X's file — so Track S has not edited
it.** The one-line change X needs is to add `cron` with `anon=false, authenticated=false`.
**R16 stays red until X makes it, and that is the correct state**: an expectation confirmed by its
causer and recorded by its owner (CLAUDE.md 45 — the guard was right).

## 10e · R17 IS WIDER THAN MY OWN RECOMMENDATION, AND IT FOUND A CALL SITE I COULD NOT

Yesterday Track S recommended this check and measured **118 call-site names, 118 reachable, 0
unreachable**, stating one limit: the axis sees only literal first arguments.

**R17 reads 119.** `src/` is unchanged since — so **the difference is the axis, not the code.** The
name mine missed is **`fetch_membership_context`**, at `src/app/select-workspace/page.tsx:17` and
`src/lib/workspace/context.ts:49`, both written with `.rpc(` on one line and the name on the next.
**My regex required them on the same line and I did not state that limit.**

**So yesterday's zero was correct about the 118 it examined and silently excluded one call site.** The
conclusion survives — R17 reports **119 of 119 reachable, and 0 call sites with a non-literal first
argument** — but the denominator was one short, and **I stated one blind spot while having two**
(rule 18). X's instrument is better than the recommendation that asked for it.

## 10f · THE HISTORY SWEEP'S ZERO, WITH ITS AXIS

**ZERO on seven high-confidence secret shapes.** **AXIS: 1,329 blobs across 426 commits and 12 refs —
GIT HISTORY, not the working tree.** A working-tree scan and a history scan answer different
questions, and only the second one speaks to a repository that has been public.

**AND TWO OF EIGHT DETECTORS FAILED THEIR OWN CONTROL FIRST.** That is the part that makes the zero
worth anything: **a zero from a sweep whose detectors were never shown firing is not a zero** (rule
20). Two were fixed before the run that produced the result.

**Consequence: the repo is still PUBLIC and nothing has leaked. So "make it private" is HYGIENE, not
an incident** — it stays on `docs/controller/JACOBS_LIST.md` at its existing priority and does not
become urgent.

## 10g · THE FOUR CLOSING CORRECTIONS

Recorded as **CLAUDE.md 42–45**: a margin measured on a chosen window is a fact about the window · a
count of a shared resource is stale the moment another party can write to it · a monitor whose
heartbeat rides its success path cannot report its own death · a guard that fails is more often right
than the file that tripped it.

---

## 11a · THE LEDGER WATCH IS PROVED END TO END — and 10a is now closed, not revised

**Measured by Track S from the state table and `cron.job_run_details`, not taken from
the controller's reading. `TZ=America/New_York date` = `Sun Oct 11 20:06:16 EDT 2026`.**

| what | reading | instrument |
|---|---|---|
| watermark | **`20261011054851`** (was `20261010075730`) | `public.migration_watch_state` |
| `consecutive_failures` | **0** (was 15 and climbing) | same |
| `last_ok_at` | `2026-10-12 00:06:00.155895+00` — **50 s old at the read** | same |
| `alerting` now | **false** — `max(version) = watermark`, so the comparison is quiet | ledger vs state |
| cron, last 8 ticks | `:00` of every minute, 0.38–0.49 s | `cron.job_run_details` |
| the comparison in the live body | **`v_max > v_watermark` INTACT, no mutation marker** | `pg_proc.prosrc` |
| the 2xx guard | **`v_status between 200 and 299` PRESENT** | `pg_proc.prosrc` |

**THE WATERMARK IS THE PROOF, AND IT IS A PROOF RATHER THAN A REPORT.** The only
statement that writes `watermark` sits inside `if v_status between 200 and 299`.
So `watermark = 20261011054851` **cannot** have been reached by any path except a
2xx response to a POST. **Delivery is proved by the value, not by a success message**
— which is the whole reason the advance was put behind the status code in the first
place. **The combined scheduling+delivery test that §10b reported INCOMPLETE is
COMPLETE.** §10a is not revised: it was true when written, and the thing it was
waiting on has happened.

**AND THE FIRST SUCCESSFUL DELIVERY WAS AN ALERT, WHICH FOLLOWS FROM THE SAME VALUE.**
The watermark could only have moved *to* `20261011054851` by the branch that names
that version — the `/fail` POST carrying `MIGRATION 20261011054851 [UNATTRIBUTED]`.
The quiet branch does not advance it past the ledger. **So the watch's first live
output in its entire existence was a true alert about a foreign migration**:
Material Matrix's `20261011054851 wh_revoke_view_dml_and_anon_team_read`, applied
**2026-10-11 01:48:51 EDT, unannounced**, 46 seconds before Track S's own commit that
night. **Not a fixture, not a test row, not ours.**

**THE TIMING, BOUNDED BY AN INDEPENDENT INSTRUMENT.** `vault.secrets.updated_at` for
`migration_watch_webhook` reads **`2026-10-11 23:57:34.371658+00` = 19:57:34 EDT**
(created `04:36:04+00`, so `updated_at > created_at` — the row was edited, not
replaced). The next tick ran **`23:58:00.089626+00`**. So the first successful
delivery was **26 seconds** after the fix landed, and is bounded to
`[23:58:00, 00:03:00]` UTC — the controller's own 00:03:48 reading saw roughly the
sixth success, not the first. **The exact first-success timestamp is NOT recoverable:
`last_ok_at` is a single row overwritten every minute, so the state table knows only
the latest.** Read the secret's `updated_at` instead; that one is durable. *(Name and
timestamps only were read. The value was never read, printed, or measured.)*

## 11b · THE ROOT CAUSE, WHICH IS THE CONTROLLER'S — AND THE RULE IS REAL BECAUSE SHAPE IS ASSERTABLE WITHOUT DISCLOSURE

**The vault held a controller PLACEHOLDER, 63 characters, stored verbatim because it
was a syntactically valid string literal.** Nothing in `vault.update_secret`, in
Postgres, or in the watch had any reason to object: a placeholder that parses is
indistinguishable from a value that works, right up to the moment something tries to
*use* it. **A PLACEHOLDER THAT IS SYNTACTICALLY VALID WILL BE EXECUTED.**

**The precondition Track S was told to check asserted a NAME when it needed to assert
a SHAPE** — and the whole weight of that distinction is that **shape is assertable
without disclosure**, which is what makes it a rule rather than an excuse. Not one of
these needs the value to leave the database:

```sql
-- all three answerable without reading, printing, or returning the secret
select decrypted_secret ~ '^https?://'            -- has a scheme
     , decrypted_secret !~ '[[:space:]]'          -- no stray whitespace
     , position('/' in decrypted_secret) > 0      -- has a path separator
from vault.decrypted_secrets where name = 'migration_watch_webhook';
```

Each returns a boolean. **The 38-character, scheme-less, slash-less string Track S
measured on Sunday morning would have failed the first and third of those at
`00:36`, nineteen hours before anybody noticed** — and the measurement Track S *did*
make (length and character class, never content) is itself the demonstration that
shape-without-disclosure is possible, because that is exactly what it was.

**The honest division of the 18 h 17 m.** The placeholder was the controller's. The
precondition's wording was the controller's. **The decision to report DELIVERY NOT
PROVED rather than blending it into a partial pass was Track S's, and it is the only
reason the gap was eighteen hours instead of however long a green-looking monitor
would have gone unexamined.** §10a called the precondition insufficient before the
cause was known; this is that paragraph's cause.

## 11c · AND THE SCHEDULER SAID `succeeded` 1,098 TIMES WHILE NOTHING WAS DELIVERED

**Unasked, and it is the finding Track S would least want a future reader to miss.**

```
runs_before_fix | runs_after_fix | succeeded_while_delivery_failed
           1098 |             10 |                            1098
```

Every run from `2026-10-11 05:40:00 UTC` to the fix at `23:57:34 UTC` — **1,098 of
1,098** — reports `status = 'succeeded'` in `cron.job_run_details`, and all 1,098 of
them delivered nothing. **The status is not wrong. It is answering a different
question**: the statement ran and returned a row. It *must* read `succeeded`, because
`migration_watch_tick()` catches the `http_post` exception by design, so a transport
failure is an ordinary return.

**A reader grading this monitor on its scheduler's own run table would have certified
it healthy for its entire dead period, at a perfect 1,098 for 1,098** — and would
have had a green table, a live cron job, and sub-second durations to show for it. The
only instruments that could see the truth are the two the function writes itself,
`last_ok_at` and `consecutive_failures`, because those sit on the **delivery** path
while the run status sits on the **invocation** path one layer above it. Recorded as
**CLAUDE.md 51**, the twin of 44: there a heartbeat rode its own success path, here a
success flag rode a layer above the thing that failed.

## 11d · X'S FIGURES — VERIFIED TWICE, AND THE SEVENTH WINDOW IS NOT QUITE THE OUTAGE

**Verified against `scripts/pilot/READINESS_LOG.md` AND re-derived from the GitHub API
by running `scripts/pilot/cron-drift-figures.mjs` with no `--write`. Every figure the
directive supplied matches both, to the digit:**

```
WINDOW 2026-09-03→2026-10-11, n=192 gaps  (193 successful scheduled runs of 204)
  median 4.51h · p90 6.59h · p99 15.10h · MAX 25.76h
  margin at the MAX vs the 8h threshold: -1066 minutes
  alert windows (gap > 8h): 7 — the seventh 2026-10-10T07:12Z -> 2026-10-11T08:58Z (25.8h)
```

The only line that differs between the log and my run is **`hours since the last
success: 0.1h` → `0.4h`**, which is the one figure that *should* differ: it is live.
**The script writing its own figures is what made this verification cheap** — there
was no hand-typed median to reconcile, which is the specific failure that put "38
minutes" into six directives.

**THE ONE CORRECTION, AND IT IS SMALL AND REAL. "That gap IS the front-door monitor's
own outage" over-identifies by about 7.5 hours.** Measured from the run list:

| | |
|---|---|
| last success before | `2026-10-10T07:12:45Z` — **the gap's start** |
| first failure | `2026-10-10T07:41:21Z` (**push**) — 28 m 36 s *after* the gap opened |
| scheduled failures | `13:46:42Z`, `18:39:56Z`, `22:36:53Z`, `2026-10-11T01:57:22Z` |
| next success | `2026-10-11T08:58:20Z` — **the gap's end**, 7 h 01 m after the last failure |

**The gap CONTAINS the outage and exceeds it at both ends.** First-failure to
last-failure is **18.27 h**; the gap is **25.76 h**. The extra 7.5 hours are not
failure at all — 28 minutes of ordinary interval before the breakage, and **seven
hours in which GitHub simply did not schedule a run.** So the seventh window measures
the outage *plus* the scheduler's own sparsity, and the gap's start is "last time it
worked," never "the moment it broke."

**AND THAT CORRECTS TWO RULES TRACK S WROTE THIS MORNING, not the directive.**
Rule 44 read "failed from **2026-10-10 09:46 EDT**" — that is the first failing
*scheduled* run (`13:46:42Z`). **The monitor's first failing run of any kind was the
push run at `07:41:21Z` = `03:41:21 EDT`, 6 h 05 m earlier**, and its log shows the
identical cause: `scripts/monitor/migration-watch.mjs:82: import { execFileSync }
from 'node:child_process'` tripping the grep guard. Rule 45's "four consecutive runs"
is likewise the **scheduled** count of **five** total failures. Both corrected in
place with the measurement beside them. **Dating an outage from the first run of
whichever trigger you happened to look at understates it by however long the other
trigger has been failing.**

## 11e · X STATED ONE BLIND SPOT WHILE HAVING THREE — and one of them its axis cannot close

Recorded as X reported it, because the third is the one that matters:

1. **the single-line limit** — `.rpc(` and the name on separate lines. This is the one
   Track S hit from the other side on 10-10 (118 vs 119, `fetch_membership_context`),
   and it is **closed**.
2. **concatenation** — a name built by concatenation yielded a **truncated** name,
   reported unreachable, with the dynamic counter left at 0 so the output read
   complete. **Closed**, and it is CLAUDE.md 46–47's source.
3. **the WRAPPER form, which that axis CANNOT close.** A helper that forwards a name
   into `.rpc` produces **no `.rpc(` match at the call site at all** — so a wrapped
   call is **absent from the 173**, not miscounted among them. No widening of a
   `.rpc(`-keyed extractor reaches it, because the thing it keys on is not there.

**X measured that no wrapper exists in `src/` by grepping for the shape, and said
plainly that this is a weaker claim than the extractor having looked.** That sentence
is the reason this section exists. An absence established by a *second, differently
shaped* search is evidence; an absence established by the *same* search is a tautology
— and the difference between them is exactly what rule 18 asks every sweep to state
about itself. R17's own output now carries it: *"a WRAPPER that forwards a name to
.rpc would not appear in 173 at all — measured 0 of each in src/ on 2026-10-11."*
**Three blind spots, two closed, one named and bounded by an instrument that is
honest about being the weaker one.**
