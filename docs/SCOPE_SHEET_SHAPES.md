# The job scope sheet — measurement and shapes

Track S, **2026-09-28**, read against `docs/reference/BMR_Job_Scope_Initial_Inspection.pdf`
(5 pages) and the live database. **No migration was applied today.** Measurement and shape only,
per the directive: a migration written before Task 1's numbers exist is a migration written
against the wrong count.

**The PDF wins over `docs/SCOPE_SHEET_SPEC.md`, and it was read page by page rather than taken
from the spec.** Where the two differ, the differences are listed in §6.

---

## 1 · TASK 1 — THE CONFIG, MEASURED

### 1.1 Containers

| container | count |
|---|---|
| `lead_control_center.fields` defined | **38** |
| `command_stages` | **6** |
| `checklists` | **2** — `intake_call` (14 field_keys) · `site_visit_scope` (**15**, not 14) |
| `lead_type_options` | 4 |
| vital fields on **New Lead** | **11** |
| tenants carrying the config | 2 — BMR and the synthetic tenant, **md5-identical** (`8cd45bcc…`), so per-tenant divergence is **0** |

**The directive's 38, its 6 stages and its 11 vital on New Lead are all CORRECT.** The spec's
*"the live Site Visit Scope Checklist holds 14 fields"* is **off by one: it is 15.** The
fifteenth is `scope_notes`.

**Vital fields per stage:** New Lead 11 · Site Visit 5 · Scope 4 · Quote 5 · Negotiating 4 ·
Closed 2.

**The field-type vocabulary that exists today — ten types, and none of them branches:**
`number` 10 · `readonly` 6 · `select` 6 · `text` 6 · `textarea` 4 · `roof_types` 2 · `address` 1
· `datetime` 1 · `email` 1 · `phone` 1.

### 1.2 The PDF, counted

**The spec says twelve sections. The PDF has thirteen numbered blocks and two unnumbered ones.**
Sections 1 · 2 · 3A · 3B · 3C · 3D · 3E · 3F · 4 · 5 · 6 · 7 · **8 (Packet)**, plus **Automatic
print list** and **Job numbering**. The spec's table stops at 7 and omits section 8 and both
unnumbered blocks — which matters, because **section 8 and the automatic print list are where
R5 actually lives.**

**Input count: 127**, counting §5's table cell-wise (6 rows × 4 data columns = 24), or **109**
counting §5 as 6 rows. **The directive's "on the order of 120" is right, and the two ways of
counting the one table are the whole spread.** Stated with its container, as required.

| block | inputs | covered by a field today |
|---|---|---|
| header (DATE · INSPECTION OR CALL · DONE BY) | 3 | 0 |
| §1 Client and job | 10 | **6** |
| §2 Measurement reports | 5 | 0 |
| §3A decide (roof? · tear off · dumpster) | 3 | 0 |
| §3A roof details | 17 | **11** (by 9 fields) |
| §3B Soffit and fascia | 12 | **2** |
| §3C Siding | 8 | 0 |
| §3D Gutters and guards | 10 | **2** |
| §3E Snow rail | 5 | 0 |
| §3F Other | 4 | 0 |
| §4 By others / not included | 2 | 0 |
| §5 Roof conditions (table) | 24 cells | **3** |
| §6 Site and access | 12 | 0 |
| §7 Notes | 2 | **1**, audience unresolved |
| page-4 footer (COMPLETED BY · DATE COMPLETED · GIVEN TO SCOTT) | 3 | 0 |
| §8 Packet | 4 | 0 |
| Job numbering | 1 | 0 |
| page-5 footer (PACKET ENTERED BY · DATE ENTERED) | 2 | 0 |
| **TOTAL** | **127** | **25** |

### 1.3 THE THREE NUMBERS, WITH THEIR CONTAINERS

> **FIELDS THAT MAP: 25 of 38.**
> **PDF INPUTS WITH NO FIELD: 102 of 127** — the build covers **one input in five**.
> **FIELDS WITH NO PDF HOME: 13 of 38.**

