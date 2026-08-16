# STRUCTTECH OS — DIRECTIVE
## Single source of truth for the build

**Version:** 1.3 · **Updated:** 2026-08-16
**Supersedes:** `PHASE_A_PRODUCTION_CORE_SCOPE.md`, `BACKLOG.md`, `CLAUDE_MD_BUILD_DIRECTIVE.md`, `StructTech-OS-Six-Week-Build-Map.md`, `StructTech-OS-Remaining-Build-Map.md`, `StructTech-OS-Build-State-Aug2026.md`. Those documents are archived. **This file wins over all of them, over the Build Tracker, and over anything said in chat.**

---

# 0 · HOW TO USE THIS DOCUMENT

This is the only document that has to be read before making a change. Read §1 to know where we are, §2–§4 to know the rules, then execute.

### If this is a new chat, start here

Read **§1 (Current Position)** and **§11 (Active Execution Week)**. Between them they answer "where are we" and "what am I doing today" without any other context. Then proceed.

### The instruction is "execute the next step." Here is what that resolves to:

1. Read the **Current Position** block in §1.
2. The next step is the **lowest-numbered task in the lowest open stage** whose dependencies are met and which is not blocked.
3. Execute exactly that task. Not the stage. Not the next three tasks. One task.
4. Verify it against its **Done when** line. If it doesn't pass, it isn't done.
5. Update §1 (Current Position) and §10 (Change Log) in this file.
6. Update `roadmap_items` status in the Build Tracker to match.
7. Report: what was done, what the verification showed, what the next step now is.

### Rules that override preference

- **If a request doesn't map to a task in §5, it doesn't get built.** It goes to §6 (Backlog) and you say so.
- **If a task's *Done when* depends on something not written in §5, this document is wrong.** Fix the document first, then build. Never fill the gap silently in code.
- **Reuse what exists.** See §4.3. Extend shipped objects; do not create parallel ones.
- **Stage order is dependency order, not calendar.** A stage closes when every task's *Done when* passes.
- **One task per execution.** Multi-task batches hide failures.
- **Blocked means stop and report.** Do not route around a blocker with a temporary shape that will need migrating later.

---

# 1 · CURRENT POSITION

> **Update this block after every completed task. It is the pointer that makes "execute the next step" unambiguous.**

| | |
|---|---|
| **Phase** | A — Production Core |
| **Stage** | A1 — Job Spine |
| **Last completed task** | **A1 Foundation (partial, 2026-08-16)** — anon exposure closed by moving both colour-normalisation backups to a private `archive` schema (migration `archive_wh_color_normalization_backups`); security advisors verified clean of `rls_disabled` and all ERROR-level findings; coordination RPC surface inventoried and corrected from 14 to 27 (§4.4). |
| **Outstanding from Foundation** | (1) Land this directive as `docs/STRUCTTECH_OS_DIRECTIVE.md` + pointer in `CLAUDE.md`. (2) CLI is authenticated to the wrong Supabase org and the project is not linked — no DB credentials available locally. (3) Take a verified backup. (4) **NEW — A1.0 migration baseline**, see §4.7. (5) Cut the A1 branch. **A1.1 must not start until A1.0 closes and a backup exists.** |
| **NEXT STEP** | **A1.0 — Migration baseline reset** (§5.1) |
| **Blocked** | Nothing in A1. Assistant-role seed is blocked externally (tenant must supply a name + email) and is not on the critical path. |
| **Phase opened** | 2026-08-16 |
| **Phase gate** | §5.6 — golden path run twice, second run crew-driven |

**Production reality check (verified 2026-08-16):** everything through signature carries real data — 198 deals, 4 estimates (3 signed), 4 signatures. Everything after signature is at **zero rows**: `material_items`, `schedule_blocks`, `check_ins`, `production_packets`, `work_order_activity`. That gap is what Phase A closes, and it is why the schema is still cheap to change.

---

# 2 · WHAT THIS IS

StructTech OS is a **pooled multi-tenant, config-driven operating system** for contracting businesses. The same engine serves different trades and different business shapes; what a tenant sees is decided by an entitlement row, not a fork of the code.

Proven in production today: two orgs run two entirely different pipelines from one engine — a contractor tenant (New Lead → Qualified → Site Visit → Estimate Presented → Negotiating → Won, with a roofing scope-to-line-item pricing map) and the internal tenant (New Scan → Contacted → Call Booked → Call Done → Proposal Sent → Won). Same code, different `tenant_modules.config`.

**Tenant types in use:** `internal` (StructTech) · `contractor` (pilot roofing tenant) · `supplier` (Material Matrix).

**The product goal Phase A serves:** an all-in-one where a tenant can cancel their estimating tool, their photo tool, their notes tool, and their crew-messaging workaround, and nothing in their day breaks.

---

# 3 · DECISIONS OF RECORD

Binding. Changing one is a scope change, recorded in §10 — not an implementation detail.

**D1 · Job / work order hierarchy.** A signed estimate may span multiple trades. The **job** is the container: one service address, one signed estimate. The **master work order** carries the full production scope and the homeowner's colors-and-finishes sign-off. **Trade work orders** are generated from the master and issued to an in-house crew, an internal department, or an external subcontractor. A trade work order's assignee MAY be external — the tenant is frequently a subcontractor themselves.

