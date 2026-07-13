# CRM Depth — Requirements (what makes it a CRM, not just a pipeline view)

Raised by Jacob 7/13 — **durable capture; this was NOT in the original SCOPE §4 `crm`,**
which described only the pipeline (kanban + stages + deal panel + follow-ups). Grounded in
the existing **Brothers Metal Roofing app spec** (`../../Brothers Metal Roofing/bmr-lead-pipeline-app/docs/SALES_PIPELINE_SPEC.md`)
— Isaac's current tool. **StructTech OS's CRM must not be a downgrade from what he already
uses.**

**Core distinction (do not conflate):** a **CRM manages customers** — contact records,
history, communication, scheduling. The **sales pipeline** is one *view* that moves a
prospect → customer. Week 2 shipped the pipeline view; the depth below is missing.

**Features & logic = YES. BMR's UI/UX & workflow = NO.** Adopt what the BMR spec *does* —
its data model, features, and logic are the right idea. But the BMR app's workflow and UI/UX
are poor; **do not carry them over.** Design fresh per the StructTech OS hi-fi and the
patterns already established in this build. (Same "reference only — adopt concepts, not code"
rule used everywhere else.)

## 1. Prospect / contact data — foundational (a contactless prospect isn't a CRM)
- Full contact info: **name, cell phone, email** — captured on the new-lead form (today's form
  is ~4 fields with no contact info), surfaced in the deal/lead panel.
- **Lead type: homeowner vs company/contractor** (`homeowner_or_contractor`).
- **Project (service) address + billing address** — separate fields. The project address
  should feed the estimate (fixes the current on-roof re-entry gap).
- Source + richer intake — model on BMR's Add-Lead modal + intake checklist.

## 2. Ownership & attribution
- **Rep/user assignment** to a lead: claim / assign / reassign / batch-assign.
- **User attribution on notes and every edit** — *who* did it, not just when ("X changed
  stage," "X assigned to Y"). The activity log exists; add actor identity.
- **Edit-by-ownership:** only the lead owner or a manager can change stage/value/profile/appointments.

## 3. Scheduling
- **Appointments / site surveys / visits** per lead: type (`site_survey`/`inspection`),
  `scheduled_at`, duration, status (scheduled/completed/cancelled/no_show). Ties to the
  Google Calendar integration (SCOPE §13).

## 4. Views & quick actions
- **Table view + calendar view** for the CRM — not only kanban.
- **Quick actions inside a lead:** call / text / email (ties to Twilio + Gmail, SCOPE §13).

## 5. Roles
- salesman / manager tiers (manager: reassign, batch, team view, delete, CSV import). Maps
  onto the role model (SCOPE §5): manager ≈ office/admin, salesman ≈ a dedicated sales role.

---
**Full reference:** the BMR app's `SALES_PIPELINE_SPEC.md` — dual-track (kanban + per-lead
command center), lead lifecycle, intake checklist, appointment/calendar model, batch edit.