The 13 split three ways, and only one of the three is a gap:
- **6 are `readonly` CRM chrome**, not inputs at all — `stage`, `outcome`, `source`, `last_note`,
  `scope_status`, `visit_status`. A paper sheet has no reason to carry them.
- **3 are pre-visit duplicates** — `estimate_inputs.approx_roof_area`, `estimate_inputs.pitch`,
  `estimate_inputs.metal_type`. Each is a phone-call guess at a field the sheet asks properly
  later (`roof_area_sqft`, `pitch_slope_notes`, the TYPE CODE). **Two values for one fact, at two
  moments** — which is a real question for R8, not a mapping failure.
- **4 are genuine CRM concepts the sheet does not carry** — `lead_type`,
  `remodel_or_new_construction`, `site_visit_scheduled_at`, and `value`. **`value` is absent by
  design**, and the PDF says so in its own header: *"NO PRICES"*. R6 confirmed from the source.

### 1.4 The 25 that map — and four of them map badly

| config field | type | PDF |
|---|---|---|
| `first_name` + `last_name` | text | §1 CLIENT NAME — **two fields, one input** |
| `phone` · `email` · `key_decision_maker` | phone/email/text | §1, clean |
| `service_address` | address | §1 JOB ADDRESS — the PDF says *"Same as StructTech OS Service Address"* |
| `main_issue` | textarea | §1 MAIN ISSUE — and §5 row 3 says *"Pairs with Main issue"* |
| `general_notes` | textarea | §7 — **but §7 has TWO audiences and this field has none** |
| `existing_roof_type` | roof_types (14) | §3A EXISTING MATERIAL — the PDF says *"= StructTech OS Existing Roof Type"*, but its own options are **Shingles · Metal · Other (3)**, against our 14 |
| `roof_type_requested` | roof_types (14) | §3A TYPE CODE — **vocabulary mismatch: 14 roof types against 17 system codes.** Not the same list and not a rename |
| `roof_area_sqft` · `facets` · `pitch_slope_notes` · `roof_profile_style` | number/textarea/select | §3A, clean |
| `roof_color` | select | §3A **PANEL COLOR** — name drift, and §3A also has **TRIM COLOR** with no field |
| `drip_edge` | **text** | §3A **DRIP EDGE (LF)** — the sheet wants a length; the field takes prose |
| `ice_water_shield` | **text** | §3A — **one field for TWO inputs**: a 2-option choice (*eaves, valleys and penetrations* / *entire roof*) **and** a SQ FT number |
| `scope_notes` | textarea | §3A SCOPE NOTES / EXTRAS |
| `osb_replacement_sheets` · `roof_vents` · `pipe_boots` | number | §5 COUNT column, rows 2 · 5 · 6 — **the only three cells of that table the build can hold** |
| `soffit_lf` · `fascia_lf` | number | §3B |
| `gutters_lf` · `gutter_color` | number/select | §3D |

**And two §1 inputs are half-covered in a way the mapping hides:** `deals.company` and
`deals.billing_address` **exist as columns** but are not `lead_control_center` fields, so §1's
COMPANY and BILLING ADDRESS are storable and not askable.

---

## 2 · TASK 2 — R1, AND ITS BEFORE-MEASUREMENT

### 2.1 The measurement, on two axes, because one of them flatters the answer

**Axis A — "did anybody fill anything in this section?"**

| gated section | fields this build has | of 200 deals, none filled | at least one filled |
|---|---|---|---|
| 3A Roof | 9 | **195** | 5 |
| 3B Soffit / fascia | 2 | **197** | 3 |
| 3C Siding | **0** | **200** | 0 |
| 3D Gutters / guards | 2 | **197** | 3 |
| 3E Snow rail | **0** | **200** | 0 |
| 3F Other | **0** | **200** | 0 |

**Axis B — "can any deal distinguish *declined* from *never reached*?"**

> **200 of 200, on all six sections. NO.**