**D2 · Catalog ownership and Material Matrix.** Every tenant builds and owns their own catalog of products and services, including items Material Matrix does not carry. **MM integration is entitlement-gated and enabled per tenant on request only.** No supplier-specific integrations in Phase A; purchase orders are supplier-agnostic records. *Rationale: the observed failures — trim ordered against consumed shop stock, a fabricator's undelivered promise — were caused by a missing record, not a missing integration.*

**D3 · Standards library ownership.** Three layers: `baseline` (authored and owned by StructTech, trade-specific, versioned) → `overlay` (tenant adopts, overrides, or disables; private to them) → `exception` (this job, this reason, client notified). Pilot field data is a jumpstart for the baseline, not the tenant's property.

**D4 · "No standard yet" is a first-class state.** `gap` → `draft` → `active` → `superseded`, plus `disputed`. A `gap` is a known-unknown with an owner, visible in the UI. Every standard carries **provenance** — the incident that produced it.

**D5 · Depth before breadth.** Phase A completes the production spine on the pilot tenant before Phase C onboards a second contractor tenant.

**D6 · Material Matrix launches standalone, migrates to a module in Phase C.** (2026-08-16) MM goes live now as its own front end and its own brand, on **the shared `structtech` backend** — same Supabase project, same `organizations` row (`tenant_type='supplier'`), same `org_id` + RLS model, same auth namespace. It is a **separate app, not a separate system.** Migration to a module later is therefore a front-end consolidation plus a `tenant_modules` entitlement, not a data migration.

*Conditions that keep that true — violating any one of these converts a Phase C consolidation into a data migration:*
1. The shop front end points at `ejlhrykcdfcyeooooodx`. **Never launch against the legacy project.**
2. No parallel auth. Shop customers live in the same auth namespace as OS users.
3. `org_id` + RLS stay on every `wh_*` table.
4. Catalog is extended, never forked. Tenant pricing (cost/sell/markup, A2.1) is a **layer on top of** the shared catalog, not a second product table.
5. MM keeps its own Stripe merchant account. StructTech's own billing (Phase D) stays separate. Split payouts remain backlogged.

*Standing risk:* going live creates a real support and fulfilment obligation that competes with Phase A execution capacity. MM support load is not Phase A work and does not pause the A-stage sequence.

**D7 · Operating model.** The controller (Claude in the StructTech OS project) does research, coordination, and holds this directive. The coder (Claude Code) executes all repo and database work. **No database or schema change is made outside the repo.** The controller may read the database for investigation; it does not write to it.

---

# 4 · SYSTEM STATE OF RECORD

## 4.1 Shipped and carrying data
CRM pipeline (config-driven stages, Lead Control Center, ownership, author attribution, free navigation, full edit/delete) · estimating (document-as-editor, manual lines, guided mode from scope keyed off `build_mode`, PDF at parity, atomic per-org estimate numbering) · in-person e-signature · present mode · pooled multi-tenancy with entitlements · owner/manager/member roles · edit-by-ownership at the RPC layer · email-and-password auth with invites · capability flags (deployed and verified under authenticated-role probes).

## 4.2 Shipped and never exercised
Coordination (sign-off gate → work order → materials, material ready-by gating schedule, change-after-sign-off audit trail) · scheduling (per-work-order crew and dates) · field (crew check-ins, visual production packet, outdoor mode). **All at zero rows.**

## 4.3 Exists — reuse, do not rebuild
| Object | What it already does |
|---|---|
| `work_order_agreements` | Versioned sign-off: original + each change order as its own row, one active, void-and-replace |
| `schedule_blocks` | Has `blocked` + `blocked_reason` — a blocking model exists |
| `material_items.ready_by` | The gate between material and schedule |
| `estimate_line_items.product_id`, `.scope_key`, `.unit` | The hook from catalog → priced line, and scope answer → line |
| `signatures.sign_token`, `work_order_agreements.sign_token_hash`, `.sent_at` | Remote-signing groundwork already in schema |
| Capability-flags mechanism | The lever that hides dollars from a role — use it for crew surfaces |
| `tracker_items.reported_by_org_id` | A tenant can already file into StructTech — extend for field-raised tickets |
| `deals.intake_checklist`, `.site_survey_complete_at`, `.roof_scope_ordered_at` | Partial discovery capture |

## 4.4 Blocking fact for A1
`work_orders` carries **`work_orders_estimate_id_key UNIQUE (estimate_id)`**. One-work-order-per-estimate is enforced *in the database*. Dropping it is the first statement of the first Phase A migration.

**Verified against the live database 2026-08-16: the coordination RPC surface is 27 functions, not 14.** The earlier count missed the child-of-child functions. Each must declare its level:

