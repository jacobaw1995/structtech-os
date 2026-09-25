# Production packet v2 — the structured callout list

Derived by Track S on 2026-09-25 to the controller's instruction. **No maps.** Graphical roof and trim
maps are deferred to November; this is the MVP that ships before the pilot.

**The property, as given:** *a crew arriving at a job can read, from one list, what they are installing
where and what is different about this roof — in the crew's words, derived from objects that already
exist.*

---

## 1. THE FIRST FINDING IS THAT THE LIST ALREADY EXISTS, AND IT IS EMPTY

`production_packets.callouts` is `jsonb NOT NULL DEFAULT '[]'`. It has four RPCs
(`add_production_packet_callout`, `update_production_packet_callout`,
`delete_production_packet_callout`, `update_production_packet_notes`), a parser
(`src/lib/field/callouts.ts`, shape `{ id, label, detail }`), a numbered read display per wireframe 3a
(`CalloutRow`), an add form, and a two-tap delete. **A structured callout list, hand-entered, is live.**

**`production_packets` holds 0 rows.** Not one packet has ever been created, in any tenant, so not one
callout has ever been written. The v2 task is therefore **not "build a callout list"** — it is
**"stop requiring somebody to type it"**. Said the other way round: the reason the list is empty is not
that the office refuses to use it, it is that nobody has opened the Packet tab; and asking an office
that has never opened it to hand-key fifteen facts the database already holds is the reason it will
stay empty.

## 2. THE SHAPE: TWO LISTS, ONE RENDERED VIEW, AND NOTHING NEW STORED

**Derived callouts are COMPUTED AT READ TIME AND NEVER STORED.** This is the whole design decision and
it is not a performance call. A stored derivation is a **mirror**, and this project has spent a month
deleting mirrors (`src/lib/permissions/model.ts` records four, A/B/C/D, and why two of them went): the
moment the estimate changes, the trade changes, or the material's `ready_by` moves, a stored callout is
a confident sentence about a roof that is no longer true — on the one screen where a crew decides
whether it may leave. So:

| | `production_packets.callouts` (exists) | derived callouts (new) |
|---|---|---|
| Written by | the office, by hand | nothing — computed on each read |
| Lives in | the table | nowhere |
| Editable | yes, full CRUD, already shipped | no. Fix the SOURCE, and the callout follows |
| Goes stale | yes, and that is the office's to fix | cannot |
| Says | *"Skylight on the back slope — do not step on the cover"* | *"10 sq · 26ga black Ag panel"* |

