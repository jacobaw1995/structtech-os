# JACOB'S LIST — things only Jacob can do

**Rewritten 2026-10-05 by Track S on a controller ruling.** The open list is **five items and only
five**. Everything A4.7 and `ORG_FILES_ENABLED` related is **removed: both are closed.**

**Every item below was verified against the repo or the live database in the session that wrote it.**
This file has been stale in four places before — pilot dates contradicting `docs/GATES.md` for two
days, two different wrong reading-counts on `ORG_FILES_ENABLED`, and a "real crew account" item that
stayed open after the crew existed. **The rule that follows from that is CLAUDE.md 30: a finding in a
report is not an open item until you check the commit it came with.**

**Live dates, agreeing with `docs/GATES.md`: pilot day 1 Wed Oct 7 · G5 ✅ ACCEPTED 2026-10-05
(one day early) · G6 Tue Oct 13 · G11 BLOCKED, no date.**

---

## THE OPEN LIST

| # | Item | Verified how, 2026-10-05 | Start by | Gates |
|---|---|---|---|---|
| 1 | **The four-tap check-in browser test.** Tap Submit four times on the phone, on BMR's pilot job, and confirm **one** check-in row appears carrying a `client_token`. The database guard (`20261004213144`), the caller, and the deployment are all in place; **the whole path is unexercised by a human.** | **`check_ins` = 1 row, and 0 rows carry a `client_token`.** `special_trips` = **0 rows, 0 tokens**. So nothing has ever gone through the idempotent path. Both counts read live today. | **Before Wed Oct 7** | G6 · pilot |
| 2 | **Vercel Pro, $20/mo.** Four distinct costs, not one: **1 hour** of runtime log retention · **no log drains** · non-commercial Hobby terms while serving a paying client · **no Vercel Cron**. | **Plan is `hobby`**, read from the Vercel API's `billing.plan` by `scripts/pilot/pilot-readiness.mjs`, which records **`FAIL R10`** on exactly that value. **This is now pilot-relevant, not just exposure: pilot-day evidence expires inside the hour it is produced**, so a question asked Wednesday evening about Wednesday morning has no logs to answer it. | **Before Wed Oct 7** | G6 · pilot · R10 |
| 3 | **Make `github.com/jacobaw1995/structtech-os` private.** `CROSS_TENANT_AUDIT_20260901.md` — six unfixed authorization defects, function names, the project ref — was publicly readable for ~24 hrs before the 9/02 fix. Also public: the proving queries, the incident history, 107 archived migrations. **Check Settings → Pages first** — a `CNAME` sits at the repo root and Pages on a private repo needs GitHub Pro. | **Still public**: `gh repo view` returns `{"isPrivate": false, "visibility": "PUBLIC"}`. | overdue | none — worsens with every push |
| 4 | **Stripe account under the StructTech entity.** The existing account is Material Matrix's; `create-payment-intent` and `stripe-webhook` are theirs. SCOPE §3 keeps billing separate, so a second account is required. Business verification is usually 2 days, occasionally weeks. | `docs/GATES.md` carries **G11 · BLOCKED — NO DATE**, and the ruling that the gate gets a date the day the account exists, counted forward from there. | **Sep 25 — overdue, and not re-dated** | **G11 · BLOCKED, NO DATE** |
| 5 | **🔴 SUPABASE PRO, $25/mo — RULED KEEP 2026-10-05, AND IT IS THE ONLY ITEM ON THIS FILE WITH NO UNDO.** A paying client's data sits in a **shared** free-plan Postgres with **no backups**, alongside a second project's schema. | **The migration count is NOT 66 — that was a nine-day window figure from 2026-09-22 and it has been carried ever since. MEASURED TODAY: the shared ledger holds 265 rows — 107 Material Matrix's (`wh_%`), 158 ours.** September alone took 112, August 94. **THE PLAN ITSELF IS NOT MEASURABLE FROM THIS SESSION** and is reported as such rather than asserted: the Supabase MCP is disconnected and no management token is available. Indicative only, from `pg_settings`: `max_connections = 60`, `shared_buffers = 224 MB`, PG 17.6 — consistent with a small instance, **not proof of a tier**. The instrument that would settle it is the Supabase dashboard's billing page or a management-API read, and **a human glance at it is one of the cheapest checks on this file**. | **TODAY — the pilot is TOMORROW** | G6 · pilot · and everything after it |
| 6 | **Healthchecks margin — 38 minutes.** The GitHub Actions schedule drifts, and the monitor's grace period is what absorbs it. | `scripts/pilot/READINESS_LOG.md:410`, 23 runs since 09-30: **median 5.61 h · p90 6.96 h · max 7.37 h · 0 failures**, against an **8 h** threshold. **8 − 7.37 = 0.63 h = 38 minutes of margin.** The median has *worsened* (4.62 h → 5.61 h). **One more drift of that size and the monitor cannot report on Oct 7 at all** — and a monitor whose silence depends on a scheduler being punctual is measuring the scheduler, not the site. | **Before Wed Oct 7** | G6 · pilot evidence |

