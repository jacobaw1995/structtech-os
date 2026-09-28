# THE JOB SCOPE SHEET — AUTHORITATIVE SPEC

**REVISION 2, 2026-09-28.** Revision 1 was written from the controller's reading of the PDF and
was wrong in ten places. Track S found all ten by reading the source; every correction below is
the PDF winning. **Revision 1's structure table, section count, R5 and R7 should be treated as
withdrawn, not merely amended.**

**Sources, in precedence order — the first two are Jacob's, this file is not:**
1. `docs/reference/BMR_Job_Scope_Initial_Inspection.pdf` — 5 pages. **Wins over everything here.**
2. `docs/reference/BMR_TYPE_CODES.md` — the 17 codes and the job-number format, canon.
3. `docs/SCOPE_SHEET_SHAPES.md` — Track S's measured shapes. §6 is the list of ten.

**Decision of record, Jacob, 2026-09-28: BUILD IT NOW.** Pilot 2026-10-07 → ~2026-10-19;
G12 → ~Nov 12. Re-dated in `docs/GATES.md`. Recorded as a cost, not argued.

---

## 0 · THE SIZE OF IT, MEASURED

The PDF names StructTech OS three times. **It was written against this system**, and what ships
today is a rough first fifth of it.

| | |
|---|---|
| Configured fields | **38** across 6 stages, 11 vital on New Lead |
| Fields that map to the PDF | **25 of 38** |
| **PDF inputs with no field at all** | **102 of 127** — the build covers one input in five |
| Fields with no PDF home | 13 — but 6 are CRM chrome, 3 pre-visit duplicates, 4 CRM concepts |
| Deals that can distinguish *declined* from *never reached* | **0 of 200. On all six gated sections.** |

127 counts §5 cell-wise; 109 counts it row-wise. **Those two readings of one table are the whole
difference**, which is itself the finding — §5 is the hard part.

---

## 1 · THE STRUCTURE — corrected

**Thirteen numbered blocks plus two unnumbered. Not twelve sections.**

| # | Section | Gate |
|---|---|---|
| — | **Header** | **Site inspection · Discovery call** — sets what "complete" means for everything after it |
| 1 | Client and job | always |
| 2 | Measurement reports | always |
| 3A | Roof | **Price a roof on this job?** No → skip all roof detail |
| 3B | Soffit and fascia | **Soffit and fascia · Soffit only · Fascia only · No** |
| 3C | Siding | Yes / No |
| 3D | Gutters and gutter guards | **Gutters and guards · Gutters only · Guards only · No** |
| 3E | Snow rail | Yes / No |
| 3F | Other | Yes / No |
| 4 | By others / not included | always |
| 5 | Roof conditions | always · **"PERRY'S FIELD MAPS"** |
| 6 | Site and access | always |
| 7 | Notes | always — **two note boxes** (FOR ROBERT · FOR CREW). The SHEET has four handlers; §7 has two — see R7 |
| 8 | **Packet** | — · headed **OFFICE — ISAAC** |
| — | **Automatic print list** | 8 rules — **this is where R5 lives** |
| — | **Job numbering** | `MM-YY-###-LastName-TYPE-##`, assigned when sold |

---

## 2 · THE RULINGS

### R1 — A SKIPPED SECTION IS AN ANSWER. AND SO IS A BLANK.
**Revised, and the revision is the PDF's, not mine.** Page 1 instructs: *"Never guess colors or
products — leave the line blank."* **The source instructs the blank.** So a blank is a sanctioned
answer on this sheet, and anything rendering it as *incomplete* contradicts the instruction
printed above it.

**THE COMPLETION METER COMES OFF THIS SHEET.** The live Lead Control Center shows `PROGRESS 100%`
and `14/14`. A document whose own rule is that some lines stay empty cannot carry a percentage:
it declares a sheet finished when the inspector correctly refused to guess, and unfinished when
he did exactly as instructed.

**Four states, and the fourth must be reachable, not merely handled:**
`not on this job` · `on this job, not yet filled` · `on this job, filled` · `could not be read`.

