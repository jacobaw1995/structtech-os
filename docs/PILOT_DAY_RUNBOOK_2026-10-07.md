# PILOT DAY RUNBOOK — Wednesday 2026-10-07

Written by Track S on **Tue Oct 6 20:29:58 EDT 2026** (`TZ=America/New_York date`; `date -u` already
read 2026-10-07 00:29). Baseline: **`docs/PILOT_BASELINE_2026-10-07.md`**. Production was serving
**`bd181d3`**.

**Every factual claim here was checked against the repo or the database before it was written. Four
claims came in wrong and the true ones are below, marked ⚠ CORRECTED.**

---

## RULE ONE — NO MIGRATION IS APPLIED ON 2026-10-07. FROM ANY TRACK. FOR ANY REASON.

**The mechanism, not the instruction.** Supabase organization `structteck` is on plan **`free`**, tier
**`tier_free`** (management API, controller-measured 2026-10-06). **Free tier has no backups: no
PITR, no snapshot, no restore point.** So:

- **A migration has no undo.** A DDL statement that drops, renames, retypes or narrows something is
  permanent. There is no "restore to 09:00" on this plan.
- **A Vercel deployment rolls back in one click** and takes about a minute.

**Those two facts are not symmetric, and that asymmetry is the whole rule.** Every problem that can
be solved by a deployment rollback should be; nothing should be solved tomorrow by a migration.

⚠ **AND THE RULE NEEDS SENDING, NOT JUST WRITING.** The most recent migration in the shared ledger is
**`20261005205205 wh_many_drivers_and_printing_claim_columns` — Material Matrix's, applied
2026-10-05.** Track S can bind itself and can tell U and X, but **MM applies migrations to this same
database and is not reading this file.** This is the 2026-08-26 precedent exactly: a rule written for
ourselves and not sent, which is how an unrevoked function arrived. **Somebody has to tell them
today.**

## RULE TWO — NOTHING IS DELETED ON 2026-10-07.

**Voiding is reversible. Deleting is not.** Where a thing can be voided, archived or cancelled, do
that; where it can only be hard-deleted, leave it and write it down instead.

**The precedent pattern is in `supabase/restores/`**, two files, both written *before* the removal
they describe:

- `20261004_fake_lead_chain_restore.sql` — soft removals (`void_work_order` ×2, `void_estimate`,
  `archive_deal`), proved in a rolled-back transaction: 7 values captured, 0 mismatches, a mutant
  forcing 1. It also records the pin that was **impossible** (`deals.updated_at`, overwritten by a
  trigger) rather than hiding it.
- `20261004_track_s_po_and_material_fixtures_restore.sql` — hard deletes, said plainly as such,
  values emitted by `format(%L)` from the rows instead of transcribed, and two documented divergences
  the restore cannot undo.

**If anything must be removed tomorrow, the restore is written first and it is proved, or the thing
stays.**

---

## THE HIGHEST-PROBABILITY DEFECT: a check-in that does not visibly land

This already happened once. On 2026-10-04 Jacob submitted the first check-ins in this product's
history and **got four rows, because nothing on the screen said the first one had worked.**

**Two defenses now exist and NEITHER HAS RUN IN A BROWSER.** Confirmed from tonight's baseline:

| baseline fact | value |
|---|---|
| `check_ins` rows carrying a `client_token` | **0** |
| `special_trips` rows, total | **0** |

**So the whole path is unexercised by a human.**

**Defense 1 — the pending state.** `src/components/field/ActionForm.tsx`. Every submit the crew can
reach shows a pending label, and a tap taken during flight is not honoured. The special-trip buttons
name *which* reason is saving ("Saving… / Material missing"), because "Saving…" alone does not say
which of seven buttons took.

**Defense 2 — the idempotency token.** Three files:
- `src/lib/field/submission-token.ts` — mints one token per submission attempt, with a
  `getRandomValues` fallback and a non-cryptographic last resort, because a crew's phone is the one
  device in this build we cannot choose.
- `src/components/field/AddCheckInForm.tsx:107` — the hidden `client_token` input, rotated on a
  successful save so a deliberate second check-in is accepted.
- `src/lib/field/actions.ts:117` — passes `p_client_token` to `create_check_in`.

Behind them, migration `20261004213144` (check-ins) and `20261004225242` (special trips): a nullable
`client_token`, a **partial** unique index on `(org_id, client_token)`, and a two-layer function — a
pre-check plus a `unique_violation` handler that re-reads instead of raising. **A repeat tap returns
the first row's id and reads as success.** The roofer sees **"Check-in saved."** once, never an error.

**What to watch for:** a new `check_ins` row with a **NULL** `client_token`. The index makes duplicate
tokens impossible, so the failure shape is not two rows sharing a token — it is the caller not
sending one.