| Level | Count | Functions |
|---|---|---|
| **REPLACE** | 1 | `create_work_order_from_estimate` → split into `create_job_from_estimate` (job + master) and `create_trade_work_order` |
| **MASTER** | 3 | `record_work_order_sign_off` · `create_work_order_agreement` · `fetch_work_order_agreement` |
| **TRADE** | 6 | `add_material_item` · `update_material_item` · `delete_material_item` · `add_schedule_block` · `create_check_in` · `get_or_create_production_packet` |
| **BOTH — hierarchy-aware** | 4 | `fetch_work_order` · `void_work_order` · `restore_work_order` · `delete_work_order` (voiding a master voids its trades) |
| **INHERIT — verify only** | 13 | Operate on a child id, not `work_order_id`, so they inherit their level from their parent: `add_check_in_photo` · `remove_check_in_photo` · `update_check_in` · `delete_check_in` · `fetch_check_in` · `update_schedule_block` · `delete_schedule_block` · `fetch_production_packet` · `delete_production_packet` · `update_production_packet_notes` · `add_production_packet_callout` · `update_production_packet_callout` · `delete_production_packet_callout`. **No signature change expected — but each one's org/authorization path must be re-verified against the new hierarchy.** |

A1.3 covers the first four rows (14 functions). The INHERIT row is a verification pass, not a rewrite, and belongs in A1.4.

## 4.5 Target object model (end of Phase A)
```
Client ──< JOB (service address + signed estimate)
            ├── Estimate ──< estimate_line_items (product_id → tenant catalog)
            │                  └── Invoice ──< payments (deposit · schedule · status)
            ├── MASTER WORK ORDER ── homeowner sign-off (colors & finishes)
            │        └── work_order_agreements            [EXISTS]
            └──< TRADE WORK ORDER (roof · siding · gutters · soffit/fascia)
                     ├── assignee: crew | department | subcontractor (external allowed)
                     ├── predecessor → trade_work_order   [field only in A1]
                     ├──< material_items ──< purchase_order (supplier, committed_date)
                     │         ├── stock_reservation → consumption
                     │         └── delivery → receipt_check
                     ├──< schedule_block                  [EXISTS]
                     ├──< daily_objective
                     ├──< check_in                        [EXISTS]
                     │         └── special_trip (tool | material | reason)
                     ├──< qc_item
                     ├──< standard_ref → STANDARDS (baseline → overlay → exception)
                     └──< cost_line (sub/labor · material actual · rework) → margin
```

## 4.6 Infrastructure
Supabase `structtech` (`ejlhrykcdfcyeooooodx`), Postgres 17 · Edge Functions: `process-order` v12, `create-payment-intent` v16, `stripe-webhook` v8 · app at `os.structtek.com` · shop at `shop.thecontractingco.com` · hosting Vercel (a doc conflict says Netlify elsewhere — resolve, see §6.9) · Make.com scenario 4496216 is MM's driver/customer email; **scenario 4589058 is StructTech-internal, do not modify** · legacy Supabase project pending sunset.

## 4.7 Repo/database migration divergence — BLOCKING FOR A1

**Discovered 2026-08-16 by Claude Code during the Foundation task. This is the most consequential finding of Phase A so far.**

The repository is **not** a reliable record of the database schema:

- **46 local migration files vs 69 remote entries. Zero version matches.** Local filenames use synthetic timestamps (`…120000`, `…130000`); the database recorded real applied times. `supabase migration list` reports every row as divergent.
- **39 of 69 remote migrations have no local file at all.**
- The entire `wh_*` series — roughly 20 migrations from `wh_supplier_catalog_landing_zone` (2026-08-01) through `wh_order_number_sequence_authoritative` (2026-08-15) — exists **only in the database**. The Material Matrix catalog work was applied outside the repo.
- `archive_wh_color_normalization_backups` (2026-08-16) is the tail of that pattern, not an isolated event.

**Why this blocks A1:** A1 is a schema change delivered as a repo migration. If the repo cannot represent current schema state, Claude Code cannot safely reason about what exists before altering `work_orders`. Reconciliation is a prerequisite, not cleanup.

**Second finding — wrong Supabase account.** The local CLI is authenticated to org `fxtcnutwrdhzmofpmaww` (projects `bmr-lead-pipeline`, `structtech-x-windyhill`) — almost certainly the legacy org. Production `structtech` (`ejlhrykcdfcyeooooodx`) lives in org `atutgdfktddukxabhrrj` and is not visible to the CLI. There is no `supabase/config.toml`, so the project was never linked, and `.env.local` carries only the public URL and anon key — no service-role key, no connection string. Use `--profile` when authenticating so the legacy credential in the macOS Keychain is preserved.

**Third finding — no restore target.** No local Postgres, no Docker. "Verify it restores" has nowhere to restore to until one exists. Object-count verification is the accepted fallback and must be reported as weaker than a real restore test.

**Fourth finding — direct connection unusable.** `db.ejlhrykcdfcyeooooodx.supabase.co` is IPv6-only and the build machine has no IPv6 egress. Use the **Session pooler** connection string (IPv4, port 5432). Not Direct, not Transaction pooler (6543 cannot serve `pg_dump`).

---

# 5 · PHASE A — PRODUCTION CORE

Six stages, dependency-ordered. **A stage closes when every task's *Done when* passes.**

