# THE JOB SCOPE SHEET — AUTHORITATIVE SPEC

**Source: `BMR Job Scope — Initial Inspection`, 5 pages, supplied by Jacob 2026-09-27.**
**Decision of record, Jacob, 2026-09-28: BUILD IT NOW.** The pilot moves from 2026-10-07 to
approximately 2026-10-19; G12 moves from 10-31 to approximately mid-November. Recorded as a
cost, not argued.

---

## 0 · WHAT THIS DOCUMENT IS, AND WHY IT IS NOT A REDESIGN

The PDF names StructTech OS three times — *"Field quantities also feed the StructTech OS Scope
checklist"*, *"Same as StructTech OS Service Address"*, *"= StructTech OS Existing Roof Type"*.
**It was written against this system.** What ships today is a rough first third of it.

**Measured, so the scale is not a guess.** The live Site Visit Scope Checklist holds **14
fields**, all of them inside the PDF's section 3A and part of section 5. The PDF has **twelve
sections** and on the order of **120 inputs**, and — the part that matters — **branching**.

**THE LOOK IS THE SMALL PART. THE GATES ARE THE BUILD.**

---

## 1 · THE STRUCTURE, TRANSCRIBED

| § | Section | Gate |
|---|---|---|
| 1 | Client and job | ALWAYS |
| 2 | Measurement reports | ALWAYS |
| 3A | Roof — decide, then details | **PRICE A ROOF ON THIS JOB?** No → skip all roof detail |
| 3B | Soffit and fascia | **Soffit and fascia · Soffit only · Fascia only · No** |
| 3C | Siding | **Yes / No** → No skips to 3D |
| 3D | Gutters and gutter guards | **Gutters and guards · Gutters only · Guards only · No** |
| 3E | Snow rail | **Yes / No** |
| 3F | Other | **Yes / No** |
| 4 | By others / not included | ALWAYS |
| 5 | Roof conditions | ALWAYS — a 6-row table |
| 6 | Site and access | ALWAYS |
| 7 | Notes — for the estimator, for the crew | ALWAYS |

Sub-gates inside 3A: **TEAR OFF** yes/no · **DUMPSTER NEEDED** yes/no, with a stated rule —
*"Tear off Yes → dumpster is Yes, always. Tear off No (overlay) → mark dumpster Yes or No."*

---

## 2 · THE RULINGS. These are the build, and each is a property, not a shape.

### R1 — A SKIPPED SECTION IS AN ANSWER, NOT AN ABSENCE.
**This is the most important ruling in the document.** "No — not on this job" is a decision a
person made on a roof. It is not the same as a section nobody has reached yet.

**Three states, never two:** `not on this job` · `on this job, not yet filled` ·
`on this job, filled`. A fourth exists and must be reachable: **`could not be read`**.

This is the undecided-state discipline the build has applied to pricing, to `ready_by`, and to
QC. It arrives here with teeth, because **a roof nobody priced and a roof the client declined
produce the same empty section today**, and one of those is a lost sale.

### R2 — THE GATE CHANGES WHAT IS SHOWN. IT NEVER BLOCKS A SAVE. (SCOPE §2.8)
A gate reveals and hides. It does not disable, and it does not refuse. If an inspector fills
siding lines and then answers "No siding on this job", **the lines are kept and marked**, not
deleted. Guidance is advisory; the person on the roof is the authority.

### R3 — THE 17 TYPE CODES ARE TENANT VOCABULARY, NOT CATALOG.
DLSS, AARF, MSFA, TRMS, ASRS, GRRP, SLSS, SAGU, BBMS, SKYL, CRPJ, CCAR, TRMR, MMGG, SMSD,
CFAD, CHFL. **These are BMR's system codes and they live in `tenant_modules.config`, beside
the existing field definitions.** They are NOT products and they do not touch `products` or
any `wh_*` table. **CATALOG AND MATERIAL MATRIX REMAIN OUT OF THIS BUILD.**
A code carries its label; the sheet stores the code, the screen shows the words.

