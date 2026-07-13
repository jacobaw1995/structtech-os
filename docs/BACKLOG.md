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
