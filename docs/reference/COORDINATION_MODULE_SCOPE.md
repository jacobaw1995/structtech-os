# Coordination Module — Scope & Intended Use

**Purpose of this doc:** map the coordination module — what it is, what's actually built today, and the
full intended shape — *before* we go deep on it (Phase A Week 2 starts with real sign-off). Grounded in
the live schema (7/27), not memory. Companion to SCOPE §4/§6. Open questions at the end need Jacob's vision.

---

## 1. Where it fits — the journey spine

Coordination is the **clarity layer between the sale and the field** (SCOPE §6, "no re-entry"):

```
Lead → Estimate → SIGNED → [ Coordination: sign-off → work order → materials → schedule ] → Field → Done
```

Each artifact is generated from the last. A **signed estimate** is the only way a work order is born
(`create_work_order_from_estimate` gates on `estimate.status = 'signed'`). Coordination then turns that
sold job into an executable plan the crew works from.

## 2. What it IS

The contractor's operational bridge: once a homeowner has bought, coordination captures their **final
sign-off** (colors/finishes/scope confirmed), spins up a **work order**, lists the **materials** needed
(each with a ready-by date), and lays out the **schedule** — where the rule is *material ready-by gates
scheduling* (you can't schedule crew before the materials are in). Contractor-only module.

## 3. Current state — entities (live 7/27)

| Table | Key columns | Notes |
|---|---|---|
| `work_orders` | `estimate_id`, `sign_off_at`, `sign_off_notes`, `voided_at` | born from a signed estimate |
| `material_items` | `work_order_id`, `name`, `quantity`, `ready_by` (date), `sort_order` | the ready-by feeds the gate |
| `schedule_blocks` | `work_order_id`, `crew_name` (**free text**), `start_date`, `end_date`, `blocked`, `blocked_reason` | per-work-order crew + dates |
| `production_packets` | `work_order_id`, `notes`, `callouts` (jsonb) | the visual packet the field crew reads |
| `work_order_activity` | (added 7/24) | post-sign-off change audit trail |

RPCs (all live): `create_work_order_from_estimate`, `record_work_order_sign_off`, add/update/delete
`material_item`, add/update/delete `schedule_block`, `fetch_work_order`, `void`/`restore`/`delete_work_order`.
Full CRUD (§2.6) is in place. UI: coordination list + work-order detail (SignOffPanel, material rows,
schedule rows, progress chips, danger zone).

**What's real vs. what's a stub:**
- ✅ **Real:** work-order creation from a signed estimate; materials with ready-by; schedule blocks with a
  material-gate (`blocked`/`blocked_reason`); production packet; void/restore; post-sign-off audit trail.
- ⚠️ **Stub — the big one:** "sign-off" is `record_work_order_sign_off(work_order_id, notes)` — it captures
  color/finish as **text only**. **No homeowner signature, no generated document, no copy sent.** It calls
  itself sign-off but is really a notes field. (This is Phase A Week 2's job.)
- ⚠️ **Free-text crew:** `schedule_blocks.crew_name` is a string — no crew roster, no per-person assignment.

## 4. The workflow (intended use, step by step)

1. **Estimate signed** → contractor opens Coordination, creates the work order (one-click from the signed estimate).
2. **Homeowner sign-off** → confirm final colors/finishes/scope; homeowner **signs** (today: notes only).
3. **Materials** → list what the job needs, each with a **ready-by date**.
4. **Schedule** → assign crew + dates; blocks whose work starts before their materials' ready-by are **gated**.
5. **Field** → crew works from the production packet; logs daily check-ins (Field module).
6. **Change after sign-off** → any scope/material change post-sign-off is **audit-logged** (interim; formal
   change orders are backlogged).

## 5. Going deeper — the full intended scope (what "deep" means here)

Mapped to where each piece lives on the roadmap:

- **A · Real sign-off (Phase A Week 2 — next).** Homeowner **signature/initials** (in-person AND remote via
  the shared signing system), a **generated signed document** attached to the work order, and the copy
  **delivered to the homeowner.** Replaces the notes-only stub. *Shares infrastructure with estimate signing.*
- **Crew as a real entity.** Replace free-text `crew_name` with a crew roster + per-person assignment — the
  prerequisite for the cross-job schedule below to mean anything.
- **VITAL · Cross-job crew Gantt (parking lot → pull into scheduling-depth).** Today's schedule is
  *per-work-order*. The real operational need is a **company-wide timeline across ALL jobs and crews**: when
  does a job free up so the right crew is ready for the next, where are the gaps/overlaps, who's on what now.
  This is a distinct master-schedule view, not a reflow of the per-WO list.
- **Scheduling — three distinct kinds, don't conflate** (also in the roadmap matrix): (a) per-work-order
  crew+dates *(live)*; (b) material-delivery ready-by *(live)*; (c) site-visit/appointment scheduling
  *(separate, Stage-6/parking)*; (d) Google Calendar sync *(Phase D)*.
- **Formal change orders (Later).** The post-sign-off audit trail is interim; a real change-order flow
  (documented scope/price change, re-sign) is the full version.
- **C · Homeowner portal surfacing.** The signed sign-off doc, the schedule, and job progress **appear in
  the homeowner portal** — coordination is a primary *source* of what the customer sees there.
- **Mobile polish (backlog).** Material/schedule rows are cramped on a phone — a real field-usable layout pass.
- **Later · Procurement.** Materials → actual ordering (ties to the StructTech supply shop, §12C) — the
  ready-by list becomes a purchase flow.

## 6. Cross-module connections (why coordination can't be scoped alone)

- **← Estimating:** work orders are born only from a signed estimate; the estimate's scope/line items are
  the source of the materials list (today re-entered; deeper: generated).
- **→ Field:** the production packet + schedule are what the crew executes and checks into.
- **→ Homeowner portal:** sign-off doc + schedule + progress are portal content (Phase C).
- **Signing system:** sign-off shares the in-person/remote signature + email infrastructure with estimating.
- **Scheduling:** the cross-job Gantt is a coordination view but a company-wide concern.

## 7. Resolved decisions (Jacob, 7/27) — build to these

1. **Materials — mode-driven.** Auto-generate from line items for **guided** estimates; **manual** entry
   for **manual** estimates. Keys off the estimate's `build_mode`.
2. **Sign-off scope.** Show the **entire work order**, with a **hard signature/initials requirement on
   colors & finishes** specifically (the rest is visible/confirmed, the signature focus is on colors/finishes).
3. **Change orders = void + replace.** A change order is a **new agreement that voids and replaces** the
   existing signed document — not an amendment or diff. Prior signed doc is voided; a new one is generated
   and re-signed.
4. **Crew model — staged.** Individuals now → people assigned to crews → crews assigned to work orders.
   **Multiple work orders per JOB**, so different crews handle different tasks (tear-off vs install vs gutters).
5. **Gantt — later is fine.** Cross-job crew Gantt stays parked.
6. **Portal content.** Signed documents · approved project photos · schedule window · estimated material
   delivery · sales rep / PM contact info · **a ticket-request feature** (homeowner submits questions/requests).

## 8. Structural guardrails these decisions create (design so we don't preclude — not building now)

- **Multiple work orders per JOB (from #4).** Today a work order is 1:1 with a signed estimate. His model
  needs a **job** that can carry MULTIPLE work orders (each a crew-assignable task). When coordination depth
  is built: introduce a job grouping (or let work orders share a `job_id`) — do **NOT** hard-wire one work
  order per estimate. Mental model: the **estimate is the sale**, the **job is the execution**, **work orders
  are the crew-assignable units** under it.
- **Sign-off as a versioned, replaceable AGREEMENT (from #3).** Today sign-off is a single `sign_off_at` /
  `sign_off_notes` on the work order. Void-and-replace change orders need sign-off documents modeled as their
  **own versioned entity** (e.g. `work_order_agreements`): original + each change order, only the latest
  active, prior ones voided — with the signed-doc + re-sign flow. Don't leave sign-off as two columns on
  `work_orders`.
- **Approved project photos (from #6).** Homeowner-visible photos need an **approval gate** — someone marks
  which field photos are customer-facing (new flag on the photo/check-in record; ties to R2 storage).
- **Homeowner ticket-request (from #6).** A homeowner→contractor support channel — a small job-scoped tickets
  entity surfaced in the portal. (Distinct from the existing internal `tickets` table, which is StructTech's.)

These are notes for the coordination-depth + portal builds. Work now stays: Phase A Week 1 (assistant role),
then Week 2 (real sign-off). But the data model shouldn't box these out.