| Stage | Name | Depends on |
|---|---|---|
| A1 | Job Spine | — |
| A2 | Materials & Purchasing | A1 |
| A3 | Standards & Capture | A1 |
| A4 | Field Execution | A1, A3 |
| A5 | Money | A1, A2 |
| A6 | Client Loop & Proof | all |

---

## 5.1 · Stage A1 — Job Spine

**A1.0 — Migration baseline reset** *(added 2026-08-16 — prerequisite to everything else in A1)*
Reconcile the repo with the database so the repo becomes the source of truth for schema going forward. **Decided approach: baseline reset, not backfill — do not reconstruct the 39 missing migration files.** Authenticate the CLI to the correct org using `--profile`, link the project, take a verified backup first, pull the current remote schema as a single new baseline migration, move the 46 stale local files to `supabase/migrations/_archive_pre_baseline/` (move, do not delete), and use `supabase migration repair` to mark prior remote migrations as applied. Every migration from A1.1 onward originates in the repo.
**Done when:** `supabase migration list` shows local and remote in agreement, the baseline migration is committed, and a trivial reversible schema change made in the repo applies cleanly to the database and reverts.

**A1.1 — Schema: jobs + work order hierarchy**
Drop `work_orders_estimate_id_key`. Create `jobs` (`id`, `org_id`, `deal_id`, `estimate_id`, service address, timestamps). Extend `work_orders` with `job_id` (nullable → NOT NULL), `kind` (`master`|`trade`), `trade`, `assignee_type` (`crew`|`department`|`subcontractor`), `assignee_ref`, `predecessor_id` (self-FK, nullable). Backfill the 2 existing rows as masters with jobs derived from their estimates. Add: one master per job.
**Done when:** both existing work orders resolve to a job with `kind='master'`, `job_id` is NOT NULL, and a second work order can be inserted against the same estimate.

**A1.2 — RPC split: creation**
Replace `create_work_order_from_estimate` with `create_job_from_estimate` (creates job + master) and `create_trade_work_order` (creates a trade under a master).
**Done when:** one signed estimate produces a job, a master, and three trade work orders, one of them assigned to an external subcontractor.

**A1.3 — RPC re-pointing: children**
Re-point `add_material_item`, `update_material_item`, `delete_material_item`, `add_schedule_block`, `create_check_in`, `get_or_create_production_packet` to **trade** work orders. Re-point `record_work_order_sign_off`, `create_work_order_agreement`, `fetch_work_order_agreement` to **master**.
**Done when:** a material item cannot be attached to a master, and a sign-off cannot be recorded on a trade.

**A1.4 — Hierarchy lifecycle**
`void_work_order`, `restore_work_order`, `delete_work_order`, `fetch_work_order` respect the hierarchy. Also re-verify the 13 INHERIT functions in §4.4 against the new hierarchy.
**Done when:** voiding a master voids its trades; restoring restores them; deleting a master with children is refused or cascades explicitly; no active agreement is orphaned.

**A1.5 — Crew visibility**
The master is not visible to crew-role users; trades are. Enforced via capability flags at RPC and RLS.
**Done when:** a crew-role probe can read its trade work order and cannot read the master or any dollar value.

---

## 5.2 · Stage A2 — Materials & Purchasing

**A2.1 — Tenant catalog.** Tenant-owned products and services: name, unit, cost, sell, markup, category, active. Tenant may create items freely, including items MM does not carry. Joins `estimate_line_items.product_id`.
**Done when:** a tenant with MM disabled builds a catalog and prices an estimate line from it.

**A2.2 — Take-off generation.** Estimate line items → `material_items` on the correct trade work order, no re-entry.
**Done when:** a signed estimate produces a take-off with zero manual entry.

**A2.3 — Purchase orders.** Supplier (free-text or catalog-linked), `committed_date`, promise-vs-actual history, status. Committed date populates `material_items.ready_by`.
**Done when:** a PO's committed date sets `ready_by`, and `ready_by` blocks the schedule block.

**A2.4 — Stock reservation and consumption.**
**Done when:** stock reserved on job A and consumed on job B raises a flagged shortfall on job A **before** its install date.

**A2.5 — Delivery and receipt check.**
**Done when:** a delivery received short of the take-off raises an exception visible to the office the same day.

**A2.6 — Material Matrix integration (entitlement).** `tenant_modules` module key gates catalog reads and 1-click purchasing. Off by default.
**Done when:** enabling the entitlement for one tenant exposes MM purchasing without changing any other tenant.

---

## 5.3 · Stage A3 — Standards & Capture

**A3.1 — Standards schema.** `layer` (`baseline`|`overlay`|`exception`), `owner_org_id`, `trade`, `phase` (pre-construction · tear-off · dry-in · trim · install · flashing · cleanup · closeout), `state` (`gap`|`draft`|`active`|`superseded`|`disputed`), `version`, `supersedes_id`, `body`, `language`, `provenance`, `owner_user_id`.
**Done when:** an overlay overrides one baseline item without altering the baseline, and superseding preserves the prior version and its provenance.

