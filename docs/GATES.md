# Gate calendar

**Any gate projected to slip more than 3 days is raised the day it becomes visible, with the cause named and the cut proposed.**

Recorded in the repo on 2026-09-23 by Track S, at the controller's instruction. Until today these dates lived
only in the controller's project docs, which no session can read — so **every date in every directive for
three weeks was unfalsifiable from the executor's side**, while every count in the same directives was
written to be contradicted. A deadline the executor cannot read is a deadline that cannot be contradicted.
From now on dates get contradicted the same way counts do, and the measurements are below the table.

### THE DAY LABEL IS NOT THE MIGRATION STAMP. 2026-09-28.

Three directives were issued under the header **Tuesday 2026-09-29**. New York was
**Monday 2026-09-28**. All three tracks contradicted the header independently; Track S measured
the mechanism live in one minute — `current_date` = `2026-09-29`, `(now() at time zone
'America/New_York')::date` = `2026-09-28`. The directives' own *eight working days* count is
correct **from Monday**, so the body contradicted its own header. Those three directives are
hereby **re-labelled Monday 2026-09-28**; the work in them was Monday's and was done Monday.

**Migration filenames stay UTC and are not corrected.** `20260929025035_special_trip_log` and
`20260929025510_member_capability_refusal_hints` were applied on Monday New York time under a
Tuesday UTC stamp. That is the convention working as intended: a migration filename is an
ordering key, not a day label. Renaming an applied migration would break ordering to fix
nothing. **Day labels are New York. Ordering keys are UTC. They are allowed to disagree.**

## The gates

**⚠ REVERTED 2026-09-28 22:21 EDT. THE ORIGINAL DATES STAND.**
Jacob found a workaround for BMR's job scope sheet, so it is **shelved, not cancelled**, and
the original schedule resumes. Today's two re-datings — pilot → Oct 19, then Oct 26 — are
**withdrawn**. Recorded rather than deleted: the calendar moved twice and back in one day.
**What it actually cost is Monday 2026-09-28** — that day's planned Field work did not happen
and does not come back.

**The revert is clean for a scope reason worth stating.** The core system is **StructTech's**,
not any tenant's; a tenant brands and configures its own. So the BMR job scope sheet was always
**tenant configuration**, never core — which is why taking it off the critical path costs the
platform nothing. What Track U built on 09-28 (the gate, the type-code picker, the per-row
table, the external-reference note) is the **capability**, and capabilities are core.

| Gate | Date | What it is |
|---|---|---|
| G2 | Sep 10 | A2 Materials & Purchasing accepted |
| G3 | Sep 14 | Platform debt clear |
| G4 | ~~Sep 20~~ → **November** | A3 Standards accepted — **CUT 2026-09-13** |
| G5 | **Tue Oct 6** | A4 Field Execution accepted ⚠ TRIPWIRE |
| G6 | **Tue Oct 13** | Field pilot closes ⚠ TRIPWIRE |
| G7 | **Fri Oct 16** | Invoicing live |
| **G11** | **BLOCKED — NO DATE** | Stripe subscription billing live. **Unchanged by the revert.** |
| G8 | **Sat Oct 24** | Phase A complete |
| G9 | **Sun Oct 25** | Phase B complete |
| G10 | **Thu Oct 29** | Second contractor tenant live |
| G12 | **Sat Oct 31** | MVP LAUNCH |

**Field pilot day 1: Wed Oct 7. Eight working days from this revert.**

### G11 STAYS BLOCKED. The revert does not restore its date.

Its Oct 18 was withdrawn this afternoon on Track S's challenge, and that challenge had nothing
to do with the scope sheet: **G11's critical path is a business verification that has not
begun.** Restoring the date because the calendar snapped back would restore a date for
something that still has not started. **It gets one the day the Stripe account exists, counted
forward from there.** Due Sep 25; six days late.

### The scope sheet is SHELVED, and what survives is written down

Retained in the repo and off the critical path: `SCOPE_SHEET_SPEC.md` (revision 2, corrected
against the PDF in ten places), `SCOPE_SHEET_SHAPES.md`, `reference/BMR_TYPE_CODES.md` as
Jacob's canon, and the source PDF.

