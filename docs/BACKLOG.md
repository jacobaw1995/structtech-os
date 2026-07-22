# StructTech OS — Backlog (durable queue)

Phase-independent list of deferred / queued work, so nothing lives only in a
session's memory or a soon-to-be-overwritten CLAUDE.md phase section. Treat this as
the source of truth for **"what's owed and what's next,"** alongside `SCOPE.md` (what
things are) and `BUILD_PLAN_3WEEK.md` (the phase sequence). When an item is picked up,
move it into the active CLAUDE.md phase; when done, delete it here.

**Last updated:** 7/13/26 (after Week 2 — pipeline + BMR estimating)

---

## 🔴 ISAAC FEEDBACK (7/20) — DEPTH PASS. Supersedes all other priorities.

First real client demo. **Verdict: the foundation held; the workflow surface did not.** Security,
tenancy, attribution and the 946-row migration all landed clean. But estimating / coordination / field
were built fast in Weeks 2–3 as skeletons, never got a depth pass, and were written up as working
modules. Isaac's demo exposed the gap.

**STRATEGIC DECISION (Jacob, 7/20): STOP building new modules. Depth on what exists**, in Isaac's real
workflow order, until he'd *choose* this over his old app rather than tolerate it.

### P0 — churn risk, fix immediately
- **Stage gating removal** (in flight 7/20) — see new **SCOPE §2.8 "Never block the user."** Gating
  becomes advisory + per-tenant `enforce_stage_gating`, default OFF. Split `reached` (semantic) from
  `navigable` (clickable); milestone buttons never disabled; completion shown as a hint. No DB migration.
- **Estimating intermittent failure** — "start on-site visit" didn't advance during a demo; worked later
  on different wifi. Likely network/server-action flake, NOT reproducible. **Watch item:** if it recurs,
  capture browser console + network tab at that moment. Don't hunt it blind.

### P0.5 — SYSTEMIC: coalesce-based update RPCs can't CLEAR a field (found 7/20, Chunk 3)

Every `update_*` RPC in the codebase uses `coalesce(p_field, field)`, i.e. **null means "don't change."**
There is therefore **no way to clear a field back to empty** — only to change it to another value. The
action layer compounds it: `optionalString()` turns `''` into `undefined` → null → coalesce keeps the old
value. **The user clears a field, the UI re-renders showing the old data, and nothing errors.** Silent.

**Same root cause as the `owner_id` "Unassigned" no-op** found during C1 — which had been silently broken
for weeks before anyone noticed. That was one field; this is the pattern.

- **✅ FIXED (7/24) — Isaac's live path.** `update_deal_details` (24-scalar-param, coalesce-based) replaced
  by `update_deal_fields(p_deal_id uuid, p_patch jsonb)`: key absent = untouched, key present (including
  explicit null/`''`) = write it, clearing finally works. Security: server-side allowlist of exactly the
  columns the old RPC exposed — `org_id`/`id`/`owner_id`/`created_at`/`stage`/etc. structurally cannot be
  patched; any unlisted key raises and aborts the whole call (no partial-apply). All four real call sites
  in `src/lib/crm/actions.ts` rewired (`updateDealDetails`, `updateDealColumnField` — Isaac's actual LCC
  path, `updateDealTags`, `updateDealServiceAddress` — the ask named two, grep found four). Verified live
  on synthetic data: text (email via the LCC inline row), numeric (crew_size), array (tags → `'{}'`, not
  reverted), composite address (per-field granularity confirmed). `update_deal_details` dropped
  (20260724130000) once all four were confirmed working — first drop attempt hand-transcribed the 24-type
  signature and silently no-op'd (`IF EXISTS` swallows a signature mismatch); re-ran from the exact
  `pg_get_function_identity_arguments()` string, confirmed gone.
- **Array-clear convention (Jacob, 7/24):** the UI always sends a real `[]` for "cleared," never JSON
  `null` — users can't express "unknown" vs "none" in a multi-select, so the two must never diverge in
  the data. The RPC keeps the three-way capability (absent/null/`[]`); the client just never uses null.