And it is not close. **There is no key anywhere in `intake_checklist` that could record a
decline.** The eight top-level keys across all 200 deals are `legacy_last_contacted_at` (168),
`main_issue` (7), `estimate_inputs` (6), `site_visit_scope` (5), `site_visit_scheduled_at` (4),
`legacy_proposal_sent_at` (3), `general_notes` (1), `key_decision_maker` (1) — every one of them
a value or a legacy stamp. **A filled section proves somebody filled it; an empty one proves
nothing, and there is no third thing to write.**

**State the axis with the result (RULE 18):** axis A is the one that produces 195/197/200 and it
answers a *weaker* question than R1 asks. Axis B is R1's question and its answer is a flat 200.
Three of the six sections cannot even be asked about, because the build has **zero** fields for
siding, snow rail and other.

**The container correction:** the directive says 199 deals. It is **200** — golden path run 1
created one on 2026-09-27 at 01:36 EDT in the synthetic tenant. And 200 is three tenants:
**BMR 191** · StructTech 7 · synthetic 2. For a BMR job-scope sheet the denominator is **191**.

### 2.2 THE SHAPE — reachable from the table, not only through a function

**The state lives in a column, not in the absence of one.** Every gated section gets one
answer row, and the answer is a value, never a silence:

```
public.scope_section_answers
  org_id            uuid    not null   -- RLS, my_org_ids()
  deal_id           uuid    not null
  section_key       text    not null   -- '3a_roof' … '3f_other', and the header's
                                       -- inspection_or_call, which is a gate too
  state             text    not null   -- 'not_on_this_job' | 'on_this_job' | 'unreadable'
  variant           text                -- the 4-way gates: 'soffit_and_fascia' | 'soffit_only'
                                       --   | 'fascia_only'; 'gutters_and_guards' | …
  decided_by        uuid                -- who said so
  decided_at        timestamptz
  primary key (deal_id, section_key)
```

**Why a table and not a jsonb key.** The directive's sentence — *"reachable FROM THE TABLE, not
only through a function"* — has a measured cause: **4 of 5 live members reach `schedule_blocks`
directly**, so a fact that only a function can produce is a fact half the readers cannot see. A
row in a real table with a real RLS policy is readable by a direct `select`, joinable, and
countable. A key buried at `intake_checklist->'3c_siding'->'state'` is none of those without a
function.

**The four states, and the fourth is reachable rather than merely handled:**

| state | what it means | how it is reached |
|---|---|---|
| `not_on_this_job` | a person decided. **This is the row that does not exist today** | the inspector answers No |
| `on_this_job` + no field values | on this job, not yet filled | the inspector answers Yes and moves on |
| `on_this_job` + field values | on this job, filled | the ordinary path |
| `unreadable` | **we could not ask.** Not a decision and not an absence | the read failed — the same third answer `fetchQcRows` gives, and it is a state of the READ, so it is produced by the reader and never stored |

**`unreadable` is reachable because the reader returns it, not because a row holds it** — a row
saying "unreadable" would be a stored claim about a request that already finished. That is the
distinction the QC read settled on 2026-09-21 and it transfers unchanged.

**`decided_by` / `decided_at` are on the row because a decline is a decision** — the same
standing as `first_actor_id` on `qc_items`. A section that goes from declined to on-the-job later
is a real change and writes a new decision; re-answering it with the same answer writes nothing
(§7.1 RULE 10, and Class B is now closed so the discipline is uniform).

**R2 is not violated:** this table records an answer. It does not disable, block or refuse.
Answering "No" and then filling siding lines anyway leaves both the answer and the lines, and the
screen says so.

---

## 3 · TASK 3 — R5, AND WHAT THE DERIVATION CAN ACTUALLY READ

**I ruled this way on callouts on 2026-09-25 and the ruling applies unchanged: derive at read
time, store nothing.** A stored packet line is a mirror, and a stale one is a confident sentence
about a roof that is no longer true.

**But the spec's two examples are 2 of SEVEN rules.** The PDF's page 5 carries an **AUTOMATIC
PRINT LIST** the spec does not mention, and it is the real specification of R5:

