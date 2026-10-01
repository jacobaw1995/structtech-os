# JACOB'S LIST — things only Jacob can do

**Rule, set 2026-09-02:** these are logged here, not raised in daily reports. The controller
surfaces an item ONLY when (a) it is inside its START-BY window, or (b) it blocks a dated gate
within seven days. Everything else waits for a scheduled run-through.

Ordered by **START BY**, not by how loud it is. Dates cross-reference `docs/GATES.md`.

**⚠ THE PILOT DID NOT MOVE. THE ORIGINAL DATES STAND.** This file carried *"THE PILOT MOVED …
approximately 2026-10-19"* until 2026-09-30, **contradicting `docs/GATES.md`, which withdrew both
re-datings on 2026-09-28** (commit `9df1c64`, after Jacob found a workaround and the job scope
sheet was shelved). The repo disagreed with itself across two files for two days. **GATES.md is
right and this header was stale.**

**Live dates, agreeing with `docs/GATES.md`: pilot day 1 Wed Oct 7 · G5 Tue Oct 6 · G6 Tue Oct 13
· G11 BLOCKED, no date.** Corrected 2026-09-30 by Track S.

---

## 🔴 GATING A DATED GATE

| # | Item | Start by | Gates | Cost |
|---|---|---|---|---|
| 1 | **Catalogue browser check-out** — `docs/CHECKOUT_A2_CATALOG_2026-08-26.md`, 12 steps. Step 7 is an explicit judge-it-as-a-designed-surface gate on a UI CC itself called the weakest thing that day. | **overdue** | G2 · A2 accepted · Sep 10 (unmoved — already past) | ~1 hr |
| 2 | **Stripe account under the StructTech entity.** The existing account is Material Matrix's — `create-payment-intent` and `stripe-webhook` are theirs. SCOPE §3 keeps billing separate, so G11 needs a second account. Business verification is usually 2 days, occasionally weeks (EIN mismatch, bank name mismatch). | **Sep 25 — OVERDUE, and NOT re-dated.** A later gate does not restart a verification clock that never started | **G11 · Stripe billing · ~~Oct 18~~ → ~~Oct 30~~ → BLOCKED, NO DATE.** Ruled 2026-09-28: the gate gets a date the day this account exists, counted forward from there | ~30 min + wait |
| 3 | **Real crew account + walk every page.** **RE-MEASURED 2026-09-30, live: BMR holds 2 members and `field` = 0; `crews` 0, `crew_people` 0, `crew_memberships` 0.** The only `field` login in the whole database is the synthetic tenant's. Nobody has ever logged in as a real crew member. Every A4 guarantee is proved against a synthetic user in a rolled-back transaction. **No account, no pilot.** | **Oct 1 — TOMORROW** | G6 · Field pilot · **Tue Oct 13** | ~2 hrs |
| 4 | ✅ **CLOSED 2026-09-30 — SPF at Wix needs no repair.** Read live from DNS today, not inferred: the apex carries **exactly ONE** `v=spf1` record — `v=spf1 include:_spf.google.com include:spf.leadconnectorhq.com include:mailgun.org ~all` — and `send.structtek.com` carries its own (`ip4:52.3.252.119 ip4:44.222.39.36 ip4:199.249.231.0/24 ~all`). **The RFC 7208 §4.6.4 PermError is gone**; X's 2026-09-25 reading holds five days later. Nothing to do. *(Start-by was Sep 30, which is today — it was never late.)* | ~~Sep 30~~ **CLOSED** | A6.1 client comms | **0** |
| 5 | **Resend account.** | ~Oct 1 | A6.1 / A6.6 | 1h–24h verify |

---

## 🟠 EXPOSURE — no gate, but gets worse with time

