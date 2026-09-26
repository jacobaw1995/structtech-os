# Golden path run 1 — reachability sheet

Track S, measured **2026-09-25 late evening into 2026-09-26** against the live database. Controller
decision the same day: **run 1 moves to the synthetic tenant**, because the run creates a fake lead, a
fake estimate, a fake job and fake purchase orders, and Brothers Metal Roofing is a live client
workspace.

**Tenant:** `ZZ SYNTHETIC Field Test (not a client, disposable)` · `e0851ad8-35d6-4e17-b267-6cd35cb6f713`
**Sign in as:** `jacob@structtek.com`, who is the **owner** of this tenant (last sign-in 2026-09-25
20:17 EDT). Use the top-bar tenant switcher; no new account is needed and none was created.

## Entitlements — what changed tonight

The registry is the CHECK constraint `tenant_modules_module_key_check`: **nine keys**. Before tonight this
tenant had **three** (estimating, coordination, field) and **no `crm` row at all**. It now has **four**.
Nothing else was enabled, and BMR's entitlements were not touched.

| | crm | estimating | coordination | field | delivery | scan | roadmap | tracker | build |
|---|---|---|---|---|---|---|---|---|---|
| **synthetic (after)** | **NEW** | ✔ | ✔ | ✔ | — | — | — | — | — |
| BMR (unchanged, comparison only) | ✔ | ✔ | ✔ | ✔ | ✔ | — | — | — | — |

**A bare entitlement row would not have been enough, and that was measured, not assumed.** `create_deal`
reads `crm_stage_config(org) -> 0 ->> 'key'` and raises when it is null; `crm_stage_config_internal` is
`coalesce(config->'stages','[]')`. So **no row** and **a row with `config = '{}'`** produce the *same*
refusal — *"organization e0851ad8… has no crm stage config"*. The row therefore carries a 7-stage config
(New Lead → Qualified → Site Visit → Estimate Presented → Negotiating → Won/Lost), a follow-up cadence of
`[2,5]`, and a lead_control_center of `fields / checklists / command_stages / lead_type_options`. File:
`supabase/seeds/20260925_synthetic_crm_entitlement.sql`.

## The twelve steps — reachable or not

Denominator is twelve. Everything below is for `jacob@structtek.com` as this tenant's owner, except
step 12.

| # | Step | Screen | Module | Reachable? |
|---|---|---|---|---|
| 1 | lead | `/w/<org>/crm` (`?new=1` for the form) | crm | **YES — new tonight.** Before the change this route redirected to `/w/<org>` and `create_deal` refused |
| 2 | intake | `/w/<org>/crm?deal=<id>` — the Lead Control Center opens on the same page, there is no per-lead route | crm | **YES — new tonight**, and only because the config came with it |
| 3 | estimate | `/w/<org>/estimating`, then `/estimating/<id>` and `/estimating/<id>/document` | estimating | YES |
| 4 | present | `/estimating/<id>/present` | estimating | YES |
| 5 | sign | in-app via the signature block, or a link at `/sign/<token>` | estimating (the link route is token-auth, outside the module system) | YES |
| 6 | job + master sign-off | job from `/w/<org>/coordination`; sign-off on `/coordination/<workOrderId>` | coordination | YES |
| 7 | trade work orders | `/coordination/<workOrderId>` | coordination | YES |
| 8 | materials / take-off | the take-off review and the material form, both on `/coordination/<workOrderId>` | coordination | YES — **but the estimate must really be signed**: `materialize_take_off` refuses *"this job's estimate is X, not signed"* |
| 9 | purchase order | the PO list on `/coordination`, detail at `/coordination/po/<poId>` | coordination | YES |
| 10 | schedule | the schedule-block form on `/coordination/<workOrderId>`; crews at `/coordination/crews` (optional — a typed crew name is still allowed) | coordination | YES |
| 11 | production packet + callouts | `/w/<org>/field/<workOrderId>?tab=packet` | **field** | YES — **and note it is reached through the FIELD module. There is no office-side packet screen.** An owner sees `field`, so this works; an `office` member does not (`modulesVisibleForRole` gives office only crm/estimating/coordination) |
| 12 | crew view | `/w/<org>/field` | field | **YES, with two conditions** — see below |