---

## THE EVIDENCE ASYMMETRY — the central fact of this runbook

**A SUCCESSFUL write leaves a durable row.** `field_events` and `record_field_event()` both exist
(readiness **R11 PASS**), so a saved check-in leaves a `check_in_saved` event with `outcome='ok'`,
plus the `check_ins` row itself. Permanent, queryable, in the database.

**A FAILED write leaves no row.** No check-in, and `field_events` records a `check_in_failed` with a
hint — **but only if the action reached the recording call at all.** A crash before it, a network
failure, or a function timeout leaves nothing in Postgres. **Its only trace is a Vercel runtime log,
and on plan Hobby that is kept ONE HOUR with no log drains.** Readiness **R10 FAILS on exactly
this**, and **R10 is a purchase, not code** — no commit can close it.

> **So the most dangerous class of pilot bug is the one this stack is least able to record.** A
> check-in that saves is self-documenting. A check-in that fails at 9:15 is undiagnosable by 10:16.

**THE MITIGATION IS A HUMAN SCREENSHOT AT THE MOMENT OF FAILURE.** Not afterwards. If something does
not work, the screenshot is the evidence, and nothing else will be.

**The screenshot must include the URL bar.** On the office surface the error arrives as a URL
parameter and is rendered raw, so **the URL is the only thing identifying which of the sites fired.**

---

## THE RAW ERROR SITES — ⚠ CORRECTED, and the correction matters for abort criterion 2

**The number 12 is right. The location is not.**

- **`src/app/w/[orgId]/coordination/[workOrderId]/page.tsx` contains ZERO `error.message` sites.** It
  is the **renderer**, at lines 367–369: `{searchParams.error && (… {searchParams.error} …)}`.
- **`src/lib/coordination/actions.ts` contains all 12.** Of those, **11** redirect via
  `workOrderHref(orgId, …, error.message)` and can therefore appear on a `/coordination/<id>` URL;
  **the 12th, line 69, redirects via `estimateHref(error.message)`** — a different surface.

**⚠ AND THE BIGGER CORRECTION: raw database error text CANNOT REACH A ROOFER-FACING SCREEN.** Measured
tonight:

- `src/lib/field/actions.ts` and `src/lib/field/special-trip-actions.ts` contain **0** `error.message`
  occurrences. They redirect with `classifyFieldError(error)` — **a code**.
- The field page renders only through `isFieldError(searchParams.error)` →
  `FIELD_ERROR_COPY[...]`, a lookup table. This is the controller's own **2026-09-15 ruling** — *a URL
  parameter is a code that gets looked up; the text always comes from us* — and it is implemented.
- **I checked the silent-failure shape and it does not exist either:** `classifyFieldError` has a
  catch-all `return "save_failed"`, and `save_failed` is in both the type and the copy table —
  *"That wasn't saved. Nothing was changed — please try again."* The type and the copy table hold
  **15 codes each, with zero mismatches in either direction**. **A roofer always gets a sentence.**

**So all 12 raw sites are on surfaces Jacob operates, not Anderson.** Abort criterion 2 is still worth
having, but it is a check on the **office** screen, and as written against a roofer-facing screen it
describes something the build structurally prevents.

---

## KNOWN AND EXPECTED — do not chase these tomorrow

1. **The Materials step renders grey because the job's material list is empty.** Confirmed:
   `material_items` for `d76d8664-…` = **0**. ⚠ **AND SO DOES SIGN-OFF — TWO chips are grey, not
   one.** `work_orders.sign_off_at` is NULL on both the trade and the master. The directive named only
   Materials; a runbook that names one grey chip of two sends somebody after the other.
2. **"Not linked to a crew" is harmless.** The schedule block `5aa34bb4-…` has `crew_id` NULL and
   carries the typed text "Install Crew". **The job reaches the phone through
   `work_order_crew_assignments`, not `schedule_blocks.crew_id`** — `fetch_field_jobs`'s scoping
   clause accepts either, and the assignment exists (`9d21e83d-…`, Install Crew, "Roof Install").
   Proved on 2026-10-05 by switching scoping ON in a rolled-back transaction: the roofer saw the job,
   not a refusal.
3. **Crew scoping is OFF by design for the pilot.** `scope_field_jobs_to_crew` reads **false** for
   BMR. Ruling of record (§5.4 ruling 4): BMR has one crew and one job, so scoping solves a problem
   that does not exist at that size and adds a setup step that can fail on pilot morning. **Do not
   switch it on tomorrow.**