**A3.2 — Baseline seed.** Seed from the 2026-08-10 install-standard record: pre-construction determinations (deck, ventilation, penetrations, chimney, rake square, interior protection, inspectable vs uninspectable) · tear-off (plant/hardscape/siding protection, no dragging, pipes painted, chimney mortar ground, ridge cut open with ¾″ both sides of a ridge pole or 1½″ total, deck verified after tear-off, penetrations marked on underlayment) · dry-in (no cap nails under metal, 1¼″ nails for ice & water, staples for synthetic, underlayment extends 1–1½″ past the edge and is nailed) · trim (roof trim layout map to the crew) · install (chalk quarter/half/quarter, equal starter and finisher, penetrations centered in panel, expansion clips over 20 ft, clips 18″ o.c., three rivets at ridge-cap terminations, rake edge ½″ past drip edge square) · flashing (grind mortar not brick, caulk before and after, hot-pipe boots caulked inside the boot) · cleanup (magnet sweep by segment including gutters and landscaping).
Five items enter as `gap`: drip-edge gutter gap · ridge-cap/valley junction below the main ridge · rib matching in valleys and hips · screws per clip · high-temp pipe paint.
**Done when:** baseline v1 exists and the five gaps are visible with owners.

**A3.3 — Checklist taxonomy.** `daily` vs `project` checklists generated from standards for a phase; plus `documentation_items` (recorded facts, not gates).
**Done when:** a specialty-tool need appears on a project checklist and not on the daily, and a special trip is recorded as a documentation item.

**A3.4 — Bilingual rendering.** By user profile (`en`|`es`), no toggle.
**Done when:** a crew checklist renders in Spanish from the same source record as the English one.

**A3.5 — Capture to draft.** Transcript or voice-note text → `draft` standard requiring approval. Manual paste is sufficient for A3; automated ingestion is Phase B.
**Done when:** pasted text becomes a draft that cannot go `active` without approval.

---

## 5.4 · Stage A4 — Field Execution

**A4.1 — Daily objective.** Per trade work order, per date; published by the office or derived from schedule plus prior-day exceptions.
**Done when:** a crew member opening the app sees today's objective without asking anyone.

**A4.2 — Special trips.** Type (`tool`|`material`|`other`), reason code, impact. The phase's primary leading indicator.
**Done when:** logged in ≤2 taps and visible on the office dashboard the same day.

**A4.3 — QC items.** Required photo by intersection type, countable checks, sweep confirmations; blocking vs advisory.
**Done when:** the day cannot close with a blocking QC photo missing.

**A4.4 — Production packet v2.** Roof map, trim layout map, colored expansion-clip zones, callouts.
**Done when:** a crew installs expansion clips in the right zones without asking, from the packet alone.

**A4.5 — Acknowledgment.** Who opened the work order, when.
**Done when:** the office can prove the crew received the current version.

**A4.6 — Crew model.** Person (skill, language, vehicle, availability), crew membership, assignment to trade work orders.
**Done when:** the scheduler refuses to assign a crew with no vehicle to a job requiring transport.

**A4.7 — Office-side upload + per-role file permissions.**
**Done when:** roof data and photos load from the office and a crew role cannot delete them.

**A4.8 — Adoption instrumentation.** Opens, completion rate, time-to-complete.
**Done when:** a week of field use produces a completion-rate number.

---

## 5.5 · Stage A5 — Money

**A5.1 — Invoice from signed estimate, no re-entry.** **Done when:** a signed estimate generates an invoice with zero retyping.
**A5.2 — Deposits and payment schedule.** **Done when:** a 30/40/30 schedule generates three scheduled payments.
**A5.3 — Payment status and receivables view.** **Done when:** a paid-in-full job cannot display as partially paid, and open balances list by age.
**A5.4 — Cost lines.** `sub_labor` | `in_house_labor` | `material_actual` | `rework`, attached to the trade work order.
**Done when:** rework cost appears as its own line, separate from original cost.
**A5.5 — Margin per job.** **Done when:** a job displays revenue, cost, margin and rework together, and the pilot tenant's prior invoicing tool can be cancelled without loss of function.

---

## 5.6 · Stage A6 — Client Loop & Proof

**A6.1 — Client comms.** Milestone type, channel, sent/opened, job-scoped. Milestones: signed · material ordered · delivery date set · crew scheduled · day-before · complete.
**Done when:** a scheduled milestone fires without anyone remembering to send it.

**A6.2 — Decision authority.** On the job: `homeowner` | `general_contractor` | `both`.
**Done when:** an approval recorded from a party without authority is refused or flagged.

**A6.3 — Decision records.** Verbal decision → written confirmation to the authority holder → acknowledgment.
**Done when:** no verbal decision reaches production without a written confirmation on record.

**A6.4 — Education documents.** Delivered at sale, re-served during the job.
**Done when:** the underlayment explainer is attached to an estimate and re-served at dry-in.

**A6.5 — Inspections.** Third-party inspector, method, findings, evidence attachments.
**Done when:** an inspection with a thermal-drone finding is recorded with evidence attached.

**A6.6 — Supporting surface.** Transactional email (Resend), remote/email signing link, auto-emailed signed copy, self-serve password reset, dashboard/home view.
**Done when:** an estimate can be emailed for signature and the signed copy returns automatically.