| when | print | qty | can we derive it today? |
|---|---|---|---|
| Always | 4 Site Inspection · 9 MASTER Scope Map · 10 CTP label | ×1 each | **YES** — no input needed |
| **Dumpster or tear-off = Yes** | 5 Dumpster order (W02) | ×1 | **NO** — neither field exists |
| Platform = FirstMate | 6 Page 1 ×6 · 7 Page 6 ×2 | as listed | **NO** — §2 does not exist |
| FirstMate **and** gutters on job | 8 FirstMate gutters page | ×2 | **NO** — needs §2 *and* the 3D gate |
| Roof = Yes | 9a Roof Measurements · 9b Trim · 9c Penetration · 9d Flashing SOP | ×1 each | **NO** — the 3A gate does not exist |
| Siding = Yes | 9e Field map Siding Modification | ×1 | **NO** — the 3C gate does not exist |
| Decking / OSB noted | 9f Decking Repair/Replacement | ×1 | **YES** — `osb_replacement_sheets` exists (3 deals carry it) |
| Other = Yes | 9g Spare Custom | ×1 | **NO** — the 3F gate does not exist |

> **2 of 8 rules are derivable today; 6 are not, and every one of the six is blocked on a gate
> answer that has no field.** Measured, not inferred: a search of every column, every config
> field key and every `intake_checklist` value across 200 deals for `tear.?off|dumpster|firstmate|
> hover|roofscope|eagleview|snow.?rail|gutter.?guard` returns **0 columns, 0 field keys, 0 deals**.

**AND THE CONSUMER THAT "ALREADY EXISTS" IS THE WRONG ONE — this is the finding.**
`production_packets.callouts` holds `{id, label, detail}`, and Track U's `roof-callouts.ts`
extends it with a **place** — *"a callout is a PLACE plus WHAT GOES THERE"*. A print-list line is
**a DOCUMENT plus a QTY plus the rule that triggered it**. They share a container and nothing
else, and they have different readers: **the crew scans places on a roof; the office prints
documents.** Putting *"print 2 copies of the FirstMate gutters page"* into the list where
*"the skylight is on the back slope"* lives makes both harder to scan.

**The shape:** `derivePacketPrintList(scope) -> { document, qty, rule, derived_from }[]`, rendered
as **its own section** of the packet beside the callouts, computed on every read, stored nowhere,
and each line able to say which rule produced it. `derived_from` is what makes it a derivation
that shows its working rather than a list that appeared.

**What it cannot yet read, in one line:** everything except the eight always-on documents and the
decking line — because six of the seven conditional rules are keyed on section gates, and **no
gate exists in this system at all.**

---

## 4 · TASK 4 — R9, REPORT ONLY

> *"Tear off Yes → dumpster is Yes, always. Tear off No (overlay) → mark dumpster Yes or No."*

**It is a DERIVATION with a recordable override. It is not a constraint.** Three reasons, in
order of strength:

**(1) The world contains the excluded case, and the PDF itself provides for it.** §4 is
*"WORK THE CLIENT OR ANOTHER CONTRACTOR WILL DO"*. A client who hauls their own debris is a
tear-off with no dumpster. A CHECK constraint would make that unrepresentable and refuse the
save — and the software would be telling a man on a roof that what he is looking at is
impossible. SCOPE §2.8 and R2 both forbid it.

**(2) The print list already treats them as two independent facts.** The rule is
*"**Dumpster or tear-off = Yes** → 5 Dumpster order (W02)"* — **OR**, not *tear-off alone*. If
dumpster were merely a function of tear-off the disjunction would be redundant. The source
document models them as two facts with a strong default between them.

**(3) Storing the derived value is the silent-answer defect, and we closed it three days ago.**
*A default that substitutes a value is a silent answer.* Writing `dumpster = true` because
tear-off is Yes puts a row in the database that reads as **a person's decision when nobody was
asked** — the same shape as `p_quantity numeric DEFAULT 1`, closed on 2026-09-25, and the same
shape as `material_items.quantity NOT NULL DEFAULT 1` behind it. §7.1 RULE 10 is the general
form: a write that records no decision must not look like one.

