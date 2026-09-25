# Gate calendar

**Any gate projected to slip more than 3 days is raised the day it becomes visible, with the cause named and the cut proposed.**

Recorded in the repo on 2026-09-23 by Track S, at the controller's instruction. Until today these dates lived
only in the controller's project docs, which no session can read — so **every date in every directive for
three weeks was unfalsifiable from the executor's side**, while every count in the same directives was
written to be contradicted. A deadline the executor cannot read is a deadline that cannot be contradicted.
From now on dates get contradicted the same way counts do, and the measurements are below the table.

## The twelve gates

| Gate | Date | What it is |
|---|---|---|
| G2 | Sep 10 | A2 Materials & Purchasing accepted |
| G3 | Sep 14 | Platform debt clear |
| G4 | Sep 20 | A3 Standards accepted |
| G5 | Oct 6 | A4 Field Execution accepted ⚠ TRIPWIRE |
| G6 | Oct 13 | Field pilot closes ⚠ TRIPWIRE |
| G7 | Oct 16 | Invoicing live |
| G11 | Oct 18 | Stripe subscription billing live |
| G8 | Oct 24 | Phase A complete |
| G9 | Oct 25 | Phase B complete |
| G10 | Oct 29 | Second contractor tenant live |
| G12 | Oct 31 | MVP LAUNCH |

**Field pilot day 1: Oct 7.**

## The four that are Jacob's alone

| When | What | Gate it feeds | Cost |
|---|---|---|---|
| now | Catalogue browser check-out, 12 steps | G2 | ~1 hr |
| Sep 25 | Stripe account under the StructTech entity | G11 | ~30 min + days-to-weeks verification |
| Sep 30 | SPF repair at Wix (two `v=spf1` at the apex = PermError, RFC 7208 §4.6.4) | A6.1 | ~15 min + TTL |
| Oct 1 | **REAL CREW ACCOUNT. No account, no pilot.** | G6 | ~2 hrs |

## Measured against the tracker, 2026-09-23

Counts are `roadmap_items` in the Build module's project, read today. They measure what the tracker says,
which is not the same as what a screen does (§7.1 rule 17) — a spine can be shipped while the roofer still
cannot reach it.

| Gate | Status today | Measurement |
|---|---|---|
| **G4 · Sep 20 · A3 Standards accepted** | **MISSED, 3 days ago, and not previously raised** | Standards & checklists: **0 shipped, 7 planned** of 7 |
| G2 · Sep 10 · A2 accepted | Contested | Materials & purchasing: **0 shipped, 2 in progress, 2 planned**. `docs/A2_ACCEPTANCE_EVIDENCE_2026-09-09.md` exists, so "accepted" may be a controller judgement the tracker never recorded — one of the two is wrong |
| G3 · Sep 14 · Platform debt clear | Contested | Platform / multi-tenant: 1 planned, 0 shipped |
| **G5 · Oct 6 · A4 Field accepted** ⚠ | **At risk: 13 days for 8 items, none shipped** | Field (crew): **0 shipped, 1 in progress, 7 planned** |
| G6 · Oct 13 · pilot closes ⚠ | Blocked on Jacob's Oct 1 item | No real crew account exists; the only `field` login is the synthetic one in the disposable tenant |
| G7 · Oct 16 · Invoicing live | At risk | Invoicing & payments: 0 shipped, 5 planned |
| G11 · Oct 18 · Stripe billing live | Blocked on Jacob's Sep 25 item | Nothing in the schema for subscriptions; Stripe account not yet created |
| G8 · Oct 24 · Phase A complete | At risk | Phase A: **6 shipped, 9 in progress, 27 planned** (42). 31 days of items in 31 days |
| G9 · Oct 25 · Phase B complete | At risk | Phase B: 0 shipped, 4 planned — one day after G8 |
| G10 · Oct 29 · second tenant live | Not started | No second contractor tenant exists; the only extra org is the disposable test tenant |
| G12 · Oct 31 · MVP LAUNCH | Follows G8–G11 | — |

**The one that is due in two days:** Sep 25, the Stripe account. Its verification is *days to weeks*, and
G11 is Oct 18 — so a Sep 25 start is already the last safe date, not a comfortable one.

**Raised now, per the rule at the top of this file:** G4 has slipped 3 days with nothing shipped against it,
and the same 7 Standards items are the ones A4.3's QC work depends on. Cause: Field and signing work took
every Track S and Track U session since Sep 14. Cut proposed: accept A3 on the two items the pilot actually
needs (the QC checklist, now built, and the required-photo rule) and move the remaining 5 to Phase B, or move
G4 to Oct 3 and say so.