**A6.7 — Defect burn-down.** Present Mode exit/back · outdoor-mode signature coloration · global search · Lead Command Center placement.
**Done when:** all four verified fixed in production.

**A6.8 — PHASE GATE: golden path, twice.**
Run 1: one real job travels lead → estimate → signature → job → master → trades → take-off → PO → delivery → schedule → daily objective → check-ins → QC → invoice → payment → cost retro, with **non-zero rows in every table in §4.5**.
Run 2: a second job runs the same path driven by the crew and office staff, **with the builder not present**.
**Done when:** both runs complete and Run 2 required no builder intervention.

---

# 6 · BACKLOG

Out of the current phase. Adding here is free; moving out of here requires editing §5 first.

**Intake:** blocks the golden path → Phase A (A6.7) · defect that doesn't block → §6.5 · tenant request → §6.4 · unphased idea → §6.6 · a Phase A *Done when* depends on it → this document is wrong, fix §5.

## 6.1 Phase B — selling & capture depth
Present mode: multi-section selling deck · testimonials/past jobs · payment-schedule display · product section (profile/color/warranty) · automated voice/transcript ingestion → draft standard · measurement import into estimating (Hover/RoofScope/EagleView — capability already exists in MM, port it).

## 6.2 Phase C — licensing proof
Pricing matrix (data point → priced line) · customer portal v1 (signed docs, approved photos behind an approval gate, schedule window, delivery ETA, contact, job-scoped ticket channel) · edit-by-ownership at RLS · self-serve config editor · **second contractor tenant onboarded** · Material Matrix marketplace module inside the OS (`/marketplace`, shared catalog, checkout tagged with contractor `org_id`, entitlement-gated).

## 6.3 Phase D — integrations & billing
**Stripe billing (the $20K MRR path — the OS cannot charge for itself until this lands)** · Twilio SMS · Google sign-in/Calendar/Gmail sends · Calendar two-way sync · Docs section · first-timer onboarding tour.

## 6.4 Tenant-filed requests
Absorbed into Phase A: missing-material box → ticket (A4.2) · fluid process checklists (A3.3) · scheduling based on work order (A1) · Spanish integration (A3.4).
Still open: admin-assistant login with capability toggle *(mechanism shipped and deployed; blocked on tenant supplying name + email)* · lock fields after signed work order without a change order *(deferred — change orders are Later)* · pipeline click & drag · update quick actions for work order + estimate · remove "Log Activity" from quick actions.

## 6.5 Open defects
Burn-down in A6.7: Present Mode signature coloration in outdoor mode · Present Mode exit/back · global search · Lead Command Center placement.
Not blocking: contact info editable without an explicit Edit action (fix pushed, needs commit) · Build Tool filter/sort by phase · Build Tool UI · website templates open in a separate tab.

## 6.6 Later / unphased
Formal change orders as void-and-replace beyond the current agreement object · cross-job crew Gantt · trade-WO dependency **engine** · site-visit scheduling calendar · photos at volume on R2 · annotated trim-map editor · offline field capture · CRM table/calendar views · global lead search · per-lead next-action chip · multiple pipeline types · editable document templates · portal v2/v3 · self-serve onboarding at scale · tenant-level automation builder · QuickBooks · native aerial measurement.
**North Star:** AI assistant + semantic search · product catalogs + inventory · native mobile app · StructTech supply shop / distribution.

## 6.7 Material Matrix (own project, `P1–P8` numbering)
In flight: 14-view admin back office · homepage redesign · catalog refresh · frontend cutover to the structtech project.
Deferred: Stripe Connect · Twilio SMS · public order-tracking portal · Calendar delivery sync · inventory · multi-vendor expansion · DWG/CAD roof scopes · full account with saved addresses and reorder.
Blocked: legacy project sunset — until catalog image URLs are re-pointed.
Open defects: pipe boots ask for linear feet not quantity · board-and-batten mis-filed in the roofing catalog · no scroll-to-top after Continue · X exits the whole step · "free" delivery not charging · ridge-cap and trim color not captured.
Decision of record (2026-08-14): **pickup-only**; paid delivery deferred.
Decision of record (2026-08-16): **launches standalone now, becomes a module in Phase C** — see D6.

**Pre-launch gate (must clear before public traffic):**
| # | Item | Why it blocks |
|---|---|---|
| 1 | ~~Drop the two colour-normalisation backups~~ **DONE 2026-08-16** — moved to a private `archive` schema instead of dropped (they hold the only record of 491 changed product-colour mappings). Anon exposure closed, advisors clean. | — |
| 2 | Confirm the front end points at `ejlhrykcdfcyeooooodx`, not the legacy project | Tracker shows this cutover as in progress. Launching on legacy creates a real data migration later |
| 3 | Fix: "free" delivery not charging | Revenue defect — takes orders at the wrong price |
| 4 | Fix: ridge-cap and trim colour not captured on order | Orders land incomplete and need manual confirmation |
| 5 | Fix: pipe boots ask for linear feet instead of quantity | Wrong quantities on real orders |
| 6 | Remove board-and-batten from the roofing catalog | Wrong product category on a live storefront |
| 7 | Stripe: TEST → LIVE keys + webhook secret, then one real end-to-end transaction | Fulfilment must fire only on `payment_intent.succeeded` |
| 8 | Verify `stripe-webhook` (v8) and `create-payment-intent` (v16) against a live charge | Tracker still lists these as planned — §6.8 stale |
| 9 | DNS cutover complete | Blocked on the client's outside web contact since 2026-08-10 |
| 10 | Decide who owns the customer relationship and order data, given the shop runs on a partner-owned domain | Unwinding this after launch is a commercial negotiation, not a config change |