**So:**
- **tear_off = Yes** → `dumpster` is **not stored at all**. The screen renders *"Dumpster: Yes —
  because tear-off is Yes"*, which is a derivation showing its working. Nothing to override,
  because the sheet says *always*.
- **tear_off = No (overlay)** → `dumpster` is **asked**, and the answer is the person's, carrying
  R1's three states: not asked · asked and unanswered · answered.
- **The override is the tear-off-Yes-and-no-dumpster case**, and it is not a second boolean: it
  carries a **reason**, because a W02 dumpster order will not be printed and somebody downstream
  has to know why. `{ value: false, reason, by, at }`, absent by default.
- **The print list reads the DERIVED value**, never a stored one, which is what keeps
  *"dumpster or tear-off"* correct under either branch.

**One measured fact that sharpens all of this:** today the dumpster reaches a job **as money**.
The only live evidence of a dumpster anywhere in this database is an estimate line —
`Dumpster`, qty 1, **$1500** — which the take-off turned into a material item on the Tear-Off
trade. **The concept exists in the system only as a price, and R6 says the scope sheet must never
ask for one.** Until the scope carries it, there is nothing for the print list to read.

---

## 5 · OUT OF SCOPE, HONOURED

The 17 type codes (DLSS, AARF, MSFA, TRMS, ASRS, GRRP, SLSS, SAGU, BBMS, SKYL, CRPJ, CCAR, TRMR,
MMGG, SMSD, CFAD, CHFL) are BMR's system codes and belong in `tenant_modules.config`.
**`products` and every `wh_*` table were not read, not written and not proposed.** Nothing in
this document touches the catalog or Material Matrix.

---

## 6 · WHERE THE PDF AND THE SPEC DIFFER

Every one of these is the PDF's reading winning over the spec's.

1. **Thirteen numbered blocks plus two unnumbered, not twelve sections.** The spec's table stops
   at §7 and omits **§8 Packet**, the **Automatic print list** and **Job numbering**.
2. **R5's real specification is the automatic print list — seven conditional rules and an
   always-on row, about thirteen document lines.** The spec quotes two of them.
3. **There is a gate before §1.** The header asks **Site inspection · Discovery call**, which
   sets what "complete" even means for the rest of the sheet. Not in the spec's gate table.
4. **§5 is not a uniform 6 × 5 grid.** Only 2 of the 6 rows carry a FOUND checkbox pair; 3 carry
   a COUNT hint; 1 carries a WHERE/NOTES hint. Column applicability is per row — which is a
   harder field type than "a table".
5. **§5's header reads "ALWAYS · PERRY'S FIELD MAPS"** — an external artefact and a person's name.
6. **The sheet names three people and routes work between them.** *"Give to Scott with 'Start
   scope'"*, *"Scott pulls roof geometry from the measurement report"*, **§7 FOR ROBERT
   (Estimator)**, and §8 *"Isaac enters copies for 1/2/3 only"*. The spec says "for the estimator,
   for the crew". **So §7's two audiences are three roles, and one of them — Scott — is expected
   to FILL fields the inspector leaves blank** (roof area, facets, pitch), which changes who the
   form is for mid-sheet.
7. **Job numbering exists and is `MM-YY-###-LastName-TYPE-##`** (`01-26-001-Baker-DLSS-01`),
   **assigned when sold**, with TYPE being one of the 17 codes. Nothing about it is in the spec,
   and it is the one place the type codes become an identifier rather than a label.
8. **"Never guess colors or products — leave the line blank."** The source *instructs* the blank.
   R1 is therefore not only a modelling choice: **a blank is a sanctioned answer on this sheet**,
   and rendering it as "incomplete" contradicts the instruction printed at the top of page 1.
9. **"Guards are not included just because gutters are."** An explicit anti-inference rule in
   §3D that the shape must not optimise away.
10. **The `site_visit_scope` checklist holds 15 fields, not 14.**