| # | Item | Note |
|---|---|---|
| 6 | **Make `github.com/jacobaw1995/structtech-os` private.** It is public. `CROSS_TENANT_AUDIT_20260901.md` — six unfixed authorization defects, function names, the chain, the project ref — was publicly readable ~24 hrs before the 9/02 fix. Also public: PATH_SURFACE proving queries, the full incident history, 107 archived migration files. **Check Settings → Pages first** — a `CNAME` file sits at the repo root and Pages on a private repo needs GitHub Pro. Monitor still works private. | Every push adds more. |
| 7 | **Supabase Pro, $25/mo.** 66 migrations into this shared database in the nine days to 2026-09-22, roughly half of them Material Matrix's with no file in this repo — **on a free plan with no backups, holding a client's data.** Open since 2026-09-17. | The one that has no undo. |
| 8 | **Vercel Pro, $20/mo.** Hobby keeps logs 1 hour, which is why readiness item R10 has never passed. | Before the pilot. |
| 9 | **`ORG_FILES_ENABLED` in Vercel + redeploy.** **BOTH EARLIER COUNTS WERE WRONG AND HERE IS WHAT IS CHECKABLE.** The entry said four readings and *twelve days*; the controller said nine readings and *fourteen days*. **The SPAN is fourteen days** — first recorded reading 2026-09-16, today 2026-09-30. **The reading COUNT I can verify from the repo is SIX** (09-16, 09-23, 09-25, 09-27, 09-28, 09-29); readings taken outside the repo I cannot see, so nine is possible and unverifiable from here. **Fourteen days, at least six readings, still absent.** Storage policies were applied and proved 4/4 against the real Storage API on 09-16 — the feature is built and dark, and two readiness checks cannot move until it is set. | 3 min. |
| 10 | ✅ **CLOSED 2026-09-30 AS A PASS — alerting HAS been tested, by production.** *"Alerting has never been tested"* was wrong: it fired **Mon 2026-09-28 10:59:51 EDT** to `jacob@structtek.com` and recovered **18:05:35**, a 7h05m window. No grace-time test is needed; the real thing ran. **AND THE REAL DEFECT, RECORDED IN ITS PLACE: the window opened from GitHub Actions schedule drift THIRTY-FOUR MINUTES BEFORE ANY RUN FAILED — so a working alert reported a healthy site as down for seven hours.** A monitor whose silence depends on a scheduler being punctual measures the scheduler, not the site. That is the open item now, and it is not a four-minute one. *(Track S carries the fired/recovered times and the address from the controller; they are not independently verifiable from this session — see the report.)* | — |
| 11 | **Lead form cannot report its own failure.** `results.html` catches with `.catch()`; `fetch` does not reject on HTTP errors, so a 401 resolves normally — visitor sees success, lead vanishes silently. Lives in the `audit.structtek.com` repo, outside all three worktrees. Detection is covered by X's monitor D2.3. | Fix the swallow when convenient. |

---

## 🟡 SMALL / PASSIVE

| # | Item | Note |
|---|---|---|
| 12 | **Supabase / HackerOne response.** Report filed on `anon` TRUNCATE over `storage.objects` / `storage.buckets`. If closed out of scope → `security@supabase.com`. | passive |
| 13 | **Google OAuth scope decision.** Plain sign-in on a Workspace-internal app is same-day. Add Gmail-send or Calendar scopes and it becomes a **restricted-scope app needing Google verification: weeks, with a security questionnaire.** Phase D, but approval costs nothing to sit on — start early if those scopes are ever wanted. | decision, then wait |
| 14 | **Monitor login credential.** Would let the monitor exercise a synthetic authenticated login end to end — the only way to assert on the data path where both P0s actually lived. | optional |

---

## RECORDED, NOT YET OWED

- **Legacy JWT anon key.** 208 chars, in `.env.local` and live `results.html`. Supabase is
  deprecating legacy JWT keys for `sb_publishable_…`. Future breakage, no date.
- **`tmp-render-probe` v7 is ACTIVE in production.** The name says temporary. Residue, same
  class as A1.0's orphans. *(CC's to remove, not Jacob's — listed here so it is not lost.)*
- **A `field` member can read the tenant's CRM stage config** — `crm_stage_config` and
  `crm_follow_up_cadence_days` apply no role or capability test. Seven generic labels, no deal,
  no money. **Ruled 2026-09-27: scope the readers on a capability, scheduled after the pilot.**