### R4 — A PHOTO REFERENCE WE CANNOT RESOLVE IS A NOTE, AND MUST READ AS ONE.
Section 5 carries a **CompanyCam photo ref** per row, and section 6 one more. CompanyCam is
outside this system: **we cannot verify that the reference points at anything.**
Standing rule, applied: *a reference that is not verified against the thing it references is a
name, and a name is not a control.* So it is stored as a typed external reference, rendered as
a note, and **never rendered as evidence that a photo exists.** When office-side upload lands,
an internal photo is a different field with different standing, and the two never merge.

### R5 — PACKET LINES ARE DERIVED AT READ TIME AND STORED NOWHERE.
The sheet states two consequences outright: *"after submit, packet line 9e Siding Modification
× 1 is added"* and *"packet line 9g Spare Custom × 1 is added"*.
**A stored derivation is a mirror, and this build has spent a month deleting mirrors.** A stale
packet line is a confident sentence about a roof that is no longer true, on the screen where a
crew decides whether it may leave. Derive from the scope at read time, every time.

### R6 — NO PRICES ON THIS SHEET, AND THAT IS DELIBERATE.
The PDF says it in bold and it matches A2.1's no-re-entry rule exactly. The scope feeds the
estimate; the estimate holds money. **An inspector must never be asked for a number the
estimate will ask for again.**

### R7 — IT IS FILLED ON A ROOF OR IN A DRIVEWAY. SCOPE §2.4 GOVERNS.
375px first. ≥56dp targets. One thumb column. Outdoor mode available. **And the measured
defect it must beat: the current form costs 2 taps minimum per field, 11 fields on the New
Lead stage alone, 22+ taps and 11 server round trips to fill one screen, with four different
commit behaviours.** That is the before-measurement. Anything shipped is graded against it.

### R8 — THE EXISTING 199 DEALS DO NOT BREAK.
Everything lands in `intake_checklist` jsonb, additively. 166 deals carry `existing_roof_type`,
178 `roof_type_requested`, 177 `remodel_or_new_construction`. **Those keys keep their meaning.**
A new key never redefines an old one; if a concept genuinely changes, the old key is retained
and the change is recorded, never silently remapped.

### R9 — TEAR OFF YES ⇒ DUMPSTER YES IS A RULE THE SHEET STATES. ENFORCE IT AS A DERIVATION.
*"Tear off Yes → dumpster is Yes, always."* That is the PDF's own logic, not an inference.
Derive it, show it derived, and let it be overridden with the override recorded — the same
three-state discipline as everywhere else.

---

## 3 · WHAT DOES NOT EXIST TODAY AND MUST BE BUILT

1. **A gate engine.** Nothing in the config-driven checklist branches; all fields always show.
2. **New field types:** gate (2–4 mutually exclusive options) · type-code picker · **table**
   (section 5 is 6 rows × 5 columns) · external photo reference.
3. **Section 4 — by others / not included.** Exclusions are captured nowhere.
4. **Section 6 — site and access.** Dumpster spot, power lines, pets, gate code, parking,
   landscaping to protect, site contact. None of it exists.
5. **Section 2 — measurement reports.** FirstMate / Hover / RoofScope / EagleView / hand
   measured, with an ordered-vs-received state. Measurement *import* stays Phase B; recording
   which platform and whether it arrived is in scope now.
6. **Scope → packet derivation** (R5).
7. **Two notes audiences** — "for the estimator" and "for the crew" are different readers and
   must not render to the wrong one.

---

## 4 · WHAT IS ALREADY THERE AND MUST BE REUSED, NOT REBUILT

- `tenant_modules.config` holds stage and field definitions; a TypeScript engine renders them
  generically. **The gate lives in config beside them.**
- `intake_checklist` jsonb, with 199 live rows (R8).
- The document-as-editor pattern, shipped on the estimate builder in July.
- The three-state rendering discipline shipped on QC on 2026-09-27 — on · off · could not read.
- `production_packets.callouts`, four RPCs, a parser and an office route (2026-09-27). **R5's
  output is callouts. The consumer already exists.**

---

## 5 · ACCEPTANCE — and it is not a probe

**RULE 17 governs: accepted on the rendered screen, or not accepted.** A policy-reading method
is sound for what a policy governs and blind to what a person sees.

The acceptance is one sentence: **Jacob fills this sheet on a phone, standing up, for a real
roof, and it is faster and clearer than the paper.** Against the measured baseline in R7.

Every sweep written for it runs its positive control first (rule 20) and states its axis
(rule 18). Every count carries the container it was counted in.