**One rendered list, two origins, each labelled.** A crew must never have to guess whether a line is
a fact about this roof or somebody's note about it — the same call as `STATE_LABEL` in `QcPanel`, where
four kinds of silence were given four different sentences. Each derived line therefore carries the
object it came from, as a short source tag the crew can read (*"from the estimate"*, *"from the site
visit"*), not an id.

**A derived line is a row, always — including when it is absent.** `QcPanel`'s rule applied here: a
callout section that renders nothing when a source is empty is indistinguishable from a roof with
nothing unusual about it. A missing source says so (*"No site-visit scope recorded"*), because on this
screen an absence is information.

**Refusal to derive is its own state.** If a source read fails, the section says *"could not be read"*
and never renders as "nothing unusual" — `fetchQcRows`'s three answers, reused rather than re-argued.

## 3. THE SOURCES, AND WHAT EACH ONE CAN SAY

Every one exists today. Nothing below needs a new table, a new column, or a migration.

### 3a. What they are installing — `material_items` on this trade work order
`name`, `quantity`, `unit`, and `ready_by` with `ready_by_source`. This is already the Materials tab's
data (`src/components/field/MaterialsList.tsx`) and carries **no money by construction** — the table
has no price, cost or total column. A callout line is `10 sq · SYNTHETIC metal panels`, plus
*"not ready until 25 Oct"* when `ready_by` is in the future.

### 3b. What the estimate said, where a take-off has not landed — `estimate_line_items`
`description`, `quantity`, `unit`, through `take_off_lines` for this trade. This matters because
**materials are the take-off's output and the take-off is optional**: on 2026-09-25, `material_items`
holds **2 rows** across the whole database while `estimate_line_items` holds **22**. A packet that
reads only materials is empty on almost every job. The estimate is what the customer bought; the
callouts say so, marked *"from the estimate — no take-off yet"*, which is also the honest prompt to
the office.

### 3c. What is different about this roof — `deals.intake_checklist -> 'site_visit_scope'`
The richest existing source, and a real one: measured shape is 16 keys —
`roof_profile_style`, `roof_color`, `gutter_color`, `facets`, `pitch_slope_notes`, `roof_vents`,
`pipe_boots`, `drip_edge`, `ice_water_shield`, `osb_replacement_sheets`, `fascia_lf`, `soffit_lf`,
`gutters_lf`, `roof_area_sqft`, `scope_notes`. A crew reads *"26ga black · 1 facet · 4 pipe boots ·
ice & water shield: yes · 3 sheets OSB to replace"* from it without a word being retyped.
**Only non-default, non-zero, non-"N/A" values become callouts** — a list of fifteen zeroes is worse
than no list, and this is where "in the crew's words" is actually earned.

### 3d. The roof itself — `estimates.squares` and `estimates.pitch`
Already on the packet header (`ProductionPacketView` renders `{squares} sq · {pitch} pitch` from
`fetch_field_jobs`). A **6/12 pitch is a crew-facing fact** — it decides harnesses — so it belongs in
the callout list and not only in a header line.

### 3e. Why they are here — `deals.existing_roof_type`, `roof_type_requested`,
`remodel_or_new_construction`, `intake_checklist -> 'main_issue'`
*"Tearing off shingle, installing standing seam"* is one line that orients a whole crew. `main_issue`
is free text the office already wrote — measured values include *"Small leak above living Room"* and
*"Insulation on roof."*, which is exactly the register asked for.

### 3f. What must be photographed — the QC requirement list for this trade
Code, not data (`src/lib/field/qc.ts`), already rendered by `QcPanel`. It joins the callout list only
as a pointer (*"4 required checks on this trade"*), because duplicating the checklist in a second
place is how two lists come to disagree.

## 4. BEFORE-MEASUREMENT — ACROSS THE 3 LIVE JOBS, TODAY

Measured 2026-09-25 against the live database. Three jobs exist, in two tenants.

| Job | Live trades | 3a materials | 3b estimate lines | 3c site-visit scope | 3d squares/pitch | 3e roof types + main_issue | Non-empty callout list? |
|---|---|---|---|---|---|---|---|
| BMR · 101 W Broadway St, Unit B | 1 | **1** | 1 | **0 keys** | **2255 sq · 6/12** | **none** | **YES — 3 lines** |
| BMR · 851 E Hamilton St (Devin Carter) | **0** | 0 | 9 | **0 keys** | none | **none** | **NO — and unreachable** |
| SYNTHETIC · 1 Synthetic Way | 1 | **1** | 1 | **0 keys** | none | **none** | **YES — 1 line** |

**2 of 3 jobs would produce a non-empty list. Both lists would be almost entirely "what you are
installing". 0 of 3 would produce a single "what is different about this roof" line.**

The third job produces nothing and **cannot be reached at all**: with 0 live trade work orders there is
no field surface to open, which is a separate defect and not this one's.

### AND THE MECHANISM, BECAUSE THE NUMBER IS RIGHT FOR A REASON THAT IS NOT THE OBVIOUS ONE

*(§7.1 RULE 19 — agreement on a figure is not agreement on the mechanism, and only the mechanism
predicts the next case.)*

The obvious reading of "0 of 3" is **that the scope fields are unpopulated, so 3c cannot feed anything.
That reading is FALSE**, and it would have sent this task off to design a new intake. Measured across
all 199 deals:

- `existing_roof_type` populated on **166** (Shingle 104, Metal 42, Asphalt Shingle 5, Standing Seam 4, Flat/Membrane 3, Wood Shake 2, Copper 1, Slate 1)
- `roof_type_requested` on **178** · `remodel_or_new_construction` on **177**
- `intake_checklist -> 'site_visit_scope'` on **4** · `main_issue` on **6**

**The sources work. The three deals that reached a JOB are the three that skipped intake.** Two are
test leads (*"Fake Lead"*, *"SYNTHETIC Test Homeowner"*) and the third, Devin Carter, is a real BMR lead
sitting at stage `new_lead` while carrying a signed estimate and a job — created 2026-07-31, two months
before the intake fields were filled on anything. **So the 0 is an artefact of which three rows got
there first, not a property of the design**, and the same list built against any of the 166 deals that
carry a roof type produces callouts immediately.

**The one figure that IS a real limit: `site_visit_scope` on 4 of 199.** That is the richest source and
it is nearly empty, because it is written by the site-visit scope checklist, which is §5's stage 7
("scope → estimate wiring") and is not built. So §3c is the section that will render *"No site-visit
scope recorded"* on virtually every job until that ships, and **that sentence is the deliverable**, not
a failure — it is how the office finds out the packet is waiting on the site visit.

**AND THE AXIS THIS MEASUREMENT CANNOT SEE** *(§7.1 RULE 16):* it counts non-null columns. It does not
know whether a populated value is TRUE — `roof_area_sqft: 0` and `roof_color: "N/A"` and
`scope_notes: "None"` are all present-and-useless, and they are present in the measured sample. That is
why §3c filters on meaning rather than on presence, and why a crew-facing count of *useful* callouts
will be lower than any count of *populated fields*.

## 5. WHAT THIS DOES NOT DO

- **No maps.** Deferred to November, per the ruling.
- **Nothing stored.** No migration, no new column, no new table. If a later decision wants derived
  callouts persisted — for a PDF sent to a supplier, say — that is a snapshot with a timestamp and a
  reason, and it is a different task with a different name.
- **It does not write to `callouts`.** The hand-entered list stays exactly as it is, and a derivation
  never touches it. An office note is a fact about the roof that no object holds; overwriting it with
  a derivation would destroy the only thing on this screen that had to be typed.
