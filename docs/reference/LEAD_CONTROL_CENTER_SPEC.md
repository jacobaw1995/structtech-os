# Lead Control Center — Spec (the per-lead command center)

Grounded in the **BMR app source** (`command-center.ts`, `intake-checklist.ts`, `scope-fields.ts`,
`LeadCommandCenter`/`LeadIntakeChecklist`/`LeadProfileForm`). **Adopt the features & logic below;
design the 3-panel UI fresh** (BMR's UX is not carried over). This is what our thin CRM deal panel
must become.

## What it is / where it fits
Opens when you **click a lead in the pipeline**. It's the per-lead **command center** — a
**3-panel** layout on desktop/tablet, **stacked/single-column** on mobile.

## Dual-track model (critical — do not conflate)
- **Pipeline (kanban) stage** — the board column (lead → qualified → proposal_sent → negotiating → closed).
- **Command job-path stages** — the per-lead tabs INSIDE the control center, distinct from the kanban:
  **New Lead → Site Visit → Scope → Quote → Negotiating → Closed.** The active tab is *derived* from
  the lead's data/milestones, and each tab tracks its own completion.

## Forms == checklists (the core idea Jacob stressed)
A stage's **form gathers data (or shows it if already there); the checklist is the same data viewed as
completion** — a checkmark per data point, "X of N gathered," and a % for the stage. When all of a
stage's data is in, the stage is complete (and gates the "mark complete"/advance action). Each field
shows its value or an **emptyHint** ("Gather on intake call").

## Per-stage vital fields (the form shown per command tab)
- **New Lead:** first name, last name, cell phone, email, customer type — **4 values (confirmed 7/14):** `homeowner` · `contractor` (GC) · `property_management` · `commercial` (Homeowner / Contractor (GC) / Property Management / Commercial-Other),
  main issue/problem, existing roof type(s), requested roof type(s), remodel/new construction,
  service address, source (readonly).
- **Site Visit:** service address, visit status, cell phone, existing/requested roof types.
- **Scope:** service address, existing/requested roof types, scope status.
- **Quote:** service address, current/desired roof types, main issue, key decision maker.
- **Negotiating:** quote amount, desired roof, pipeline stage, last note.
- **Closed:** deal value / outcome.
Field types: text · phone · email · textarea · select · **roof_types** (multi-section) · address (maps link) · readonly.

## The two checklists (both = data-gathering forms with completion)
### 1. Intake-call checklist (New Lead — gathered on first contact)
contact name (first & last) · cell phone · email · service address (job site) · homeowner-or-contractor ·
existing roof type(s) (all sections) · requested roof type(s) · main issue/problem · remodel-or-new ·
**site visit scheduled on the call** — plus pre-visit **estimate inputs** (approx roof area, pitch, metal
type) for a ballpark/preliminary estimate.

### 2. Site-visit scope checklist (Site Visit/Scope — on-site survey; feeds the estimate)
roof area (sq ft) · facets · pitch/slope notes · gutters (lf) · fascia (lf) · soffit (lf) · pipe boots ·
roof vents · OSB replacement (sheets) · roof color · roof profile/style · gutter color · ice & water shield ·
drip edge · scope notes/extras. (Catalog-enriched: products map to scope keys; the scope "auto-builds"
when the data points are in, and drives the on-site quote.)

## Per-stage guidance & gating
- **Recommended next action** per stage (e.g. "Claim this lead, then call to start the intake checklist";
  "Intake complete — schedule the site visit and generate a preliminary estimate").
- **Completion gating**: e.g. can't "Mark Qualified" until the intake checklist is complete; scope
  auto-builds; quote requires a value + presented; etc.

## Rich lead data model we're MISSING (deals today is far thinner)
first_name / last_name (split, not one `contact_name`) · secondary_phone · company_name ·
homeowner_or_contractor · remodel_or_new_construction · existing_roof_type · roof_type_requested ·
structured service address (street/city/state/zip) + billing · referral_name · owner_id ·
**intake_checklist JSON** (main_issue, general_notes, site_visit scope data, estimate_inputs) ·
site_survey_complete_at · roof_scope_ordered_at · quote_presented_at · appointments · notes-with-author.

## Confirmed 3-panel layout (from Jacob's hi-fi, 7/14)
- **LEFT panel:**
  - **Quick Actions** — Call · Text · Schedule · Log Activity (2×2).
  - **Prospect Data** — name, phone, billing address, **Owner** dropdown (= rep assignment),
    **Tags** (e.g. Homeowner / Remodel / Asphalt shingle), **Pipeline Stage** dropdown (the KANBAN
    stage — separate from the command tabs), "Edit lead details →".
  - **Revision History** — the system activity log (desktop/iPad only; merges into Log Activity on mobile).
- **CENTER panel:**
  - Lead name + sub-stage + close (×); a **Progress %** bar.
  - **Command-stage tabs**: New Lead · Site Visit · Scope · Quote · Negotiating · Closed (the job path,
    NOT the kanban stage). Tabs gate/enable by completion.
  - The active stage's **checklist == form**: a header ("INTAKE CALL CHECKLIST — 7/10") + instruction +
    progress bar, then rows where **each row is a form field AND a checklist item in one**: empty → hollow
    circle + hint, tap to type inline; filled → value shown + green check + pencil to re-edit. The card
    just re-renders with the active stage's item set (no separate screen per stage).
- **RIGHT panel:** **Lead Notes** — "name + timestamp on every entry"; add-note box + author/timestamped entries.
- **MOBILE:** single column — header, Quick Actions as a row, **Log Activity = notes + activity combined**,
  stage tabs (horizontal scroll), the checklist==form card (full inline edit), then Prospect Data + Tags
  collapse below. Full field control on mobile.

**The dual-track, made concrete:** LEFT has the *Pipeline Stage* dropdown (kanban); CENTER has the
*command-stage tabs* (job path). They are two different axes on the same lead.