Nice-to-have, not blocking: scroll-to-top after Continue · X-vs-Back navigation clarity · cart editing · admin back-office access for the partner.

## 6.8 Stale — tracked but contradicted by the live system
| Tracker says | System says | Action |
|---|---|---|
| Stripe server-side PaymentIntent — planned | `create-payment-intent` ACTIVE v16 | Verify end-to-end, mark shipped |
| `stripe-webhook` fulfilment — planned | `stripe-webhook` ACTIVE v8 | Verify, mark shipped |
| Orders payment schema not present | Migration `wh_orders_payment` shipped 8/6 | Close as done |
| Product lengths unmapped (0 rows) | Migration `wh_retire_length_tables` shipped 8/5 | Likely obsolete — close, do not build |

## 6.9 Security & hygiene
- ~~`wh_colors_backup_20260814` and `wh_product_colors_backup_20260814` have RLS disabled — 878 rows readable and writable with the anon key.~~ **RESOLVED 2026-08-16.** Verification showed the tables are *not* redundant: row counts match (47 / 831) but **491 of 831 product-colour mappings differ from live**, plus 1 name change and 3 hex changes — they are the only surviving record of the pre-normalisation state. Dropping them would have destroyed it. Both tables were instead moved to a private `archive` schema with no anon/authenticated grants (migration `archive_wh_color_normalization_backups`), which removes API reachability entirely while preserving the data. Advisors re-run clean — no `rls_disabled`, no ERROR-level findings. *Prune only after the normalisation is confirmed correct in production.*
- **Data-quality flag surfaced by that check:** 25 of 47 live colours have no `color_family` value. The base-colour swatch grouping in the storefront reads that column — close before the Checkpoint 6 launch.
- **7 tables have RLS enabled with no policy** (`structtech_state`, `estimate_number_counters`, four `migration_bmr_*` staging tables). This denies all anon/authenticated access by default, which is the correct posture for counters and migration scaffolding — recorded so it is not mistaken for a gap. The `migration_bmr_*` tables can be dropped once the migration is confirmed verified.
- Photo attribution history corrupted by a user-account rename — affects any historical photo audit.
- Hosting doc conflict: CLAUDE.md says Vercel, other docs say Netlify. Make one canonical.
- Make.com lacks error handling/retry/status webhooks (MM P7). **Scenario 4589058 is internal — do not modify.**

---

# 7 · CONSTRAINTS THAT BIND EVERY DECISION

Observed from live field behaviour, not preference.

1. **One page.** A work order or checklist that doesn't fit one screen is not used.
2. **Micro before macro.** Introduce new procedure attached to a defect the crew is already fixing. A full procedure dropped on a crew will not be adopted.
3. **Ask the crew first.** Elicit process content from the crew before prescribing it — even when the answer is identical, authorship drives adoption.
4. **Language by profile**, never a toggle.
5. **Phone-first, outdoors.** Outdoor mode is the default assumption for field surfaces.
6. **Faster than a text message.** If a field action takes longer than sending a text, it loses to the text.
7. **No dollars in the field.** Enforced at RPC and RLS via capability flags.
8. **Radical brevity.** Precision through fewer words, not more.

---

# 8 · RISKS

| Risk | Mitigation |
|---|---|
| Pilot tenant is unreliable and slow-paying; adoption may stall | The builder personally runs the tenant's operations as a third party and can drive the golden path without tenant adoption; StructTech's own org has `delivery` enabled for dogfooding |
| Schema window closes once real jobs flow | A1 and A2 execute first, while production tables are at zero rows |
| A3/A4 are adoption risk, not build risk | Adoption instrumentation is an A4 acceptance criterion (A4.8), not a later addition |
| Single builder, no slack, concurrent commitments | A5 and A6 are the compressible stages; name the tradeoff before it happens |
| Phase A ends without billing | Deliberate. Stripe billing is Phase D; revenue does not start at the phase gate |
| Roadmap drift (§6.8) | The tracker is corrected to match this document, never the reverse |

---

# 9 · EVIDENCE ARCHIVE

Reference only — not directives. Do not build from these; build from §5.

- `BMR-Chronological-Record-Aug2026.md` — nine-day field record, 25 recordings, source of every failure cited here
- `BMR-Data-Map-and-Gate-Framework.md` — the gate framework and data-stream map
- `BMR-Full-Transcript-Pack-Aug2026.md` — full verbatim transcripts

These live in the claude.ai StructTech OS project, not in this repo.

---

# 10 · CHANGE LOG