**12 of 12 have a reachable screen. Two conditions on step 12, and they are conditions, not gaps:**

1. **It needs the crew login**, which is not Jacob's own account: the `field` member is
   `proof-crew@zz-synthetic-field-test.invalid` (last sign-in 2026-09-20). Its password is on this machine
   in two gitignored files written by `scripts/pilot/create-synthetic-logins.sh` — in U's worktree as
   `FIELD_TEST_PASSWORD` in `.env.proof.local`, and in X's worktree as `PROOF_CREW_PASSWORD` in the same
   filename. Named by variable, never by value.
2. **It needs a correctly dated schedule block** — see trap (a).

## The two traps

### (a) The crew screen shows a job only while `end_date >= today`

**Measured:** `fetch_field_jobs` filters `sb.end_date >= p_today` on trade, non-voided work orders. The
tenant's only existing block is `a2a0cf7e…` on the trade work order, **2026-09-17 → 2026-09-19**, and
today in New York is **2026-09-26**, so it returns **0 jobs**. That block is dead and tomorrow's is
step 10's to create.

**The one line:** **date the block so its `end_date` is the run day or later** — `start_date` and
`end_date` both set to the run day is enough.

**And the reason that is enough is worth one more line, because the obvious worry is closed.** `p_today`
still **defaults** to `CURRENT_DATE`, which is the *session's UTC* date, and from 8 PM EDT that is already
tomorrow — a block ending on the run day would vanish that evening. **The field page does not use the
default:** `src/app/w/[orgId]/field/page.tsx:56` passes `todayInNewYork()`, and that is in the deployed
commit. So the screen is correct all day. The UTC default remains a trap for anything that calls the RPC
*without* `p_today`, which is a real residual and not this run's problem. Setting `end_date` a day past
the run day costs nothing and makes the run independent of it.

### (b) `create_trade_work_order` never reads `sign_off_at` — STILL TRUE

**Measured two ways.** `prosrc ~ 'sign_off_at'` is **false**, and the full body checks only: org
membership, `kind = 'master'`, not voided, a non-blank trade, assignee type/ref supplied together,
assignee type in (crew, department, subcontractor), predecessor is a trade on the same job, and a
double-submit guard on (job, trade, assignee). **No sign-off gate anywhere.**

**And it is not a theoretical hole — this tenant already demonstrates it.** The existing master
`029e4346…` has `sign_off_at` **NULL** and already carries a trade work order (`6af911f6…`, "SYNTHETIC
Roofing"). So step 6's sign-off can be skipped and steps 7–12 still fill every table. **If the run is
meant to prove the gate, the gate has to be watched for by the person running it; the software will not
stop you.**

## What is already in this tenant, so the run does not mistake it for its own work

deals **1** (at stage `new_scan`, which is StructTech's vocabulary and **not** one of the seven stages now
configured — so it renders in **no column** on the board; left alone on purpose, so there is only ever one
lead in "New Lead" and it is the one the run creates) · estimates **1** (signed) · estimate_line_items
**1** · signatures **1** · jobs **1** · master **1** (not signed off) · trade **1** · material_items **1**
· schedule_blocks **1** (expired) · **and zero of:** crews, purchase_orders, take_off_decisions,
production_packets, check_ins, qc_items, products.

## One thing that got wider tonight, reported rather than buried

Enabling `crm` gave this tenant a crm config where there was none, and **a `field` member can read that
config**: `tenant_modules` carries a permissive `member read own tenant_modules` SELECT policy scoped only
on `my_org_ids()`, and `crm_stage_config` / `crm_follow_up_cadence_days` apply **no role or capability
test** — measured as the crew: 4 tenant_modules rows, 3 crm config keys, 7 stages.

**It is not any of the three negatives the ruling named.** No deal, no estimate, no money: seven generic
English stage labels, a `[2,5]` cadence, and the intake-checklist *definitions*. The class was already
open — a BMR crew, if BMR had one, could read BMR's crm config today — and what changed is that this
tenant now has a config to read. **Not reverted**, because reverting makes step 1 impossible for the sake
of seven words. Filed for a ruling: scope the two config readers on a capability, or narrow that SELECT
policy.