**The measurements are the part worth keeping, because they stay true whenever this resumes:**
the build covers **25 of 38 configured fields**, and **102 of 127 PDF inputs have no field at
all**; **0 of 200 deals can distinguish "the client declined this" from "nobody got to it"**,
on all six gated sections; and `lib/estimating/scope-line-items.ts` has **no concept of a
gate**, so a section marked *not on this job* would still price its lines.

### G5 CUT — ACCEPTED 2026-10-01, and the ruling that unblocked it

**THE §2.8 RULING, verified against `docs/SCOPE.md` before being recorded.** The controller's
reading survives the file. §2.8 forbids *"prevent[ing] navigation or data entry based on the
completeness or order of other data"* and names its own escape hatch, verbatim: *"Where a tenant
genuinely wants enforced process, that is **per-tenant config, defaulted OFF**
(`enforce_stage_gating`), never the shipped default."*

> **A "never" and a "must refuse" are reconciled by a SWITCH, not by a winner.** The Done-when
> tests that the refusal EXISTS and fires when a tenant turns enforcement on. The default tests
> the principle. **Fifteen days were spent treating them as a contest.**

**A4.6's refusal was built the same day the ruling landed** — `20261002025107_crew_vehicle_refusal`,
following the shape set three days earlier by `20260929153659_crew_scoped_field_jobs`.

**THE CUT, as proposed on 2026-09-30 and accepted:**

| | items |
|---|---|
| **KEEP in G5** | **A4.2** special trips · **A4.6** crew model · **A4.7** office upload |
| **MOVE to November** | **A4.1** daily objective · **A4.3's blocking clause** · **A4.4** packet v2 · **A4.5** acknowledgment · **A4.8** adoption |

**Cause on the record:** *a stage whose Done-whens predate §2.8 being made non-negotiable,
measured against a product no crew has used.* **A4.8's reason is separate and unarguable: its
Done-when is a week of field use, and it cannot precede the pilot it measures.**

**What the kept three still need**, from the 2026-09-30 grading: `ORG_FILES_ENABLED` turned on
(an env var, not a build) · a real BMR crew with one person and one membership (Jacob's Oct 1
item) · and an office view of special trips. **A4.6's refusal is now built but has nothing to
fire on: crews, crew_people, crew_memberships and work_order_crew_assignments are all 0.**

### What did not move, and did not move back

**The real crew account is still Oct 1** — three days out again rather than twenty-five.
Re-measured 2026-09-28: BMR holds **2 members, 0 with role `field`**, and **0 rows in `crews`,
`crew_people` and `crew_memberships`** alike. **No account, no pilot.**

**`ORG_FILES_ENABLED`** — measured absent on 09-16, 09-23, 09-25, 09-27 and 09-28. **Twelve
days**, and it gates two readiness checks that cannot move without it.

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
| G11 · **NO DATE** · Stripe billing live | Blocked on Jacob's Sep 25 item | Nothing in the schema for subscriptions; Stripe account not yet created |
| G8 · Oct 24 · Phase A complete | At risk | Phase A: **6 shipped, 9 in progress, 27 planned** (42). 31 days of items in 31 days |
| G9 · Oct 25 · Phase B complete | At risk | Phase B: 0 shipped, 4 planned — one day after G8 |
| G10 · Oct 29 · second tenant live | Not started | No second contractor tenant exists; the only extra org is the disposable test tenant |
| G12 · Oct 31 · MVP LAUNCH | Follows G8–G11 | — |

**The one that is overdue:** the Stripe account, due **Sep 25** and not started. Its verification is
*days to weeks*. **G11 no longer carries a date precisely because this has not begun** — see
*G11 carries no date* above. *(This paragraph read "G11 is Oct 18 — so a Sep 25 start is already the
last safe date" when it was written on 2026-09-25. There is no last safe date to name any more;
the gate now waits on the account rather than the account racing the gate.)*

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

**The Sep 25 item is OVERDUE.** The Stripe account under the StructTech entity. Its verification is
*days to weeks*. **G11 has carried no date since 2026-09-28** — it gets one the day the account
exists, counted forward from there. It is nobody's but Jacob's and no executor session can advance
it. *(Written on 2026-09-25 as "due TODAY … G11 is Oct 18"; corrected here rather than left to
contradict the table above it.)*