| Date | Change | By |
|---|---|---|
| 2026-08-16 | Directive v1.0 created. Consolidates and supersedes the Phase A scope, backlog, CLAUDE.md directive block, six-week map, remaining-build map, and build-state documents. | Jacob + Claude |
| 2026-08-16 | Phase A opened with stages A1–A6. Decisions D1–D5 recorded. 44 items written to the Build Tracker under `phase='A'`, tagged A1–A6. | Jacob + Claude |
| 2026-08-16 | **D6 recorded** — Material Matrix launches standalone on the shared backend, migrates to a module in Phase C. Five conditions and a 10-item pre-launch gate added to §6.7. | Jacob + Claude |
| 2026-08-16 | §11 Active Execution Week added — Stage A1 daily directives, Sun 8/16 → Sat 8/22. New-chat entry point added to §0. | Jacob + Claude |
| 2026-08-16 | **A1 Foundation (partial).** Migration `archive_wh_color_normalization_backups` applied: `archive` schema created with no anon/authenticated grants; both colour backups moved out of `public`. Verified first — 491/831 product-colour mappings differ from live, so the tables were archived rather than dropped. Security advisors re-run: `rls_disabled` cleared, zero ERROR-level findings. | Jacob + Claude |
| 2026-08-16 | **§4.7 added — repo/database migration divergence.** 46 local migration files vs 69 remote, zero version matches, 39 remote migrations with no local file, entire `wh_*` series existing only in the database. Also: CLI authenticated to the wrong Supabase org, project never linked, no restore target, direct connection IPv6-only. **New task A1.0 (migration baseline reset) inserted ahead of A1.1.** | Jacob + Claude Code |
| 2026-08-16 | **§4.4 corrected** — coordination RPC surface is 27 functions, not 14. Breakdown: 1 replace · 3 master · 6 trade · 4 hierarchy-aware · 13 inherit-and-verify. | Jacob + Claude |
| 2026-08-16 | **D7 recorded** — controller/coder operating model. No database or schema change is made outside the repo. | Jacob + Claude |

> **Append a row here on every completed task and every decision change. Do not rewrite history.**

---

# 11 · ACTIVE EXECUTION WEEK

**Stage A1 — Job Spine · Sun Aug 16 → Sat Aug 22, 2026**

> If asked "what am I doing today," read this section together with §1. Today's directive is the row matching today's date. If §1 says the previous day's task did not pass its *Done when*, that task carries and the rest of the week shifts by one day — do not skip ahead.

| Date | Task | Directive |
|---|---|---|
| **Sun 8/16** | A1 Foundation + A1.0 | ✅ Anon exposure closed (backups archived, advisors clean). ✅ RPC surface inventoried — corrected 14 → 27, see §4.4. ⬜ This directive committed to `docs/` + pointer in `CLAUDE.md`. ⬜ Verified backup. ⬜ A1.0 migration baseline reset. ⬜ Cut the A1 branch. **A1.1 does not start until A1.0 closes and a backup exists.** |
| **Mon 8/17** | A1.1 Schema | Drop `work_orders_estimate_id_key`. Create `jobs`. Extend `work_orders` — `job_id`, `kind`, `trade`, `assignee_type`, `assignee_ref`, `predecessor_id`. Backfill the 2 existing rows as masters. Set `job_id` NOT NULL. **Done when** a second work order can be inserted against the same estimate. |
| **Tue 8/18** | A1.2 Creation RPCs | Replace `create_work_order_from_estimate` with `create_job_from_estimate` + `create_trade_work_order`. External subcontractor must be a valid assignee. **Done when** one estimate produces a job, a master, and three trades, one external. |
| **Wed 8/19** | A1.3 Child RPCs | Re-point materials, schedule blocks, check-ins, production packets to **trade**. Re-point sign-off and agreements to **master**. Wrong-level calls refused. **Done when** a material item can't attach to a master and a sign-off can't be recorded on a trade. *Heaviest day — nine functions.* |
| **Thu 8/20** | A1.4 Lifecycle | Void, restore, delete, fetch respect the hierarchy. Voiding a master voids its trades. Re-verify the 13 INHERIT functions. **Done when** the tree behaves like a tree and no active agreement is orphaned. |
| **Fri 8/21** | A1.5 Crew visibility | Master hidden from crew roles, trades visible, enforced at RPC **and** RLS via the shipped capability-flags mechanism. Verified with a real crew-role probe. **Done when** a crew role sees its trade and no dollar value anywhere. |
| **Sat 8/22** | A1 Acceptance | Run all A1 *Done when* checks end to end against real data. Update §1 and §10. Mark the A1 tracker items shipped. Read §5.2 and fix any gap in this document before Monday. **Done when** A1 closes on evidence and A2.1 is the stated next step. |

**Week guardrails.** One task per day · backup before any migration · blocked means stop and report, never a temporary shape that needs migrating later · Material Matrix support load is not A1 work — if it costs a day, the week shifts a day, it does not compress A1.3 or A1.5.

**Nothing this week is blocked on another person.**

> **Replace this section at the start of each stage.** When A1 closes, §11 becomes the A2 week.
