# StructTech OS — Rollout Checklist (task-level working doc)

**The in-app Build Tracker (`/w/[orgId]/build`, live 7/24) is now the authoritative source for FEATURE
STATUS.** This file is the subordinate **task-level breakdown** — the build steps under each tracker
feature that the coarse tracker rows don't capture. As each feature is executed, its task detail migrates
into that tracker item's `notes`, and this file shrinks toward retirement. Don't track feature *status*
here — do that in the app. `ROADMAP_MATRIX.html` is retired (superseded by the tracker).

**Update rule (from ROADMAP):** reconcile at each phase boundary and **before any bug-fix detour** (so we
know where to resume).

Legend: `[x]` shipped · `[~]` in progress · `[ ]` not started.

---

## ✅ Shipped & live (the current base)

- [x] Foundation — auth, pooled multi-tenancy, workspace shell, roles + entitlements
- [x] Security gate — RLS leaks closed, Isaac seeded as BMR owner (BMR-scoped), attribution, edit-by-ownership
- [x] BMR data migrated — 188 leads + 171 notes + 587 activity, attribution preserved
- [x] CRM / Lead Control Center — 3-panel, form==checklist, config-driven stages
- [x] Gating removed — advisory only, `enforce_stage_gating` default off (§2.8)
- [x] Estimate builder — document-as-editor, Manual/Guided, PDF parity, Present Mode
- [x] Coordination (base) — sign-off gate → work order → materials → schedule (sign-off is a stub, see A)
- [x] Field (base) — crew check-ins, production packet, outdoor mode
- [x] Recent fixes — contact-edit affordance, post-sign-off logging, coalesce/clear on deals, NULL-auth gap

---

## Phase 0 — In-app Build Tracker (PULLED FORWARD, building now, ~1 day)

Built before Phase A so tracking is a single attributed in-app source, not scattered files.
- [ ] `roadmap_items` table + `module_key='build'` entitlement for StructTech (internal) only
- [ ] Patch-based update RPC + create/delete, actor-stamped `updated_by` (attribution)
- [ ] Nav + route (`/w/[orgId]/build`), StructTech workspace only; grouped matrix table UI; full CRUD
- [ ] Seed ~65 items from `ROADMAP_MATRIX.html` data array (status: shipped for Now, planned for future)
- [ ] Verify: a contractor (BMR) can't see the build module (entitlement + RLS probe)
- [ ] Once live: this checklist + the matrix move into the app; files retire → **return to Phase A Week 1**

---

## Phase A — Finish the depth pass (make what exists real)

**Week 1 — Assistant role + P0.5 close-out + email**
- [ ] Assistant capability role: `permissions` jsonb on `org_members`; fixed capability set
- [ ] Server-side field-stripping (hide `value`/estimates for callers without the flag) — NOT UI-hiding
- [ ] Resolve edit_leads × C3 ownership · capability × role precedence · edit × view_financials
- [ ] P0.5 close-out: apply JSONB-patch/clear convention to estimate, line-item, production-packet RPCs (decide once)
- [ ] **Pull Resend/SMTP forward** — reliable transactional email (unblocks remote-sign, reset, invites)
- [ ] Self-serve password reset (`/forgot-password` + `/reset-password` + PKCE callback)
- [ ] Bug lane

**Week 2 — Signing system + real coordination sign-off**
- [ ] Remote/email signing: tokenized link → customer signs on their device → OS status sync
- [ ] Auto-email the signed copy back to the customer
- [ ] Coordination: real homeowner signature capture (in-person + remote), generated signed doc on the job
- [ ] Deliver the signed coordination doc to the homeowner
- [ ] Bug lane

**Week 3 — Field depth + a home**
- [ ] Field: can office/owner (Isaac) create field data / upload roof data himself?
- [ ] Field: per-role file permissions (can crew edit/delete a file Isaac uploaded?)
- [ ] Field: general UX pass
- [ ] Dashboard / home view (open leads, today's schedule, recent activity)
- [ ] Bug lane

**Phase A exit:** Isaac would *pick* StructTech OS over his old app for his whole day, no stubs hit.

---

## Phase B — Present Mode as a real sales deck

- [ ] Multi-section deck shell (cover → credentials → findings → product → scope → investment → payment → sign)
- [ ] Testimonials / past-jobs (new small table)
- [ ] Payment schedule (30/40/30) on the estimate
- [ ] Product section (roof profile / color / gauge / warranty / good-better-best)
- [ ] Assembles from existing data (lead, checklist+photos, roof-type, line items) — no re-entry
- [ ] Tablet-first + printable booklet + per-tenant branding
- [ ] Bug lane

---

## Phase C — Second-client readiness + customer portal

- [ ] Config editor — tenant self-edits stages / checklist fields / dropdown options
- [ ] Pricing matrix — checklist data points → pricing rules → estimate line items
- [ ] Edit-by-ownership at the RLS layer (before any non-manager rep login)
- [ ] Stand up a second contractor tenant ("StructTech Test Co") — prove onboarding = config
- [ ] **Customer / homeowner portal v1** — external actor access model (tokenized per-job / light accounts) + signed docs + schedule + status  *(⚠️ heavy: new actor class — see BACKLOG; Jacob to confirm if it pulls ahead of B)*
- [ ] In-app Build Tracker module (this checklist, dogfooded) — optional slot here
- [ ] Bug lane

---

## Phase D — Integrations + maturity

- [ ] Google Workspace (OAuth sign-in, Calendar two-way sync, Gmail CRM follow-up sends)
- [ ] Twilio SMS (instant lead response)
- [ ] Stripe billing (tenant subscriptions — the $20K MRR path)
- [ ] Docs section (view / download / send all work orders + estimates)
- [ ] Follow-ups get a home + sender (currently scheduled but inert)
- [ ] First-timer onboarding tour + Settings tutorial tab
- [ ] Bug lane

---

## Parking lot — real, not yet sequenced

- [ ] Cross-job crew Gantt (VITAL — master schedule across all jobs/crews)
- [ ] Site-visit / appointment scheduling (calendar) · table + calendar CRM views · global search · next-action chip
- [ ] R2 file storage (estimate PDFs + field photos at volume) · annotated trim-map
- [ ] Homeowner portal v2 (photos + progress timeline) · v3 (homeowner confirms/schedules)
- [ ] Qualification + site-survey checklists · roof-type touch picker · `/select-workspace` bounce root-cause
- [ ] Security debt: `client_roadmaps` token leak · funnel null-org stopgap · decommission old standalone app
- [ ] Multiple pipeline types · self-serve onboarding at scale · editable doc templates + invoices
- [ ] North Star: AI assistant · product catalogs · StructTech shop · native mobile app