- **contact_name is the one field that keeps old coalesce-ish fallback behavior on purpose** (not a plain
  "empty clears it" field) — see `20260724120000`'s header comment. Preserves the existing
  derive-from-first/last-name behavior that "Contact name (override)" depends on.
- **NULL-authorization gap found in review, fixed in `update_deal_fields`, NOT YET fixed elsewhere:**
  `v_owner_id = auth.uid()` is NULL on an unowned deal, so for a non-manager
  `not (is_org_manager OR NULL)` = `not NULL` = **PL/pgSQL treats a NULL IF condition as false — the
  authorization raise is silently skipped.** Any authenticated org member could edit an unowned deal.
  Fix is `coalesce(v_owner_id = auth.uid(), false)`. **The identical construct is in all eight other
  C3-gated RPCs** (`update_deal_stage`, `archive_deal`, `restore_deal`, `update_intake_checklist_field`,
  `complete_site_survey`, `order_scope`, `present_quote`) **and `assign_deal_owner`'s rep branch — separate
  migration, not bundled with this one.** Verify with a synthetic rep + an UNOWNED deal — the case C3's 13
  scenarios didn't cover (they tested owned-by-someone-else, not unowned).
- **Remaining scope, not yet fixed:** `update_estimate_contact` (all fields coalesce-only);
  `update_estimate_details`'s squares/pitch/site_address/estimate_date/notes_terms (tax_rate/valid_until
  got explicit `p_clear_*` flags in Chunk 3 — 20260723160000 — because they're a numeric/date "one-way
  door"; the rest weren't, on the same reasoning that made contact_name/notes_terms/estimate_date
  exceptions above); the line-item RPCs; `update_production_packet_notes`. Same decision needed: explicit
  `p_clear_<field>` flags per-field vs. the JSONB-patch convention now proven out on deals — decide once,
  don't refight this per table.

### From Isaac's walkthrough tutorial (7/24) — three items

**(a) Contact info must require an explicit Edit action — P1, small.**
Tap-to-edit on established contact fields means a stray thumb silently overwrites a customer's phone
number. **Not a §2.8 violation** — see the §2.8 clarification: fields being *gathered* stay tap-to-edit;
*established reference data* gets an explicit Edit affordance. Apply to the Lead Control Center prospect-
data block (an "Edit lead details" path already exists — route through it) and re-examine the same risk on
the new estimate document's customer/job-site blocks, which are currently tap-to-edit everywhere.
Checklist rows being filled during intake are NOT affected — leave those alone.