**Measured: 0 of 200 deals can express the first one.** There is no key anywhere in
`intake_checklist` that could record a decline — all eight top-level keys across 200 deals are
values or legacy stamps. A filled section proves somebody filled it; an empty one proves nothing.

**Shape (S's, accepted):** a table, `scope_section_answers`, one row per (deal, section), with
`decided_by` / `decided_at`, because a decline is a decision. **Reachable from the TABLE, not
only through a function** — **8 of 8 live members** reach `schedule_blocks` directly (re-measured
2026-09-28: its only SELECT policy is `org_id in (select my_org_ids())`, with **no capability
test at all** — the earlier "4 of 5" predates three memberships and understated it), so a fact only
a function can produce is a fact half the readers cannot see. **`unreadable` is produced by the
reader and never stored** — a stored row claiming a request failed is a claim about something
already over.

### R2 — THE GATE REVEALS AND HIDES. IT NEVER BLOCKS A SAVE. (SCOPE §2.8)
A flip after filling **keeps and marks**; it never deletes. On a roof the commonest cause of a
flip is a mis-tap and the second is learning something new.

**`reveals` IS A LIST OF GROUPS, NOT A BOOLEAN** — U's correction. 3B is four-way and the sheet
says *"Soffit only → skip the fascia lines. Fascia only → skip the soffit lines."* A four-option
gate reveals a **subset**; all-or-nothing cannot express it. 3D is the same shape and carries its
own printed anti-inference rule: **"Guards are not included just because gutters are."** That
rule is explicit in the source and must not be optimised away.

**AND THE GATE IS AN INPUT TO PRICING, OR R2 AND R5 FIGHT.** `lib/estimating/scope-line-items.ts`
turns filled scope fields into estimate line items. Lines that are *kept and marked* after a
"No" are still filled, so they become **priced lines for work the client declined**; the existing
`unmapped` guard catches the opposite direction and does not help. **"Kept and marked" means
excluded from pricing.**

### R3 — THE 17 TYPE CODES ARE TENANT VOCABULARY. CANON IS `docs/reference/BMR_TYPE_CODES.md`.
They live in `tenant_modules.config`. **They are not products; they do not touch `products` or
any `wh_*` table.** Catalog and Material Matrix remain out of this build.
A code carries its label; the sheet stores the code, the screen shows the words; an unrecognised
code is **shown, not guessed at**.

**Two vocabularies, unresolved and Jacob's:** 14 configured roof types against 17 system codes —
not a rename, not a superset. **A job routinely carries more than one code**; any model assuming
one per job is wrong before it is built.

### R4 — AN UNRESOLVABLE REFERENCE IS A NOTE, AND MUST READ AS ONE.
**Corrected: CompanyCam appears FOUR times in the PDF, not two**, and the two Revision 1 missed
are the ones the question turns on.

| Where | Field | Verifiable |
|---|---|---|
| §1 | **CompanyCam PROJECT NAME** | **Yes, cheaply** — `GET /projects?query=` filters by name |
| §2 | Hand measured — sketch location | No — free prose |
| §5 | Photo ref × 6 rows | No |
| §6 | Site hazards — photo ref | No |

**The project name is its own field type** (X's revision, accepted): **one reference with a
future, eight without** — counting slots, the sheet has nine (§1 project name · §2 sketch
location · §5's photo-ref column × 6 rows · §6 site hazards) in four places. *(Revision 2 said
seven; that is neither the slot count, 8, nor the place count, 3.)*

**The seven stay notes, and the reason is about people, not endpoints.** CompanyCam identifies
photos by a numeric id it assigns. An inspector on a roof writes a human label — *"decking, north
slope"* — and there is no attribute on a CompanyCam photo that a hand-written label can be matched
against. No endpoint closes that gap.
**And a resolved reference still is not evidence:** confirming a project exists says nothing about
whether a photo of that decking row exists or shows decking.
So: **no thumbnail, no "photo attached", no icon, no tick, no count.** Nothing on the page may
claim a photo exists. *(Cost, recorded: paid plan, hand-rotated tokens that die silently, OAuth
per tenant for multi-tenant, and a v2 deprecation notice for early 2027.)*

### R5 — THE AUTOMATIC PRINT LIST. DERIVED AT READ TIME, STORED NOWHERE.
**Revision 1 quoted 2 rules. There are 8** — an always-on row plus seven conditionals, about
thirteen document lines, on page 5. That list *is* R5's specification.

**2 of 8 are derivable today.** The other six are each blocked on a gate answer with no field.
Measured across every column, every config key and every `intake_checklist` value on 200 deals:
tear-off · dumpster · FirstMate · Hover · RoofScope · EagleView · snow rail · gutter guard →
**0 columns, 0 field keys, 0 deals.**

**A stored derivation is a mirror and this build has spent a month deleting mirrors.**

**AND THE CONSUMER NAMED IN REVISION 1 WAS THE WRONG ONE** (S's finding, accepted).
`production_packets.callouts` models *a place plus what goes there*, for a crew scanning from a
truck. A print line is *a document plus a quantity plus the rule that fired*, read by the office.
Same container, different readers, different verb. **R5 renders as its own section**, each line
naming the rule that produced it.

### R6 — NO PRICES ON THIS SHEET.
Bold on page 1 of the source, and it matches A2.1's no-re-entry rule. The scope feeds the
estimate; the estimate holds money. Confirmed independently from the PDF, not inherited.

### R7 — THE SHEET CHANGES HANDS. "FILLED ON A ROOF" IS TRUE OF PART OF IT.
**Revision 1 said this was one person's document. It is four.** *"Give to Scott with 'Start
scope'"* · *"Scott pulls roof geometry from the measurement report"* · **§7 FOR ROBERT
(Estimator)** · §8 **OFFICE — ISAAC** · §5 **PERRY'S FIELD MAPS**.

**Scott is expected to fill fields the inspector deliberately leaves blank** — roof area, facets,
pitch. So a blank is not only sanctioned (R1); on some lines it is a **handoff**. The screen must
know **whose turn it is**, which is a different question from who may edit it.

**SCOPE §2.4 still governs the inspector's part:** 375px first, ≥56dp targets, one thumb column,
outdoor mode, both themes.
**The baseline it must beat, measured 2026-09-27 and re-confirmed 09-28:** 2 taps minimum per
field · 11 vital fields on New Lead · **22+ taps and 11 server round trips for one screen** · four
different commit behaviours. **§5 alone is 24 cells — 48 taps before a word is typed**, for a page
of paper an inspector fills with a handful of strokes.

### R8 — THE EXISTING DEALS DO NOT BREAK. *(Revision 1's facts were wrong; the principle stands.)*
**Corrected by U, measured:** `existing_roof_type`, `roof_type_requested` and
`remodel_or_new_construction` are **columns on `deals`**, not `intake_checklist` keys — **0 deals
carry them in the jsonb.** Counts are **167 / 179 / 178 against 200 deals**, of which **171** have
a non-empty `intake_checklist`. Revision 1 said 166/178/177 against 199 and pointed at the wrong
store; a migration written from it would have moved nothing that exists.

**What the jsonb actually holds:** `legacy_last_contacted_at` (168) · `main_issue` (7) ·
`estimate_inputs` (6) · `site_visit_scope` (5) · `site_visit_scheduled_at` (4) ·
`legacy_proposal_sent_at` (3) · `general_notes` (1) · `key_decision_maker` (1).
**`site_visit_scope` holds 15 fields, not 14.**

**Its readers, and what a gated sheet does to each:** `scope-line-items.ts` (breaks — see R2) ·
`command-center.ts` (renders every configured field, no concept of a gate) · `scope-fields.ts` ·
`crm/actions.ts → update_intake_checklist_field` (the only writer, and **the only database object
that reads the jsonb at all** — 0 views, 0 policies, 0 indexes) · `intake-checklist.ts`.

### R9 — TEAR OFF ⇒ DUMPSTER IS A DERIVATION WITH A RECORDABLE OVERRIDE. NOT A CONSTRAINT.
S's three grounds, accepted whole:
1. **The excluded case exists and the sheet provides for it.** §4 is *"work the client or another
   contractor will do"*. A client who hauls their own debris is a tear-off with no dumpster. A
   CHECK makes that unrepresentable and refuses the save — software telling a man on a roof that
   what he is looking at is impossible. §2.8 and R2 both forbid it.
2. **The print list says "Dumpster OR tear-off = Yes."** That disjunction is redundant unless they
   are two independent facts.
3. **Storing the derived Yes is the silent-answer defect closed on 2026-09-25** — the same shape
   as `p_quantity numeric DEFAULT 1`.

So: tear-off Yes stores nothing and the screen reads *"Dumpster: Yes — because tear-off is Yes"*;
tear-off No asks, with R1's states; **the override carries a reason**, because a dumpster order
that does not print leaves somebody downstream needing to know why.

### R10 — §5 IS NOT A UNIFORM GRID, AND THE PAPER ASKS LESS THAN REVISION 1 DID.
**Only 2 of 6 rows carry a FOUND pair** — decking concerns, and leaks / problem areas. The other
four have an empty found cell: *write what you saw*, three with the unit pre-printed (OSB sheets ·
roof vents · pipe boots), one pre-labelled *"Flashing notes"*. **Column applicability is per row.**
Building a uniform grid puts four questions on a roof the paper never asked.

**And the words are "None seen", not "None."** It does not claim there are none — only that none
were seen from where the inspector stood. **That distinction was in Jacob's paper before this
build wrote it down anywhere.** Adopted verbatim.

---

## 3 · ACCEPTANCE

**RULE 17 governs: accepted on the rendered screen, or not accepted.** Every defect found in the
browser on 2026-09-20 sat behind correct policy.

**One sentence: Jacob fills this sheet on a phone, standing up, for a real roof, and it is faster
and clearer than the paper** — against R7's measured baseline.

Every sweep runs its positive control first and records that it fired (rule 20), states its axis
and what that axis cannot see (rule 18), and carries the container every count was counted in.

---

## 4 · CORRECTIONS MADE TO REVISION 2 BEFORE IT WAS COMMITTED

Track S, 2026-09-28, checking this file against the PDF and `docs/SCOPE_SHEET_SHAPES.md` as
instructed. **Four factual corrections; no judgement was touched.**

1. **§1 table, §7 — "three audiences, not two" → two.** §7 has exactly two note boxes, FOR ROBERT
   and FOR CREW. What has four is the SHEET's readership, which is R7's point and is correct
   there. The structure table had merged the two claims.
2. **R1 — "4 of 5 live members" → 8 of 8.** Re-measured: `schedule_blocks`' only SELECT policy is
   `org_id in (select my_org_ids())` with **no capability test**, and there are 8 memberships. The
   argument gets stronger, not weaker: it is not most readers, it is all of them.
3. **R4 — "seven without" → eight.** Nine reference slots in four places; one verifiable.
4. **R7 — "§5 alone is 30 cells — 60 taps" → 24 cells, 48 taps.** 30 counts the pre-printed ITEM
   column as an input. It also contradicted **§0 of this same file**, whose 127 was computed on 24
   (6 rows × 4 data columns); at 30 the total would be 133. R10's own reading agrees with 24.

**Verified and correct, not changed:** R8's replacement counts — **167 / 179 / 178 against 200
deals, 171 with a non-empty `intake_checklist`, and 0 of the three in the jsonb** — re-measured
exactly. So is *"the only database object that reads the jsonb at all"*: **1 function
(`update_intake_checklist_field`), 0 views, 0 policies, 0 indexes.** My own 166/178/177-against-199
was right for 2026-09-25 and was made stale by golden path run 1's deal, not wrong.

**And R2's new pricing claim is CONFIRMED by reading the code, not accepted.**
`generateScopeLineItems` (`src/lib/estimating/scope-line-items.ts:95`) iterates every configured
`site_visit_scope` field and skips only on: not filled · no pricing config (→ `unmapped`) ·
`generates: false` · non-numeric (→ `unparseable`). **There is no concept of a section gate
anywhere in it.** A field that is filled and then marked *"not on this job"* becomes a priced
line for work the client declined. **"Kept and marked" must mean excluded from pricing**, and
today nothing implements that.