4. **A late Healthchecks alert is the cron, not the product.** ✅ **Verified against
   `scripts/pilot/READINESS_LOG.md:408–414` and the figures have NOT moved:** 23 gaps since 09-30,
   **median 5.61 h, p90 6.96 h, max 7.37 h, 0 over the 8 h threshold → 38 minutes of margin.** The
   median has worsened from 4.62 h. **A false "down" tomorrow is a coin-flip away and it is GitHub
   Actions schedule drift, not os.structtek.com.** Check `/api/health` before believing an alert.

---

## ABORT CRITERIA — four, each with its rollback

**Rollback is the same action in all four cases: Vercel instant rollback to the prior deployment. No
build. No migration.** Vercel → the project → Deployments → the previous **READY** production
deployment → **Instant Rollback**. About a minute.

| # | criterion | what it means | rollback |
|---|---|---|---|
| 1 | **A check-in cannot be recorded after two honest attempts** | two genuine submissions, screenshots of both, and no new `check_ins` row | instant rollback |
| 2 | **Raw database error text appears in the URL bar on a roofer-facing screen** | ⚠ structurally prevented on the field surface (see above). If it happens anyway, the model of this build is wrong and that is itself the reason to stop | instant rollback |
| 3 | **Office-uploaded roof data will not load on the phone** | the file itself does not open through `/files/open`. **A broken thumbnail beside a working link is NOT this** — see the signed-URL section | instant rollback |
| 4 | **A field role cannot reach the job at all** | `fetch_field_jobs` returns `[]` or refuses for Anderson. Check the switch first: `scope_field_jobs_to_crew` must be **false** | instant rollback |

### What rollback does NOT do

**Rollback does not undo data. Rows written before it stay.**

**And that is correct, not a limitation.** Those rows are the evidence. A check-in written at 09:10 by
a deployment rolled back at 09:40 is the record of what a roofer actually did on a roof — and on a
**free-tier database with no backups it cannot be re-created.** Rolling back code to protect data is
the right trade; rolling back data to tidy up the code would destroy the only account of the morning.

**Corollary, from Rule Two: resist the urge to clean up after a rollback.** A half-finished check-in,
a special trip with a wrong reason code, a duplicate row — all of it is evidence until Thursday.
Void, never delete; and write the restore first if even voiding seems necessary.

---

## The signed-URL read path — answered, with the TTL measured

**Two reads, two lifetimes. This was measured, not reasoned.**

**1 · The thumbnail: ONE HOUR, minted per render, baked into the HTML.**
`DEFAULT_SIGNED_URL_TTL_SECONDS = 60 * 60` in `src/lib/storage/org-files.ts`, and
`src/components/files/WorkOrderFiles.tsx:44` calls `signOrgFiles({orgId, paths})` **with no
`expiresInSeconds` override**, so the default applies. The URL is created while the server renders
and is embedded in the `<img src>` that is delivered (line 68). The route is dynamic, so every fresh
request mints fresh URLs — but **a page already on a phone keeps the URLs it was given.**

**2 · Opening the file: 60 SECONDS, minted at the moment of the click.**
`src/app/w/[orgId]/files/open/route.ts` calls `signOrgFile(..., expiresInSeconds: 60)` and 303-
redirects. Its own comment states the design: *"the url is signed at the moment of opening (60 s), so
a page left open on a phone for an hour still opens its files."* It also records a `file_opened`
field event, bounded so it cannot stop the file opening.

### So: if a roofer opens the packet in the morning and the page sits until afternoon?

**The PHOTO STILL LOADS.** The link re-signs on every click. ✅

**But the THUMBNAIL WILL BE BROKEN** — its URL expired an hour after the page rendered. **A roofer
sees a broken-image icon next to a working link, and may reasonably conclude the file is gone and
never click it.** That is the realistic shape of this tomorrow, and it is **not** abort criterion 3.

### Is the TTL short enough to matter across a work day? YES — for the thumbnail only.

**THE SMALLEST SAFE CHANGE, NAMED AND NOT MADE.** Nothing ships tonight.

- **Preferred — one line:** point the thumbnail's `src` at the same `/w/[orgId]/files/open` route the
  link already uses. No new TTL, no new code path, no new surface; the route already re-signs and
  already authorizes. **Trade-off to decide first, not discover:** it would record a `file_opened`
  event per thumbnail *render*, which pollutes the adoption metric that event exists to produce. A
  `&thumb=1` parameter suppressing the recording keeps it one line in each of two files.
- **Alternative — also one line:** pass an explicit longer `expiresInSeconds` for the thumbnail. It
  is simpler and worse: it lengthens the life of a URL that leaks if the HTML is shared, which is
  precisely what the 60-second open route was built to avoid.

**Neither is a pilot-day change.** Both are Thursday's.