**(b) Post-signature edits need change control — INTERIM now, Change Orders backlogged.**
Once a work order is a signed project with approved color/finish, changing scope silently is wrong
commercially (that's what a change order is for). Jacob: **Change Orders is a real feature, backlogged until
the rest of MVP is done.**
*Interim, do NOT lock the fields* — locking without a change-order path would strand the user (§2.6). Instead
**log and surface**: stamp post-signature changes to work-order scope fields (color/finish/materials) in the
activity log with actor, and flag them visually on the record ("changed after sign-off"), the same pattern
as the estimate's "edited since presented." Visibility now, formal process later. The estimate itself already
freezes at `signed` (Chunk 1), so this is specifically about the coordination-module fields downstream of it.

**(c) Admin-assistant role — granular capability flags. P1, real design work.**
Isaac needs a login for an assistant who can see all leads and add notes but **not** see lead value or
estimates. That's **field-level visibility**, which today's role model (screen-level `org_members.role`)
can't express — but SCOPE §5 already anticipates it ("per-module level → granular flags → item-level roles").
Shape:
- `permissions` jsonb on `org_members` (per-tenant, per-user capability flags — fits the config-driven model).
- A SMALL fixed set of capabilities, not per-field toggles, or it sprawls into an unmaintainable matrix:
  `view_financials` (lead value, estimate totals, pricing), `view_estimates`, `edit_leads`, `add_notes`,
  `manage_users`, `view_field`.
- ⚠️ **Enforce SERVER-SIDE — strip the fields in the RPC/query layer, never hide them in the UI.** A
  client-side hide is cosmetic; the data still ships to the browser. `fetch_deal` and the deals list must
  omit `value` entirely for a caller without `view_financials`.
- Interacts with C3 edit-by-ownership — capabilities gate *what you can see*, ownership gates *what you can
  change*. Keep the two orthogonal; don't merge them into one role enum.

### P1 — make the half-built modules real
- **Estimate builder → document-as-editor (Joist model).** Replace the 4-step wizard with a WYSIWYG
  document: the editor IS the PDF the customer receives. Customer + job site pre-fill from the lead;
  line items are the primitive (tap to add description/qty/rate); totals, notes/terms, signature block.
  **Mode toggle: Manual (Isaac's default — type anything, any order) vs Guided** (scope checklist +
  pricing matrix auto-generate line items). *This rescues the checklist/pricing-matrix work — it becomes
  the optional power path instead of the only path.* Mock built 7/20; **get Isaac's reaction before building.**
- **Coordination "sign-off" is a stub.** Today it captures color/finish text and calls it sign-off.
  Needs: real homeowner **signature/initials capture**, a **generated document** attached to the job,
  and **confirmation delivered to the homeowner**. Currently misrepresents what it does.
- **Field module — "cool but clunky."** Open questions to answer from the code, then fix:
  (a) can Isaac (office/owner) create field datapoints or upload roof data himself, or is it crew-only?
  (b) can crew **edit or delete** a file Isaac uploaded? Needs a real per-role file permission model.
  (c) general UX pass.
- **No dashboard / home view.** Nav is pipeline · estimate · coordination · field with no overview.

### P2 — the differentiator: Present Mode (CORRECTED understanding 7/20)
**Present Mode is NOT the estimate rendered nicely.** It's a multi-section **sales presentation that
sells the roof**, walked through with the homeowner on a tablet at the kitchen table, closing with a
signature before you leave. Also printable as a booklet/brochure. Reference: roofdocsstudio.com (18-section
proposal — cover with the customer's home, credentials, testimonials + star ratings, findings/damage
photos, **the roof product itself**, scope in plain language, investment summary, 30/40/30 payment
schedule, warranty, signature).

Most content already exists — Present Mode *assembles* it (no re-entry applied to selling):

| Deck section | Source |
|---|---|
| Cover (customer, address, their home) | lead record |
| Company credentials / branding | tenant config |
| Testimonials, past jobs | **new** (small table) |
| Findings + damage photos | site-visit checklist + field photos |
| **The roof — material, profile, color, gauge, warranty, good/better/best** | roof-type options → product catalog (§12B) |
| Scope of work | site-visit scope checklist |
| Investment summary | estimate line items |
| Payment schedule | **new** (deposit/progress/final on the estimate) |
| Signature | already built |

Tablet-first; printable; **per-tenant template + branding** (§12E/§12F). **Sequencing: estimate builder
FIRST** — the investment summary generates from those line items.

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
- **Follow-ups have no home right now (dormant feature)** — auto day-2/day-5 `follow_ups` are
  still *scheduled* in the DB, but (a) sending was never built (the Make.com scenario is "later"),
  and (b) the Stage-4 Lead Control Center dropped the follow-up *display* the old DealPanel had.
  So they're created, invisible, and inert. Needs a home — a tasks/today view (see BMR's "Coach's
  Calls") and/or re-surfacing on the lead — plus the Make sender.
- **Responsive mobile web shell** — `WorkspaceShell` is desktop-only; needs drawer nav
  + mobile top bar. (In progress as of 7/13.)
- **Coordination schedule-block edit polish** — editing start/end date as two separate
  field-blur submits can transiently violate the `end_date >= start_date` check and
  surface a raw Postgres error in the UI banner. Rare, non-corrupting (final edit saves
  fine). Fix = friendlier error text, or a single two-field "save" instead of per-field
  auto-submit.

---

## Checklists — qualification + site-survey (both in BMR's current app)

Two distinct checklists at two moments (raised 7/14). Features & logic from the BMR app, fresh UI.

- **Qualification / intake checklist** — a structured, completion-tracked checklist gathered on
  **first contact** to qualify a lead (beyond CRM Stage 1's basic fields; BMR stores it as
  `leads.intake_checklist` JSON). **Belongs in CRM Depth** (lead intake) — slot as a CRM stage.
- **Site-survey / scope checklist** — the checklist filled **on the on-site visit**, capturing
  roof scope (trims, boots, vents, penetrations, layers, measurements). **Belongs to ESTIMATING**,
  not CRM: it enhances the on-roof "validate" step and FEEDS both the estimate and the production
  packet; triggered by the CRM-Stage-3 site-visit appointment. BMR spec §5.5.

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

## Deferred from CRM Depth Stage 1 (contact & address data, 7/14)

- **Structured/geocoded project address** — `deals.project_address` ships Stage 1 as plain
  free text (matches the existing `estimates.site_address` precedent). It will want to become
  structured (street/city/state/zip) and geocoded later: EagleView aerial measurement
  (BUILD_PLAN/SCOPE §13 runner-up) needs a real address to query, and crew routing wants
  coordinates, not a string. Not blocking Stage 1 — noted so the free-text choice doesn't
  quietly calcify.
- **Conditional "Company" field by lead type** — the new-lead form always shows Company
  (labeled "if applicable") regardless of homeowner/company selection, rather than
  show/hiding it via client JS keyed off `lead_type`. Cheap polish for later, not Stage 1.

---

## Security workstream (REQUIRED before any client user gets a login — SCOPE §11)

**Now the core of CRM-Depth Stage 5 — full plan + live audit in
`docs/reference/STAGE5_GOLIVE_GATE.md` (audited 7/17).** Corrections from that audit:
- RLS is already enabled on ALL public tables incl. `structtech_state` — that item is **done**.
- The `is_staff()` migration is **mostly unnecessary**: is_staff-only tables are StructTech-internal
  and correctly staff-gated; core member tables already have `my_org_ids()` policies. Don't blanket-rip.
- **The real leaks (RLS on, but policy = `true`):** `audit_leads` (SELECT true), `audits`,
  `proposals`, `prospects` (ALL true), `client_roadmaps` (UPDATE true). PLUS `profiles` +
  `lead_appointments` gated on `is_pipeline_user()` = "any profiled user" (not org-scoped) — both
  leak cross-tenant the moment Isaac gets a profile. All re-scoped in Stage 5 Track A.
- Harden `my_org_ids()` — it's the one helper missing `SET search_path=public`.
- Advisor re-run is the Track-A definition-of-done.

**`client_roadmaps` token-portal leak — its own migration, coordinated with the portal (deferred from Stage 5 Track A, 7/17).** RLS is on but `read roadmap by token` (SELECT) doesn't check the token and `update roadmap milestones` (UPDATE) is `true`/`true` — so anon can read/write **every** roadmap. Deferred from Track A NOT because it's minor (it's a real read/write-all leak on client data) but because **this repo's app never touches `client_roadmaps`** — the external client portal does, and we can't test that codebase here. The correct fix (a security-definer RPC that takes the token + returns/updates only the matching row, or a header/GUC token predicate in the policy) requires a coordinated change to the portal. Not part of the go-live gate: it's pre-existing and Isaac's login doesn't worsen it. **Do soon, with its own reviewed migration + portal coordination + an actual token-flow test.**

**Funnel writes `audit_leads` with `org_id = NULL` (found 7/17 during the Stage 5 smoke-test).**
New StructTech funnel inserts land tenant-less (6 of 7 existing rows have an org only because an
earlier migration backfilled them; a fresh test lead came in null). Not a gate breach — null-org
rows are invisible to org-scoped members (Isaac can't see them) and only surface via the
`is_staff()` catch-all, which is why they appear across *Jacob's* dual-membership/staff view. Fix:
the funnel should stamp `org_id = StructTech internal org` on insert; since that's the external
funnel codebase, stopgap = a `before insert` trigger / default on `audit_leads` setting the
StructTech org when null (revisit if/when a second tenant gets its own capture funnel — then it must
route by funnel, not a hardcoded default). Data-routing fix, separate from the Track A security gate. **Root cause confirmed 7/17:** the writer
is Jacob's *previous standalone StructTech OS app*, still pointed at the same prod DB — it predates
the org model, so its inserts don't set org_id.

**Old standalone StructTech OS app = a second, ungoverned door into the prod database (strategic,
pre-scaled-go-live).** The prior StructTech app shares the production Supabase project and reads/writes
the same tables (audit_leads, audits, prospects, proposals, …) outside the new multi-tenant access
model. Benign today (only Jacob uses it; he's staff/platform-admin so Track A didn't break his views),
but it's the unfinished half of the "standalone → one platform" merge. Decide its fate before scaled
client go-live: decommission (platform absorbs the funnel intake), or migrate its capture path to write
through the platform (stamping org_id). Until then, the null-org stopgap trigger above covers the data.

**Edit-by-ownership is RPC-level only — tighten RLS before onboarding non-manager reps (from C3, 7/19).**
Track C3 gates the mutating RPCs (`is_org_manager(org) OR owner_id=auth.uid()`), but the `deals` (and
child `deal_notes`/`deal_activity`/`estimates`/etc.) UPDATE RLS policies are still org-level
(`org_id IN my_org_ids()`), so a rep could bypass the gates entirely via a direct PostgREST table write.
Doesn't matter for Isaac (manager-tier, solo). Before any non-manager rep gets a login, make the
`deals` UPDATE policy owner-aware (`... AND (is_org_manager(org_id) OR owner_id = auth.uid())`) — after
confirming the app writes deals ONLY through the definer RPCs (grep), since definer RPCs bypass RLS and
won't be affected. Also: `update_deal_details.p_owner_id` is now vestigial (ownership goes through
`assign_deal_owner` only) — drop the param in a future signature-change cleanup (DROP-first + types regen).

Still open, lower priority (post-go-live):
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
- **Intermittent session bounce to `/select-workspace` (INVESTIGATE — real-user risk)** —
  recurs across sessions: a mid-interaction request occasionally redirects to the workspace
  picker (looks like a transient session/auth-refresh miss in middleware or `getSession`).
  Harmless in testing (re-navigate), but a user bounced mid-form loses their input. Not a
  one-off — worth a real root-cause pass (middleware refresh timing / cookie race).
- **Docs section** — one place to view / download / send work orders + estimates (signed or
  not), later invoices + packets. Ties to the tenant-customizable document-template system
  (SCOPE §12E). Jacob: "add to later build if needed."

---

## From phone testing (7/16) — Lead Control Center fix-pass caveats

- **Roof-type multi-select needs a touch-friendly picker** — the seeded `existing_roof_type` /
  `roof_type_requested` dropdowns render as a native `<select multiple>`, which requires
  ctrl/cmd-click on desktop (fine-ish on mobile, which shows a tappable list). Acceptable v1
  per "editable later via the editor," but a proper chip/checkbox picker is the real fix.
- **Two legacy BMR deals hold `project_address` only** (no structured address). The read-only
  "(legacy)" hint in EditLeadDetailsForm surfaces the value so Isaac can re-enter it structured;
  once he does, the free-text value is unused. Not a migration — just cleanup Isaac can do himself.

---

## Self-serve password reset — "Forgot password?" (raised 7/19, confirmed needed)

`/login` is email+password only with **no recovery path** — a forgotten password today means Jacob
resetting it from the Supabase dashboard. Fine at one client, untenable at ten. Not a Monday blocker
(Isaac gets a password via dashboard recovery), but the next auth work after go-live.

Shape:
- `Forgot password?` link on `/login` → **`/forgot-password`**: email input → `resetPasswordForEmail(email,
  { redirectTo: <SITE_URL>/reset-password })`. Always show the same "if that email exists, we sent a link"
  confirmation — never reveal whether an account exists (account-enumeration leak).
- **`/reset-password`**: new-password form → `updateUser({ password })` → redirect to `/select-workspace`.
- ⚠️ **The fiddly part — the callback.** Supabase recovery links use PKCE / `token_hash`; with the SSR
  client the token must be exchanged for a session in a route handler (`/auth/confirm` or
  `/auth/callback`) before `/reset-password` can call `updateUser`. Skipping this is the usual reason
  reset "silently does nothing." Follow CLAUDE.md rules 1–2 (`getSession()`, server `createClient()`).
- Redirect allow-list already covers it via `https://os.structtek.com/**` (set 7/19).
- Also worth it then: **email deliverability** — Supabase's built-in mailer is rate-limited and lands in
  spam. Resend is already in the stack (CLAUDE.md §Tech stack); wiring it up as custom SMTP makes both
  recovery AND invites reliable. Do these together.

## First-timer onboarding tour (raised 7/19 — hold until after Isaac's Mon walkthrough)

A first-login product tour (coach-marks/tooltips highlighting each area + how it relates to others),
built with a React tour lib (Driver.js / React Joyride), anchored to elements, with a per-user
"completed" flag on `profiles` so it fires once. **Must respect module entitlements** (only tour areas
the tenant has). Plus a **Settings → Tutorial tab** to replay the walkthrough at any time.
Start with the LIGHTWEIGHT version (one first-login tour of the main areas, ~6–10 steps), not
per-area contextual tips (much more surface to maintain). Down the road the tour content can be
tenant-configurable (§12F). Scope it AFTER watching Isaac use the system live Mon — target real
friction, not guessed friction. Self-contained; no data-model/security touch.

## Larger future capabilities (already recorded — SCOPE §12 North Star / §13)

- Editable document-template system + **invoices** + **work orders** (SCOPE §12E).
- **Configurable-platform / self-serve customization epic (SCOPE §2.7 + §12F — the core value prop).**
  Tenants self-onboard and shape the platform to their operation, via authoring UIs (backlog) over
  config the engine already reads:
  - **Editable pipeline stages** — add / edit / delete / reorder stages like any real CRM (config is
    already per-tenant in `tenant_modules.config.stages`; needs the CRUD authoring UI + full CRUD support).
  - **Multiple pipelines, of different TYPES** — not just one sales pipeline: campaign pipelines,
    marketing/automation pipelines, custom. Each tenant has N pipelines, each typed, each with its own
    stages (and eventually its own record type). *Data-model guardrail (do now): don't hard-wire
    "one pipeline per tenant" — records must be able to carry a `pipeline_id` additively later, and the
    sales pipeline is "the default pipeline," not the only one.*
  - **Tenant-authored checklists / stages / fields / data points** (§12F). *(Definitions are config
    today; the deeper step — stage completion/derivation/gating **conditions** expressed as config too
    (a small rules layer) — lands when tenants need fully custom stages beyond the fixed milestone-column
    model. Today those bindings stay in the engine code, on purpose.)*
  - **Pricing-matrix / estimate-logic tool** — map checklist data points → pricing rules → estimate line
    items (BMR's `scope-fields.ts` `intake_scope_key` → product is the reference). Hooks laid now: stable
    scope keys + `product_id` on line items.
  - **Self-serve tenant onboarding** at scale (hundreds of tenants) — activation = config, not engineering.
  The UIs are incremental/backlog; the **data model must never hard-wire a single tenant's shape.**
- AI assistant + semantic search (§12A) · client product catalogs + inventory (§12B) ·
  StructTech shop / distribution integration (§12C) · native mobile app (§12D).
- Integrations: Google Workspace, Twilio, Stripe (§13); QuickBooks + aerial roof
  measurement (runner-ups).

---

## Remaining planned phases (BUILD_PLAN_3WEEK.md)

- **Week 3:** coordination (work order → materials → schedule) + field module +
  delivery/portal — the "clarity" layer.
