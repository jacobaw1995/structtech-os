# StructTech OS — Backlog (durable queue)

Phase-independent list of deferred / queued work, so nothing lives only in a
session's memory or a soon-to-be-overwritten CLAUDE.md phase section. Treat this as
the source of truth for **"what's owed and what's next,"** alongside `SCOPE.md` (what
things are) and `BUILD_PLAN_3WEEK.md` (the phase sequence). When an item is picked up,
move it into the active CLAUDE.md phase; when done, delete it here.

**Last updated:** 7/13/26 (after Week 2 — pipeline + BMR estimating)

---

## Next up — revenue layer (owed from the Week 2 "close-tool" fork)

- **`proposals` + Present Mode module** (internal-only; SCOPE §4). StructTech's own
  quote/proposal builder + video-call **Present Mode**. The counterpart to contractor
  `estimating` — this is how StructTech closes its *own* paying clients ($20K MRR
  path). Source material: `docs/reference/EXISTING_CRM_SCHEMA.md` (proposals/quotes) +
  the legacy `PRESENT_MODE_PLAN.md`. **Not started.** Was consciously deferred when
  BMR live estimating was prioritized in Week 2 — not dropped.

---

## Deferred from Week 2 (small, tracked)

- **Per-deal next-action chip** — add `next_action` (text) + `next_action_at` (date)
  to `deals`, an editable field, and the card/panel chip (wireframe 1b/2b element).
- **R2 file storage** — persist estimate PDFs and populate `signatures.pdf_url`;
  today PDFs generate on-demand and `pdf_url` stays null.
- **Follow-up *sending*** — the Make.com scheduled scenario that emails scheduled
  `follow_ups`. Schema + UI exist; actual sending does not (always scoped as "later").
- **Responsive mobile web shell** — `WorkspaceShell` is desktop-only; needs drawer nav
  + mobile top bar. (In progress as of 7/13.)
- **Coordination schedule-block edit polish** — editing start/end date as two separate
  field-blur submits can transiently violate the `end_date >= start_date` check and
  surface a raw Postgres error in the UI banner. Rare, non-corrupting (final edit saves
  fine). Fix = friendlier error text, or a single two-field "save" instead of per-field
  auto-submit.

---

## Deferred from Week 3 — field module (small, tracked)

- **Annotated trim-map / boot-vent placement layer** — wireframe 3a's production
  packet shows a trim map with pinned photo markers. Needs R2 photos + pin
  coordinates over an image; not modeled this phase. Custom detail callouts (text
  list) shipped instead.
- **check_ins.photos as base64, not R2** — reuses the `signatures.signature_data`
  precedent (functional, no fake upload UI) until R2 file storage (above) lands.
  Fine for a handful of phone photos per check-in; would need R2 before real volume.
- **No crew/user identity mapping** — `check_ins.crew_name` / `schedule_blocks.crew_name`
  are free text; a crew member self-identifies at submission time. A real crew entity
  (member roster, per-user assignment) is future scope.

---

## Management controls retrofit (SCOPE §2.6 — full user CRUD, before Isaac goes live)

Earlier modules were built create-and-advance and lack user-facing edit/delete/archive
on some entities, so cleaning up human error currently needs a developer + SQL. Backfill
so the *user* manages their own data. High priority — needed before Isaac operates real jobs.

- **Deals** — user delete/archive + edit deal details (today: create + stage + notes only).
- **Estimates** — user void/delete + edit (the `void` status exists but has no UI path).
- **Work orders** — user delete/void a work order (materials + schedule already have delete;
  the work order itself does not).
- **Standing rule going forward:** every new entity ships with edit + delete/archive from
  the start (now a Definition-of-Done item + SCOPE §2.6). Field module included.

---

## CRM depth — real customer management, not just a pipeline view (raised 7/13)

Week 2 shipped a thin **sales-pipeline view**; it is NOT yet a CRM. Full requirements +
grounding in Isaac's current tool: **`docs/reference/CRM_DEPTH_REQUIREMENTS.md`** (adopt the
BMR spec's *features & logic*, NOT its UI/UX/workflow). Headline gaps:

- **Contact/prospect data** (foundational): name/cell/email on the lead form, homeowner-vs-
  company type, **project address + billing address** (project address feeds the estimate).
- **Ownership + attribution:** rep assignment (claim/assign/reassign/batch), and *who* made
  each note/edit — not just when.
- **Scheduling:** appointments / site surveys / visits per lead (type, time, duration, status).
- **Views + quick actions:** table + calendar views; call/text/email inside a lead.
- **Roles:** salesman / manager tiers (edit-by-ownership).

Sequencing note: the **contact/address/type data + richer lead form is near-term** (a real
lead needs it, and it fixes the estimate re-entry gap); the deeper CRM (assignment,
scheduling, calendar/table, quick actions) is a dedicated **CRM-depth phase** (quick actions
depend on the Twilio/Gmail integrations, SCOPE §13).

---

## Security workstream (REQUIRED before any client user gets a login — SCOPE §11)

- Tighten `audit_leads` "authenticated read = true" policy — currently any logged-in
  user can read every lead across all tenants.
- Migrate legacy tables (`org_systems`, `tickets`, `engagements`, …) off `is_staff()`
  to the `my_org_ids()` membership model.
- Enable RLS on `structtech_state`.
- Add `NOT NULL` to `deals.org_id` and the CRM/estimating `org_id` columns once RPCs
  are the only insert path.
- Replace `tenant_type`-based targeting with `org_id` in seeds/updates once a 2nd
  contractor org exists (flagged in the Stage 1 migration).

---

## From phone testing (7/13) — UX, scheduling, docs

- **Estimate wizard: back navigation** *(fixing near-term — real bug)* — the
  preliminary→validate→present→sign flow has no way back; missing a field before advancing
  forces starting a whole new estimate. Add back/step navigation (steps stay editable until
  `present_estimate` locks them).
- **Coordination detail: mobile layout** *(fixing near-term)* — material rows (name/qty/date/×)
  and schedule crew+date fields are cramped/jammed on a phone. Stack/wrap for narrow viewports.
- **Cross-job crew schedule / Gantt (VITAL — operational, not visual polish)** — a master,
  company-wide timeline across ALL jobs and crews: see when a job ends so the right crew is
  ready for the next, spot gaps/overlaps, and see at a glance which crew is on which job now
  and where they'll be later. The current **per-work-order** crew+dates list does NOT give
  this cross-job resource view — this is a distinct master-schedule view/dashboard.
  Deferrable short-term (small crew) but a real need, priority for the scheduling-depth pass.
  (Stack: DHTMLX Gantt PRO decided for enterprise; portal has a deferred lightweight SVG Gantt.)
- **Docs section** — one place to view / download / send work orders + estimates (signed or
  not), later invoices + packets. Ties to the tenant-customizable document-template system
  (SCOPE §12E). Jacob: "add to later build if needed."

---

## Larger future capabilities (already recorded — SCOPE §12 North Star / §13)

- Editable document-template system + **invoices** + **work orders** (SCOPE §12E).
- AI assistant + semantic search (§12A) · client product catalogs + inventory (§12B) ·
  StructTech shop / distribution integration (§12C) · native mobile app (§12D).
- Integrations: Google Workspace, Twilio, Stripe (§13); QuickBooks + aerial roof
  measurement (runner-ups).

---

## Remaining planned phases (BUILD_PLAN_3WEEK.md)

- **Week 3:** coordination (work order → materials → schedule) + field module +
  delivery/portal — the "clarity" layer.