---

### Why item 5 is urgent, which was not stated when it was raised

**TOMORROW — Wednesday 2026-10-07 — is the first day that database receives real field records.**
Until now everything in it is a build artifact, a migration fixture or a 946-row import that exists
elsewhere. **From tomorrow it holds a roofer's check-ins, hours, blockers, special trips and photos
of a real customer's roof** — facts that exist nowhere else and cannot be re-derived. **The window
in which there is something to lose opens in ONE day, not two:** today is Tuesday 2026-10-06,
computed from `TZ=America/New_York date`, and the controller's "two days" was written against
2026-10-05.

**AND NOTHING WATCHES THIS. The controller's statement is CORRECT, verified rather than accepted:**
`scripts/pilot/pilot-readiness.mjs` records exactly seven check ids — R1, R2, R2b, R3, R9, R10, R11
(R4–R8 are emitted per crew member) — and **not one of them mentions a plan, a tier, a backup or
PITR.** The single grep hit for "backup" is a comment about `field_events`. So **the one item here
with no undo is also the only one with no instrument**: twelve checks can read green on the morning
of the day the data becomes irreplaceable. Rule 13's shape — closed by an absence, and an absence
has no owner and no alarm.

## CLOSED 2026-10-05 — removed from the open list

- **`ORG_FILES_ENABLED` in Vercel + redeploy.** **CLOSED.** Set, verified `=== "true"` without the
  value being printed, and **exercised**: a 937,021-byte `image/png` sits at
  `9d32b5a9…/office-uploads/d76d8664…/` created **16:54:37 EDT**. Readiness **R2b and R9 both PASS**.
  The cause of the two-day delay is recorded in `docs/GATES.md` as four standing facts — the first
  being **never mark a feature flag "Sensitive" in Vercel**, because the typing destroys the ability
  to check the value, and **the value before 16:52:48 is permanently UNKNOWN** in consequence.
- **A4.7 — office upload + per-role file permissions.** **CLOSED, MET on both clauses**, and G5
  accepted a day early on the strength of it. The write half was observed by Jacob in a desktop
  browser; the refusal half on an iOS phone as the `field` role, where the file renders with **no
  remove control**. **SQL cannot grade the refusal half** — `storage.protect_objects_delete` fires
  for every role including the owner's — which is why a screen act was the only instrument.
  Evidence: `docs/G5_ACCEPTANCE_CASE_2026-10-05.md`.
- **Real crew account + walk every page.** **CLOSED.** BMR holds **1 crew ("Install Crew"), 1 crew
  person ("Anderson Reyes") carrying a `field` login that has signed in, 1 membership, 1 work-order
  assignment, 1 schedule block covering Oct 7.** The 2026-09-30 entry's "`field` = 0, crews 0" is
  stale. Readiness **R3 through R8 all PASS** as that identity.

---

## OFF THE OPEN LIST BY THE 2026-10-05 RULING — kept, not deleted

**The ruling named five open items. These were on the file and are not among them.** They are kept
here rather than destroyed, because a record removed is a record that cannot be re-raised, and **one
of them is the only item on this file with no undo.** Each needs a ruling to close or to return.

- **Catalogue browser check-out** (`docs/CHECKOUT_A2_CATALOG_2026-08-26.md`, 12 steps) — G2, overdue.
- **Resend account** — A6.1 / A6.6.
- **GitHub Actions schedule drift as its own defect** — distinct from item 5's margin: the 09-28
  seven-hour false alarm opened **34 minutes before any run failed**.
- **Lead form cannot report its own failure** — `results.html` swallows HTTP errors; lives in the
  `audit.structtek.com` repo, outside all three worktrees.
- **Supabase / HackerOne response** · **Google OAuth scope decision** · **Monitor login credential**
  — passive.
- **Recorded, not yet owed:** legacy JWT anon key · `tmp-render-probe` v7 active in production · a
  `field` member can read the tenant's CRM stage config (ruled 2026-09-27: scope after the pilot).
