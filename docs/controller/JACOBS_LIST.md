# JACOB'S LIST — things only Jacob can do

**Rule, set 2026-09-02:** these are logged here, not raised in daily reports. The controller
surfaces an item ONLY when (a) it is inside its START-BY window, or (b) it blocks a dated gate
within seven days. Everything else waits for a scheduled run-through.

Ordered by **START BY**, not by how loud it is. Dates cross-reference `docs/GATES.md`.

**⚠ THE PILOT MOVED.** Jacob's decision 2026-09-28: build the full job scope sheet first
(`docs/SCOPE_SHEET_SPEC.md`). Pilot 2026-10-07 → approximately **2026-10-19**; G12 10-31 →
approximately mid-November. Gate-linked dates below are the ORIGINAL ones; treat them as
"how much lead time this needs", not as live deadlines, until `docs/GATES.md` is re-dated.

---

## 🔴 GATING A DATED GATE

| # | Item | Start by | Gates | Cost |
|---|---|---|---|---|
| 1 | **Catalogue browser check-out** — `docs/CHECKOUT_A2_CATALOG_2026-08-26.md`, 12 steps. Step 7 is an explicit judge-it-as-a-designed-surface gate on a UI CC itself called the weakest thing that day. | **overdue** | G2 · A2 accepted · Sep 10 | ~1 hr |
| 2 | **Stripe account under the StructTech entity.** The existing account is Material Matrix's — `create-payment-intent` and `stripe-webhook` are theirs. SCOPE §3 keeps billing separate, so G11 needs a second account. Business verification is usually 2 days, occasionally weeks (EIN mismatch, bank name mismatch). | **Sep 25 — OVERDUE** | **G11 · Stripe billing · Oct 18** | ~30 min + wait |
| 3 | **Real crew account + walk every page.** Production has zero `field` members; BMR has 0 and 0 rows in `crew_memberships`; nobody has ever logged in as crew. Every A4 guarantee is proved against a synthetic user in a rolled-back transaction. **No account, no pilot.** | **Oct 1** | G6 · Field pilot | ~2 hrs |
| 4 | **SPF repair at Wix.** ⚠ **RE-CHECK BEFORE SPENDING THE TIME** — Track X measured 2026-09-25 that the apex now carries **one** `v=spf1` record, not two, and Resend has its own on `send.structtek.com` with DKIM live. May already be closed. Original finding: two `v=spf1` TXT at the apex is a PermError under RFC 7208 §4.6.4. DNS is at Wix (`ns6/ns7.wixdns.net`), not Vercel. | Sep 30 | A6.1 client comms | ~15 min + TTL |
| 5 | **Resend account.** | ~Oct 1 | A6.1 / A6.6 | 1h–24h verify |

---

## 🟠 EXPOSURE — no gate, but gets worse with time

| # | Item | Note |
|---|---|---|
| 6 | **Make `github.com/jacobaw1995/structtech-os` private.** It is public. `CROSS_TENANT_AUDIT_20260901.md` — six unfixed authorization defects, function names, the chain, the project ref — was publicly readable ~24 hrs before the 9/02 fix. Also public: PATH_SURFACE proving queries, the full incident history, 107 archived migration files. **Check Settings → Pages first** — a `CNAME` file sits at the repo root and Pages on a private repo needs GitHub Pro. Monitor still works private. | Every push adds more. |
| 7 | **Supabase Pro, $25/mo.** 66 migrations into this shared database in the nine days to 2026-09-22, roughly half of them Material Matrix's with no file in this repo — **on a free plan with no backups, holding a client's data.** Open since 2026-09-17. | The one that has no undo. |
| 8 | **Vercel Pro, $20/mo.** Hobby keeps logs 1 hour, which is why readiness item R10 has never passed. | Before the pilot. |
| 9 | **`ORG_FILES_ENABLED` in Vercel + redeploy.** Measured ABSENT on 09-16, 09-23, 09-25, 09-27. **Twelve days.** Storage policies were applied and proved 4/4 against the real Storage API on 09-16 — the feature is built and dark, and two readiness checks cannot move until it is set. | 3 min. |
| 10 | **Healthchecks grace-time test.** Delivery is proven (ARMED since 09-19). **Alerting has never been tested** — open since 2026-09-11. Shorten Period and Grace to 1 minute, wait for the email, note the time and address, set them back to 1 hour / 7 hours. **Never use Pause** — Healthchecks documents it as the way to avoid alerts, so it tests nothing. | 4 min. |
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
