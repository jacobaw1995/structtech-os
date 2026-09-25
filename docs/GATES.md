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
| G4 | ~~Sep 20~~ → **November** | A3 Standards accepted — **CUT 2026-09-13** |
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
| **G4 · A3 Standards accepted** | **CUT. DEFERRED TO NOVEMBER** — controller decision 2026-09-13, recorded here 2026-09-25. Not a miss. See below. | Standards & checklists: **0 shipped, 7 planned** of 7. Verified independently 2026-09-25 |
| G2 · Sep 10 · A2 accepted | Contested — **re-derived from live objects 2026-09-25**, see §G2 below | Materials & purchasing: **1 shipped, 2 in progress, 3 planned** (6 rows). **MY 2026-09-23 FIGURE IN THIS TABLE WAS WRONG** — it said 0 shipped and 4 rows. Three of the six rows are A2.4/A2.5/A2.6, which LEFT A2 on 2026-08-29, so the section is not A2's denominator |
| G3 · Sep 14 · Platform debt clear | Contested | Platform / multi-tenant: 1 planned, 0 shipped |
| **G5 · Oct 6 · A4 Field accepted** ⚠ | **At risk: 13 days for 8 items, none shipped** | Field (crew): **0 shipped, 1 in progress, 7 planned** |
| G6 · Oct 13 · pilot closes ⚠ | Blocked on Jacob's Oct 1 item | No real crew account exists; the only `field` login is the synthetic one in the disposable tenant |
| G7 · Oct 16 · Invoicing live | At risk | Invoicing & payments: 0 shipped, 5 planned |
| G11 · Oct 18 · Stripe billing live | Blocked on Jacob's Sep 25 item | Nothing in the schema for subscriptions; Stripe account not yet created |
| G8 · Oct 24 · Phase A complete | At risk | Phase A: **6 shipped, 9 in progress, 27 planned** (42). 31 days of items in 31 days |
| G9 · Oct 25 · Phase B complete | At risk | Phase B: 0 shipped, 4 planned — one day after G8 |
| G10 · Oct 29 · second tenant live | Not started | No second contractor tenant exists; the only extra org is the disposable test tenant |
| G12 · Oct 31 · MVP LAUNCH | Follows G8–G11 | — |

**The one that is due TODAY (2026-09-25):** the Stripe account. Its verification is *days to weeks*, and
G11 is Oct 18 — so a Sep 25 start is already the last safe date, not a comfortable one.

## G4 — CUT, NOT MISSED. Controller decision 2026-09-13; recorded 2026-09-25.

**Recorded on the day it was told to the executor, with the date it was actually made, because those
are two different dates and only one of them is the decision.** On 2026-09-23 this file raised G4 as
*"MISSED, 3 days ago, and not previously raised."* That was the honest reading of what the executor
could see, and it was wrong about the world: **the cut was made on 2026-09-13, seven days before the
gate.** A3 Standards & checklists moves to **November**, after the field pilot.

**This is the deadline-side twin of the count rule.** A gate cut in the controller's own notes and not
in a file the executor can read is, from here, indistinguishable from a gate being missed — and the
executor will report it as missed, correctly and uselessly. **A cut is recorded where the executor
reads it, on the day it is made, or it is not a cut yet.**

**THE TRIPWIRE: CLOSED, NOT FIRED.** The rule at the top of this file — *any gate projected to slip
more than 3 days is raised the day it becomes visible* — did not fail here and did not fire. It
could not: there was nothing to project. A cut gate has no slip. Evaluated on its own terms, the
tripwire is **not-fired**, and what actually happened on 2026-09-23 is the second-best outcome: the
executor raised a gate it could not know was cut, which is how the cut reached this file at all.

**THE COUNT, VERIFIED BY THE EXECUTOR RATHER THAN ACCEPTED (2026-09-25).** The directive said zero
standards objects exist in the database. **It is zero, and the zero was looked for on four axes**, not
one (§7.1 RULE 16 — a sweep is only as wide as the axis it was written on):

| Axis | What it asked | Result |
|---|---|---|
| 1 · object NAME | tables/views matching `standard\|checklist\|documentation_item\|phase\|overlay\|supersed` | **0**, out of 100 public tables |
| 2 · COLUMN vocabulary | any table carrying `layer`, `supersedes_id`, `provenance`, `owner_org_id`, `phase`, `language` — A3.1's own field list | **1 hit, a false positive**: `roadmap_items.phase`, which is the Build Tracker's Phase A/B, not A3.1's install phase |
| 3 · FUNCTION name | `standard\|checklist\|documentation_item\|supersed\|bilingual` | **1 hit, a false positive**: `update_intake_checklist_field`, the CRM lead intake checklist on `deals.intake_checklist` |
| 4 · CHECK-constraint VALUES | any constraint containing `baseline\|overlay\|superseded\|disputed\|tear-off\|dry-in\|closeout` — A3.1's state and phase vocabularies | **0** |

**AND WHAT THOSE FOUR AXES CANNOT SEE, stated with the result.** They are keyed on A3's *own*
vocabulary, so they are blind to a checklist that exists under a different name — and one does.
**`qc_items` is a live checklist table** (X-W1.20, migration `20260922004806`, three rulings applied
`20260922221943`), with an attester allow-list, a first-attestation record and photo evidence
resolvable against a check-in. It is **A4.3's**, not A3's, and it is the "QC checklist, now built"
that the 2026-09-23 cut proposal named. So: **zero A3 objects, and not zero checklist objects.** A
sweep that reported "0 checklist objects" would have been correct on its axis and false about the
database.

## G2 — re-derived from live objects, 2026-09-25

See the day's report. The short version, because a gate file should carry the verdict and not only
the contest: **§5's A2 is six tasks (A2.0 · A2.0b · A2.1 · A2.1c · A2.2 · A2.3), all marked ✅ CLOSED
in the directive, and the Build Tracker has no row for four of them.** The tracker's
"Materials & purchasing" section is not A2's denominator: three of its six rows (shop stock, delivery
receipt, Material Matrix) are A2.4/A2.5/A2.6, which **left A2 on 2026-08-29 as unspecified or gated**.
Measured against the live database rather than against the 2026-09-09 acceptance document, **two of
A2's own *Done when* clauses have never happened in production** — `products` holds **0 rows** and
`estimate_line_items.product_id` is non-null on **0 of 22**, so "a tenant builds a catalog and prices
an estimate line from it" is proved as a *capability* and unexercised as a *fact*; and
`organizations.policy` is `{}` on **all 4** tenants, so A2.3's block-when-opted-in clause has never
been exercised either. **A2.2's *Done when* names a function that no longer exists**
(`generate_take_off`, dropped by `20260916214814`) and a shape its replacement contradicts.

**Raised 2026-09-23, and now SUPERSEDED by the cut above — kept verbatim because the record of what
the executor could see matters:** *"G4 has slipped 3 days with nothing shipped against it, and the
same 7 Standards items are the ones A4.3's QC work depends on. Cause: Field and signing work took
every Track S and Track U session since Sep 14. Cut proposed: accept A3 on the two items the pilot
actually needs (the QC checklist, now built, and the required-photo rule) and move the remaining 5 to
Phase B, or move G4 to Oct 3 and say so."* The controller's actual decision, made ten days before this
was written, was broader than the proposal: **all seven move, to November.**

**The Sep 25 item is due TODAY.** The Stripe account under the StructTech entity. Its verification is
*days to weeks* and G11 is Oct 18, so this was already the last safe date when this file was written
two days ago. It is nobody's but Jacob's and no executor session can advance it.
