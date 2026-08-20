# STRUCTTECH OS — DIRECTIVE
## Single source of truth for the build

**Version:** 1.10 · **Updated:** 2026-08-20
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
- **Push to origin at the end of every working session, at minimum. Unpushed work is unbacked work.**

---

# 1 · CURRENT POSITION

> **Update this block after every completed task. It is the pointer that makes "execute the next step" unambiguous.**

| | |
|---|---|
| **Phase** | A — Production Core |
| **Stage** | A1 — Job Spine |
| **Last completed task** | **A1.5 — Crew visibility — CLOSED (2026-08-20)** — migration `20260820133834_a1_5_crew_visibility_rls_write_hole_and_anon_execute_sweep` applied via MCP. **UI authored first, migration last.** Three pieces. **(1) The A1.4 RLS write hole is CLOSED** — `check_ins`/`material_items`/`schedule_blocks`/`production_packets` INSERT **and** UPDATE now require the referenced work order to be mine **and** `kind='trade'` via a new `work_order_is_my_trade()`; verified first, not assumed, that no app write is affected (a grep for `.insert(`/`.update(`/`.delete(` over `src/` returns **zero** matches — every write goes through a SECURITY DEFINER RPC, which RLS does not apply to). **(2) The §6.9 `anon` sweep is DONE and paired** — `revoke execute … from public, anon` over every postgres-owned security-definer function in `public` (signatures taken from `oid::regprocedure`, never retyped), plus `alter default privileges for role postgres … revoke execute on functions from public, anon` so new functions cannot re-acquire it. Advisor `anon_security_definer_function_executable` went **109 → 2**. **The 2 are deliberate exclusions, reported not hidden:** `create_wh_order` and `get_wh_order` are the Material Matrix storefront's anon-callable order RPCs — `create_wh_order`'s body opens `IF auth.uid() IS NULL THEN v_org := v_supplier`, so **§6.9's claim that all 109 are refused by `my_org_ids()` was false**, and revoking them would break live order placement on a customer-facing site this repo cannot test. **(3) Crew visibility at BOTH layers** — two new capability functions shaped exactly like `has_capability()` but with a role-derived, closed default (`can_view_master_work_order`, `can_view_financials`); RESTRICTIVE policies (permissive ones OR together and `deals` already carries a second one, so a permissive edit would have gated nothing) on `work_orders`, `work_order_agreements`, `work_order_activity`, `estimates`, `estimate_line_items`, `deals`; and the same gate written into `fetch_work_order`, `fetch_work_order_tree` and `fetch_estimate` because SECURITY DEFINER bypasses RLS. `fetch_estimate` returns the four money columns as NULL to a caller without financials; new `fetch_field_jobs()` feeds the crew Today list with a select list that contains no money column at all. **Probed with a REAL `role='field'` member** — a genuine `auth.users` row plus an `org_members` row, built and rolled back inside the transaction. Measured before: crew read the master, 4 estimates (max `presented_total` 34000.00), 21 line items, 191 deals. After: master **0 via RPC and 0 via direct table select**, estimates 0, line items 0, deals 0, `fetch_estimate` money NULL, agreements/activity 0 — while the crew still reads its own trade (RPC 1, direct 1), its own check-in and schedule block, and its job header. Owner unchanged throughout (master 1, trade 1, 3 work orders, presented_total 34000.00, 191 deals). All 6 write-hole attacks blocked, both positive controls still pass. Zero residue. Advisors **0 ERROR**. `tsc --noEmit` and `next lint` clean. |
| **Previously completed** | **A1.4 — Hierarchy lifecycle — CLOSED (2026-08-19)** — migration `20260819233735`. Cascade marker columns on `work_orders` and `work_order_agreements`; void cascades master→live trades and voids the active agreement; restore reverses **only** the cascade (Monday/Tuesday case proved); delete of a master with children refused, naming the count; `fetch_work_order` left alone per rule 5b with `fetch_work_order_tree` added for the tree. **The 13 INHERIT functions came back 13/13 BROKEN, not "verify only"** — all fixed, plus the two material-item functions from A1.3b, 15 in total. 15/15 positive and 15/15 negative, zero residue, advisors 0 ERROR. Full detail in the §10 rows dated 2026-08-19. |
| **Before that** | **A1.3b — child RPC re-pointing — CLOSED (2026-08-18)**, migration `20260819002237`; and **A1.3a — trade surface, UI only — CLOSED (2026-08-18)**. Both shipped the same day; see §11 Tue 8/18 and the §10 rows dated 2026-08-19. |
| **Earlier in A1** | **A1.1 — Job spine schema — CLOSED (2026-08-16)** — two migrations, both applied via MCP. `20260816172215_a1_1_job_spine_work_order_hierarchy`: dropped `work_orders_estimate_id_key` (§4.4); created `jobs` with org-scoped RLS; extended `work_orders` with `job_id`, `kind`, `trade`, `assignee_type`, `assignee_ref`, `predecessor_id`; backfilled both existing work orders as `kind='master'`; `job_id` NOT NULL; one-master-per-job. `20260816173237_a1_1_fix_create_work_order_rpc_and_job_uniqueness`: repaired `create_work_order_from_estimate` (it now creates the job then the master, same name/signature/call sites) and added `UNIQUE (jobs.estimate_id)` per D1. All four *Done when* clauses verified, including no broken production write path. Advisors clean of ERROR-level findings. |
| **Outstanding from Foundation** | **CLOSED 2026-08-16.** (1) ✅ Directive landed at `docs/STRUCTTECH_OS_DIRECTIVE.md` + pointer in `CLAUDE.md` (commit `d985499`). (2) ➖ CLI still authenticated to the wrong Supabase org and the project is not linked — moot for now; all migrations go through MCP. Folded into the deferred A1.0. (3) ✅ Targeted pre-A1.1 backup taken (`backups/`, 5 tables, row-count verified). (4) ➖ **A1.0 migration baseline — DEFERRED**, see §4.7; hygiene, not a blocker. **Every migration goes through MCP `apply_migration` with a matching repo file. Never `supabase db push` or `db reset` — see §4.7.** |
| **NEXT STEP** | **A1 ACCEPTANCE** (§11, Fri 8/21). Every A1.1–A1.5 *Done when* re-run end to end against real data, §1/§10 updated, the A1 tracker items marked shipped, §5.2 read and any gap in this document fixed before Monday. **What it will need:** the golden-path chain exercised in one pass (signed estimate → job + master → trades → materials → schedule → check-in → packet → sign-off → agreement), the carried-debt list below read as a checklist rather than a footnote, and a decision on whether the outstanding browser confirmation on `os.structtek.com` — now covering A1.3a, A1.3b, A1.4 **and** A1.5's UI — blocks acceptance or is recorded as a known gap. **A1.0 (migration baseline reset) is the first task after acceptance.** |
| **Carried debt from A1.5** | **Four items. Tomorrow's acceptance should read this as a checklist.** (1) **`anon` still holds EXECUTE on `create_wh_order` and `get_wh_order`** — deliberate, not an oversight: both are anon-callable by design for the Material Matrix storefront, and `create_wh_order` has an explicit `IF auth.uid() IS NULL` branch. Removing them needs the MM owner's confirmation and a token-scoped replacement. **This also falsifies §6.9's old claim that all 109 were refused by `my_org_ids()`** — corrected in place. (2) **`has_capability()` still fails open** — a member with no `permissions` row still gets `view_financials`, `view_estimates`, `view_field`, `add_notes` and `schedule` from its global fallback array. A1.5 deliberately did not touch it (decision, §10) and routed around it with two new closed-default functions instead, which means **two functions now answer "can I see money" and they disagree for a crew-tier member with no permissions row.** That is the intended state today and unacceptable as a permanent one. **Scheduled for A2** with its own *Done when*. (3) **`leads`, `org_invoices`, `proposals` and `audits` carry money-shaped columns and were NOT gated** — the crew probe returned 0 rows from `leads` so nothing is exposed today, but that is a property of the current data, not of a policy. (4) **No crew-role user exists in production.** Every crew guarantee in A1.5 is proved against a synthetic-but-genuine `role='field'` member built inside a rolled-back transaction. It is a real membership row and a real `auth.users` row, but the first *real* crew login will still be the first time this runs outside a probe. |
| **Carried debt from A1.4** | **CLEARED 2026-08-20.** (1) The RLS INSERT hole is closed on INSERT **and** UPDATE across all four child tables, cross-org and wrong-level both — six attack cases blocked, two positive controls still passing. (2) The `work_order_activity` string-parsing item carries forward below. |
| **Carried debt from A1.3b** | **One item still open.** `work_order_activity` names the trade inside a string rather than in a column; deliberate (the stale document is the master's), and it wants a `subject_work_order_id` column only if "which trade changed?" becomes a real query. The other two A1.3b items were cleared by A1.4. |
| **Carried debt from A1.3a** | **CLEARED as a distinct item — folded into item (1) above.** |
| **Carried debt from A1.2** | **CLEARED 2026-08-19.** The `create_work_order_from_estimate` shim was dropped as the first statement of the A1.3b migration, exactly as planned; `pg_proc` confirms 0 remaining. Nothing else carried from A1.2. |
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

> **D7 AMENDED 2026-08-19 (scope change, see §10).** D7 binds every migration against the `structtech` project, not only the OS app. Material Matrix work runs on the shared backend (D6) and is therefore in scope: every schema change originates in a repo migration file, whichever app or session applies it. A change applied without a repo file is a defect to be reported, not a shortcut to be absorbed.

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
| **INHERIT — ~~verify only~~ WAS BROKEN, FIXED IN A1.4** | 13 | `add_check_in_photo` · `remove_check_in_photo` · `update_check_in` · `delete_check_in` · `fetch_check_in` · `update_schedule_block` · `delete_schedule_block` · `fetch_production_packet` · `delete_production_packet` · `update_production_packet_notes` · `add_production_packet_callout` · `update_production_packet_callout` · `delete_production_packet_callout`. **The "inherit their level from their parent" description was wrong, and "verify only" was the wrong instruction.** A1.4 produced a verdict per function: **13 of 13 BROKEN.** None read the parent's `kind`; every one read `org_id` off its own row only; and the guarantor that made them look safe (`create_check_in` / `add_schedule_block` / `get_or_create_production_packet` refusing a master) is bypassable through the tables' own RLS INSERT policies. All 13 now **ENFORCE** their level through the parent via `assert_work_order_level`, and their org path moved from the child's own row to the parent. No signature changed. |

A1.3b covered the first two rows plus BOTH-hierarchy prep (14 functions). **The INHERIT row was scoped as a verification pass; it was a rewrite.** A1.4 fixed all 13 plus `update_material_item`/`delete_material_item` — 15 functions.

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

> **RE-MEASURED 2026-08-19 — the figures above are the 2026-08-16 reading and are now stale. The gap is wider, and it is still growing.**
> **81 remote entries vs 47 local files. 78 remote entries have no version match. 49 have neither a version nor a name match — that is 49 remote migrations with no repo file at all, against the 39 recorded on 2026-08-16. Twenty-three of the 49 are `wh_*`.**
> **RE-MEASURED AGAIN 2026-08-20 — the rate is the finding, not the total.** **Fourteen** non-A1 migrations landed on `structtech` on 2026-08-20 alone, none with a repo file: `tg_agenda_bot_schema`, `tg_agenda_bot_assets_bucket`, `tmp_enable_http_for_verification`, `tg_agenda_cleanup_unused_assets`, `tg_agenda_per_user_sessions_and_group_optin`, `tmp_enable_http_verify_v3`, `tmp_drop_http_after_verify`, `tmp_http_for_bot_diagnosis`, `bmr_field_ticket_schema`, `bmr_tickets_schema_standalone`, `cp3_thursday_backup_categories_20260820`, `wh_categories_image_url_backfill`, `cp3_thursday_backup_systems_20260820`, `wh_systems_hero_image_rehost`. **Four of them landed AFTER A1.5** (the last four in that list). Three more landed on 2026-08-19 (`wh_catalog_editor_dual_write_rpc`, `cp3_wednesday_step0_backups_20260819`) and are counted there. **The 2026-08-16 rate was ~5/day; 2026-08-20's was 14/day.** Four of the fourteen are named `tmp_` and one of those left the `http` extension installed on production (§6.9) — so the divergence is no longer only a bookkeeping problem, it is now the delivery mechanism for an un-reviewed security change. A1.0 does not get to slip again.
>
> **It grew by 5 in a single day:** `cp3_tuesday_step0_backups_20260818`, `wh_price_history`, `wh_product_types`, `wh_product_roles` and `wh_variation_colors` all landed on 2026-08-18 with no repo file — after D7 was recorded on 2026-08-16. That is what the D7 amendment in §3 exists to stop, and it is why A1.0 is now scheduled (§5.1) rather than deferred: a baseline reset against a divergence that is still growing would be obsolete the week it was done.
- The entire `wh_*` series — roughly 20 migrations from `wh_supplier_catalog_landing_zone` (2026-08-01) through `wh_order_number_sequence_authoritative` (2026-08-15) — exists **only in the database**. The Material Matrix catalog work was applied outside the repo.
- `archive_wh_color_normalization_backups` (2026-08-16) is the tail of that pattern, not an isolated event.

**Why this blocks A1:** A1 is a schema change delivered as a repo migration. If the repo cannot represent current schema state, Claude Code cannot safely reason about what exists before altering `work_orders`. Reconciliation is a prerequisite, not cleanup.

**Second finding — wrong Supabase account.** The local CLI is authenticated to org `fxtcnutwrdhzmofpmaww` (projects `bmr-lead-pipeline`, `structtech-x-windyhill`) — almost certainly the legacy org. Production `structtech` (`ejlhrykcdfcyeooooodx`) lives in org `atutgdfktddukxabhrrj` and is not visible to the CLI. There is no `supabase/config.toml`, so the project was never linked, and `.env.local` carries only the public URL and anon key — no service-role key, no connection string. Use `--profile` when authenticating so the legacy credential in the macOS Keychain is preserved.

**Third finding — no restore target.** No local Postgres, no Docker. "Verify it restores" has nowhere to restore to until one exists. Object-count verification is the accepted fallback and must be reported as weaker than a real restore test.

**Fourth finding — direct connection unusable.** `db.ejlhrykcdfcyeooooodx.supabase.co` is IPv6-only and the build machine has no IPv6 egress. Use the **Session pooler** connection string (IPv4, port 5432). Not Direct, not Transaction pooler (6543 cannot serve `pg_dump`).

**MITIGATION, NOT BLOCKER (2026-08-16). The divergence does not prevent new migrations. Applying a migration via MCP `apply_migration` works correctly and records properly in remote history. The divergence is only dangerous if someone runs `supabase db push` or `supabase db reset`, which would attempt to replay 46 stale local files against production. HARD RULE: never run `supabase db push` or `supabase db reset` on this project until the baseline reset is complete. New migrations go through MCP `apply_migration`, with a matching file written to `supabase/migrations/` so the repo stays current going forward.**

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

**A1.0 — Migration baseline reset (SCHEDULED 2026-08-19 — the FIRST task after A1 acceptance. No longer "deferred, do when convenient".)**
**Why it moved:** the divergence is not static. It grew by 5 in one day (§4.7, re-measured 2026-08-19: 49 remote migrations with no repo file, up from 39). Resetting a baseline while changes are still landing outside the repo produces a baseline that is obsolete the week it is taken. **The decision of 2026-08-19 was therefore two-step: stop the growth NOW via the D7 amendment (§3), then reset the baseline once it has stopped.** A1.0 runs first after A1 closes; it does not slip further.
Reconcile the repo with the database so the repo becomes the source of truth for schema going forward. **Decided approach: baseline reset, not backfill — do not reconstruct the 39 missing migration files.** Authenticate the CLI to the correct org using `--profile`, link the project, take a verified backup first, pull the current remote schema as a single new baseline migration, move the 46 stale local files to `supabase/migrations/_archive_pre_baseline/` (move, do not delete), and use `supabase migration repair` to mark prior remote migrations as applied. Every migration from A1.1 onward originates in the repo.
**Done when:** `supabase migration list` shows local and remote in agreement, the baseline migration is committed, and a trivial reversible schema change made in the repo applies cleanly to the database and reverts.

**A1.1 — Schema: jobs + work order hierarchy**
Drop `work_orders_estimate_id_key`. Create `jobs` (`id`, `org_id`, `deal_id`, `estimate_id`, service address, timestamps). Extend `work_orders` with `job_id` (nullable → NOT NULL), `kind` (`master`|`trade`), `trade`, `assignee_type` (`crew`|`department`|`subcontractor`), `assignee_ref`, `predecessor_id` (self-FK, nullable). Backfill the 2 existing rows as masters with jobs derived from their estimates. Add: one master per job.
**Done when:** both existing work orders resolve to a job with `kind='master'`, `job_id` is NOT NULL, and a second work order can be inserted against the same estimate, and no existing production write path is left broken.

**A1.2 — RPC split: creation**
Replace `create_work_order_from_estimate` with `create_job_from_estimate` (creates job + master) and `create_trade_work_order` (creates a trade under a master).
**Done when:** one signed estimate produces a job, a master, and three trade work orders, one of them assigned to an external subcontractor.

**A1.3a — Trade surface on the master (UI ONLY — no migration, no database change)**
The master work order page lists the trade work orders on its job (trade, assignee type, assignee ref, predecessor), each row linking to its own work order page, and offers a create-trade form calling `create_trade_work_order`. A trade page does not offer "create trade" — trades do not nest. **`trade` is a free-text input, never a fixed dropdown** (decision §10, 2026-08-17; UI consequence §10, 2026-08-18): the engine is config-driven and tenants do not share a trade list, so a hardcoded `<select>` would undo that decision in the UI layer. A `datalist` of suggestions is permitted; a closed list is not. The RPC's own errors — trade under a trade, half-specified assignee, duplicate active trade, predecessor from another job — are surfaced to the user verbatim; client-side checks are convenience only and never the gate.
**Why this comes first:** A1.3b re-points nine child functions onto trades. Until a trade can be created through the UI, that re-point cannot be exercised by a human at all, only by hand-written SQL — and the *Done when* below is a UI claim, not a SQL claim.
**Done when:** a trade created through the UI appears in the master's trade list and opens its own work order page; the zero-trade empty state renders on both production masters; a refused case shows the RPC's message.

**A1.3b — RPC re-pointing: children**
**First statement of the migration: `drop function public.create_work_order_from_estimate(p_estimate_id uuid)`** — the A1.2 shim, whose re-pointed callers went live with A1.3a.
Re-point `add_material_item`, `update_material_item`, `delete_material_item`, `add_schedule_block`, `create_check_in`, `get_or_create_production_packet` to **trade** work orders. Re-point `record_work_order_sign_off`, `create_work_order_agreement`, `fetch_work_order_agreement` to **master**.
**Done when:** a material item cannot be attached to a master, a sign-off cannot be recorded on a trade, and the master page no longer offers child-object forms it will refuse.
**Why the third clause:** A1.3a exists so refusals have somewhere to go. Leaving the master page rendering material and schedule forms that now always fail re-creates the problem the split was meant to avoid. Hiding a form that does not apply at this level is **not** SCOPE §2.8 blocking — §2.8 forbids disabling a control because *other data* is incomplete, not rendering a control only where its object can exist.

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
- **🔴 OPEN — the `http` extension is live on production, and `anon` + `authenticated` hold EXECUTE on all 14 of its functions.** Installed by migration `tmp_http_for_bot_diagnosis` (`20260820020138`) with no drop after it; found by the controller on 2026-08-20 while verifying A1.5. Version 1.6, schema `extensions`. **A1.5's `alter default privileges` sweep covers schema `public` only and does not touch this.** Every overload — `http`, `http_get` ×2, `http_post` ×2, `http_put`, `http_patch`, `http_delete` ×2, `http_head`, `http_header`, `http_list_curlopt`, `http_reset_curlopt`, `http_set_curlopt` — reads `anon=true, authenticated=true`, inherited from a PUBLIC grant (`=X/supabase_admin`), not from an explicit per-role grant.
  - **Decision (Jacob, 2026-08-20): revoke the grants, KEEP the extension.** The tg_agenda bot is not in this repo and may call `http_*` at runtime, so dropping it is not on the table without that owner's confirmation.
  - **The revoke IS NOT DONE, and it is not a matter of writing the migration.** `revoke execute on function extensions.http_get(...) from public, anon, authenticated` **is a silent no-op from this connection.** Proven in a rolled-back test: the functions are owned by `supabase_admin`, the PUBLIC grant was made by `supabase_admin`, and only a grantor can revoke its own grant. `postgres` is **not** a superuser (`rolsuper=false`), **cannot** `set role supabase_admin` (*permission denied to set role*), and **cannot** take ownership (*must be owner of function http_get*). Postgres emits a warning, not an error — so a migration doing this would report success and change nothing. That is the same class of failure as migration-discipline rule 2.
  - **What DOES work from `postgres`:** `revoke usage on schema extensions from anon, authenticated`. `postgres` owns the `extensions` schema (`nspacl` shows `anon=U/postgres, authenticated=U/postgres`), and the revoke took effect in the same rolled-back test. **Blast radius measured, not assumed:** `extensions` also holds `pgcrypto`, `uuid-ossp` and `pg_stat_statements`, but in `public` there are **0** column defaults, **0** constraints and **0** invoker-rights functions referencing `extensions.*`, and every SECURITY DEFINER function runs as its owner and is unaffected. `service_role` and `postgres` USAGE would be untouched, so an edge function or definer-owned caller keeps working. **Not applied — it is a different mechanism from the one decided, on a shared backend serving two apps this repo cannot test, and it is Jacob's call.**
  - **🔴 UNVERIFIED, and it decides how serious this is: whether `extensions` is in the project's exposed schemas.** It cannot be read from SQL — `pg_db_role_setting` for the `authenticator` role carries only `session_preload_libraries`/`statement_timeout`/`lock_timeout`, no `pgrst.db_schemas`, so the list lives in the Supabase API config. **It must be checked in the dashboard: Settings → API → Exposed schemas.** If `extensions` IS exposed, `http_get` was callable over `/rest/v1/rpc/` with the anon key — a server-side request-forgery surface on production — and this finding is considerably more serious than recorded here. **Do not assume the default.**
  - Note for the record: the same session dropped `http` once already — `tmp_drop_http_after_verify` (`20260820013529`) — and then re-installed it 46 minutes later with `tmp_http_for_bot_diagnosis` and did not drop it again. The pattern self-corrected once and then did not.
- ~~`wh_colors_backup_20260814` and `wh_product_colors_backup_20260814` have RLS disabled — 878 rows readable and writable with the anon key.~~ **RESOLVED 2026-08-16.** Verification showed the tables are *not* redundant: row counts match (47 / 831) but **491 of 831 product-colour mappings differ from live**, plus 1 name change and 3 hex changes — they are the only surviving record of the pre-normalisation state. Dropping them would have destroyed it. Both tables were instead moved to a private `archive` schema with no anon/authenticated grants (migration `archive_wh_color_normalization_backups`), which removes API reachability entirely while preserving the data. Advisors re-run clean — no `rls_disabled`, no ERROR-level findings. *Prune only after the normalisation is confirmed correct in production.*
- **Data-quality flag surfaced by that check:** 25 of 47 live colours have no `color_family` value. The base-colour swatch grouping in the storefront reads that column — close before the Checkpoint 6 launch.
- **7 tables have RLS enabled with no policy** (`structtech_state`, `estimate_number_counters`, four `migration_bmr_*` staging tables). This denies all anon/authenticated access by default, which is the correct posture for counters and migration scaffolding — recorded so it is not mistaken for a gap. The `migration_bmr_*` tables can be dropped once the migration is confirmed verified.
- **RLS INSERT policies let a child row be created on the wrong level (found 2026-08-19, A1.4).** `member insert own check_ins`, `…material_items`, `…schedule_blocks` and `…production_packets` each test only `org_id in (select my_org_ids())`. Nothing stops an authenticated user inserting a check-in, material item, schedule block or production packet **directly onto a master work order**, bypassing the trade-asserting creation RPC. Probe-confirmed the same day: `create_check_in(<master>)` refused and a plain `insert` of the same row succeeded in the same session. **Severity is low today** — the child tables are at zero rows, the app never inserts directly, and A1.4 made all 15 child RPCs refuse a wrongly-levelled row so such a row is inert. But it is the reason 13 functions that looked like they "inherit their level" were in fact BROKEN. **Fix belongs in A1.5**, where RLS enforcement is the subject: the `with check` needs to test the parent work order's `kind`, or the insert policies need removing so the RPC really is the only path. **Also note this contradicts CLAUDE.md's Supabase rule 3** as written — that rule describes the app's pattern, not a property of these tables.
- ~~**`anon` holds EXECUTE on 109 security-definer RPCs in `public`**~~ **RESOLVED 2026-08-20 in A1.5, and the original entry was wrong on the substance.** The sweep ran — `revoke execute … from public, anon` over every postgres-owned security-definer function in `public`, paired with `alter default privileges for role postgres … revoke execute on functions from public, anon` so new functions cannot re-acquire it. Advisor count **109 → 2**. **But the old entry's reassurance was false:** it said "every one of the 109 is refused on its first statement by `my_org_ids()`". `create_wh_order` opens `v_uid := auth.uid(); IF v_uid IS NULL THEN v_org := v_supplier;` — an explicit anonymous branch. It is the Material Matrix storefront's order-placement RPC and is anon-callable **by design**, as is `get_wh_order`. Those two are the remaining 2 and are **deliberately excluded**: revoking them would break live order placement on a customer-facing site this repo cannot test. Closing them properly needs the Material Matrix owner's confirmation and a token-scoped replacement. Several others (`crm_stage_config`, `tracker_status_config`, `tracker_type_config`, `generate_roadmap_for_lead`, `create_engagement_from_roadmap`) also had no `my_org_ids()` gate and were simply revoked.
- **`has_capability()` FAILS OPEN — a member with no `permissions` row has `view_financials` (found 2026-08-20, A1.5).** Its fallback is `p_capability = any(array['view_financials','view_estimates','view_field','add_notes','schedule'])`, so the absence of a permission grants it. That is the inverse of constraint 7. **A1.5 deliberately did not flip it** — changing a global default in a shipped, deployed mechanism one day before A1 acceptance is rule 5b's shape even though no migration breaks (decision, §10, 2026-08-20). Instead A1.5 added `can_view_master_work_order()` and `can_view_financials()`: the same three-tier shape, the same `org_members.permissions` keys, but a role-derived default that is CLOSED for `field` and `client_portal_viewer`. **Consequence, recorded as debt rather than glossed:** two functions now answer "can I see money" and they disagree for a crew-tier member with no permissions row. **Reconciling them is A2 work and needs its own *Done when*.**
- **Money-shaped columns NOT covered by A1.5's crew gates:** `leads.value`, `org_invoices.amount`, `proposals.price`, `audits.total_pain_score`. The crew probe returned 0 rows from `leads`, so nothing is exposed today — but that is a property of the current data, not of a policy. `wh_*` catalog prices are supplier-shop prices, not job money, and are out of constraint 7's scope by intent; say so explicitly rather than leave it ambiguous.
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

> **Rows in this log are historical, not instructions.** A row records what was true and decided on its date. Where a later row supersedes an earlier one, the earlier text stays as written — the live position is always §1, §5 and §11, never a change-log row. If a §10 row and §1 disagree, §1 wins and the row is history.

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
| 2026-08-16 | **A1.0 DEFERRED.** Reclassified from prerequisite to hygiene: the divergence does not prevent new migrations, since MCP `apply_migration` records correctly in remote history. Mitigation and the hard rule against `supabase db push` / `db reset` recorded in §4.7. | Jacob + Claude Code |
| 2026-08-16 | **A1.1 COMPLETE.** Migration `20260816172215_a1_1_job_spine_work_order_hierarchy` applied via MCP. Dropped `work_orders_estimate_id_key`; created `jobs` (org/deal/estimate + structured service address, org-scoped RLS mirroring `work_orders`); extended `work_orders` with `job_id`, `kind`, `trade`, `assignee_type`, `assignee_ref`, `predecessor_id`; backfilled 2 rows as masters against derived jobs; `job_id` NOT NULL; partial unique index `work_orders_one_master_per_job`. Verified: both work orders resolve to a job with `kind='master'`, zero null `job_id`, a second work order inserts against the same estimate (rolled back), and a second master per job is refused. Advisors: 0 ERROR. Pre-migration backup of 5 tables taken and row-count verified. **Known debt:** `create_work_order_from_estimate` now fails until A1.2 (rule 5b). | Jacob + Claude Code |

| 2026-08-16 | **A1.1 defect fixes — stage closed.** Migration `20260816173237_a1_1_fix_create_work_order_rpc_and_job_uniqueness` applied via MCP. (1) Repaired the `create_work_order_from_estimate` regression introduced by `20260816172215`: it now resolves the estimate, find-or-creates the job (org/deal/estimate + structured service address from the estimate's deal), then inserts the work order with `job_id` and `kind='master'`. Name, signature `(p_estimate_id uuid) returns uuid`, and call sites unchanged — the split into `create_job_from_estimate` + `create_trade_work_order` remains A1.2. Overload count re-verified at 1 (CLAUDE.md rules 1 and 3). Idempotency retained and scoped to the master. (2) Added `UNIQUE (jobs.estimate_id)` per D1 — one job per signed estimate — closing the double-click gap flagged when A1.1 first shipped. Verified end to end against a real signed estimate with no job: one call produced a job + master work order with the full structured address, a second call returned the same work order id, counts moved 2→3 once and not twice, and the whole test rolled back with zero residue. The three original *Done when* checks re-confirmed after the change. | Jacob + Claude Code |
| 2026-08-16 | **§5.1 A1.1 *Done when* extended** — now also requires "and no existing production write path is left broken." Recorded because A1.1 initially shipped a passing *Done when* alongside a broken deployed RPC; the criterion did not catch it. | Jacob + Claude Code |
| 2026-08-16 | Branch policy decided — work proceeds on main, one commit per task. Per-stage branches add a merge step without benefit for a single builder. The wip/work-order-agreements-signoff preservation branch stays as-is. | Jacob + Claude Code |
| 2026-08-16 | **Sunday 8/16 foundation CLOSED.** Directive landed and pointer added to `CLAUDE.md`; anon exposure closed; coordination RPC surface corrected 14 → 27; migration divergence discovered and recorded (§4.7); A1.0 deferred with the MCP mitigation and the hard rule against `db push` / `db reset`; targeted backup taken and row-count verified; A1.1 shipped and closed across two migrations. Branch policy set. Push to origin was initially denied by the Claude Code permission classifier; a Bash permission rule for `git push`/`fetch`/`ls-remote` was added to `.claude/settings.json` and the push completed. §0 now requires a push at the end of every session. | Jacob + Claude Code |

| 2026-08-16 | **Both branches on origin — §0's push rule is now satisfied, not aspirational.** `main` at `9259d8029d50f691ce445e5fec82bad2d6a669ad` (fast-forward from `8c7cea6`, 5 commits: directive landed → A1.0 deferred → A1.1 job spine → A1.1 fixes → branch policy). `wip/work-order-agreements-signoff` at `3e22046b8be401edadc0bb5e160e316f32529793`, pushed as a new remote branch with upstream tracking. `git ls-remote` confirms remote and local hashes identical on both; 0 commits ahead on either. Remote: `github.com/jacobaw1995/structtech-os`. | Jacob + Claude Code |

| 2026-08-17 | **A1.2 COMPLETE — creation RPC split.** Migration `20260817151709_a1_2_creation_rpc_split_job_and_trade` applied via MCP. **Function DDL only — no table created, altered or dropped, no row inserted, updated or deleted.** (1) `create_job_from_estimate(p_estimate_id uuid) returns jsonb` — resolves the estimate, refuses anything not `status='signed'` (via `coalesce`, rule 5), find-or-creates the job with the structured service address off the deal, find-or-creates the master. **Returns jsonb `{job_id, master_work_order_id}` rather than a uuid because it creates two rows and both ids are load-bearing** — the caller redirects to the master while A2/A5 hang materials, purchasing and money off the job; a uuid return would force every caller into a second round trip. (2) `create_trade_work_order(p_master_work_order_id, p_trade, p_assignee_type, p_assignee_ref, p_predecessor_id) returns uuid` — **inherits `org_id`, `estimate_id` and `job_id` from the master rather than taking them as parameters, so a trade cannot land in the wrong org or on the wrong job: the caller has no way to name either.** Authorization checked once against the master via `my_org_ids()`; predecessor confirmed to be a trade on the same job; external subcontractor a first-class assignee per D1; double-submit guard keyed on trade + assignee, so two crews may split a trade but an identical row is refused. (3) `create_work_order_from_estimate` **kept as a DEPRECATED SHIM per rule 5b** — same name, same `(p_estimate_id uuid) returns uuid`, body delegates to `create_job_from_estimate` and unwraps `master_work_order_id`. Dropping it in A1.2 would have broken production work-order creation for as long as the UI took to ship, which is the exact failure A1.1 recorded once already. Overload count verified at exactly 1 for all three against `pg_proc` after applying (rules 1–3). | Jacob + Claude Code |
| 2026-08-17 | **Three A1.2 decisions recorded.** (1) *"Valid assignee" needs no new table.* An external subcontractor is `assignee_type='subcontractor'` paired with a non-empty `assignee_ref`, enforced in the RPC; §5 defines no subcontractors table and the person/crew model is A4.6, so nothing outside §5 was created. The pairing rule — assignee optional, never half-specified — is what makes "assigned to an external subcontractor" a checkable state and what makes the A4.6 upgrade to a resolvable reference safe. (2) *`trade` is required but not constrained to a vocabulary.* The engine is config-driven and tenants do not share a trade list; §4.5's four trades are the pilot's, not the engine's, and CLAUDE.md rule 4 makes changing a CHECK value set expensive. (3) *`create_work_order_from_estimate` is kept as a deprecated shim, dropped in A1.3*, per CLAUDE.md rule 5b — the migration reaches prod instantly and the Vercel UI deploy lags it. | Jacob + Claude Code |
| 2026-08-17 | **Repo caught up to the deployed A1.2 migration — same commit.** `supabase/migrations/20260817151709_a1_2_creation_rpc_split_job_and_trade.sql` written from `pg_get_functiondef()` on the live database, not from memory, with the header recording the DDL-only scope and the three design decisions above. Call sites re-pointed: `createWorkOrderFromEstimate` → `createJobFromEstimate`, now calling `create_job_from_estimate` and reading `master_work_order_id` off the jsonb — **and redirecting back to the estimate with an explicit error when that key is missing, instead of building `/coordination/undefined`**, which would have read as "the work order is missing" rather than "the call came back wrong". Importers updated in `coordination/page.tsx` and `EstimateSignatureBlock.tsx`; both new functions added to `database.types.ts` with `create_job_from_estimate` returning `Json`. `npx tsc --noEmit` and `next lint` both clean. **Note: the migration is recorded remotely as version `20260817151709`, not `20260817151454`** — the repo filename follows the database, since a mismatched version is precisely the §4.7 divergence this file exists to stop reproducing. | Jacob + Claude Code |
| 2026-08-17 | **§6.9 — `anon` holds EXECUTE on all 110 security-definer RPCs.** Found while confirming the A1.2 functions' ACLs. It is the project-wide default function ACL applied automatically on create, never granted deliberately. **Advisors report 0 ERROR and every one of the 110 is refused on its first statement by `my_org_ids()`, which returns nothing for an unauthenticated caller — an unnecessary surface, not an open door.** Not fixable per-migration, since new functions re-acquire it from the same default; **filed as one `revoke` sweep in A1.5**, where the RPC grant surface is already the subject. | Jacob + Claude Code |
| 2026-08-17 | **§11 re-dated one day earlier.** A1.1 shipped Sunday 8/16 rather than Monday, so the week moves up: A1.2 Mon 8/17 (done) · A1.3 Tue 8/18 · A1.4 Wed 8/19 · A1.5 Thu 8/20 · A1 acceptance Fri 8/21 · Sat 8/22 becomes unallocated buffer. The buffer is slack against a slipped day, not room for new scope. | Jacob + Claude Code |

| 2026-08-18 | **A1.3 SPLIT into A1.3a and A1.3b.** A1.3 as written was a nine-function re-point whose *Done when* ("a material item cannot be attached to a master, and a sign-off cannot be recorded on a trade") could not be exercised by a human, because **nothing in the UI could create a trade** — A1.2 shipped `create_trade_work_order` with no caller. Verifying A1.3 would have meant hand-written SQL, which is not the same claim. **A1.3a (UI only, no migration, no database change)** puts the trade surface on the master; **A1.3b** is the original re-point, and its migration opens by dropping the A1.2 shim — now safe, because A1.3a ships the last caller. §5.1, §4.4 and §11 updated to match. | Jacob + Claude Code |
| 2026-08-18 | **UI consequence of the 2026-08-17 `trade` decision — free text, never a fixed dropdown.** The decision itself is A1.2's, recorded in the 2026-08-17 row above: `trade` is required but not constrained to a vocabulary, because the engine is config-driven and §4.5's four trades are the pilot's, not the engine's. A1.3a is the layer where that could have been quietly undone — a hardcoded `<select>` in the create-trade form re-imposes a shared vocabulary with the database none the wiser, and `tsc` would not have noticed. **Suggestions are permitted, constraint is not:** the form renders a `datalist` built from the trade names *this org has already used*, so it is empty on a tenant's first job, grows into the tenant's own vocabulary, and never limits what can be typed. Note the deliberate contrast with `assignee_type`, which **is** a closed three-value `<select>` — there the constraint is real (`work_orders_assignee_type_check`), so anything else is a constraint violation rather than tenant configuration. | Jacob + Claude Code |
| 2026-08-18 | **A1.3a COMPLETE — trade surface on the master. UI only: no migration written, no schema object touched, no production row created or modified.** The master work order page now lists the trades on its job (trade, assignee, predecessor), each row linking to its own work order page, above a create-trade form calling `create_trade_work_order` through a new `createTradeWorkOrder` server action — `getSession()` first, RPC only, `revalidatePath` then `redirect`, never returning data. The action passes the RPC's error message through verbatim and **deliberately re-implements none of its validation**; `trade` is forwarded even when empty so the user sees the RPC's own "trade is required on a trade work order" rather than an error boundary. Redirect goes back to the master, not into the new trade, because trades are added several at a time and the master is where the list that proves it worked lives. **A trade page renders neither the form nor the list** — trades do not nest — and instead gets an "↑ Master work order" link plus a chip naming its trade. **Verified by authenticated-role probe (`request.jwt.claims` set to a real BMR member) inside a DO block that raises at the end, so the whole test rolled back:** both production masters report `kind='master'`, `trades=0` → empty state; two trades created (Roof/crew, Gutters/subcontractor with Roof as predecessor) both appeared in the master's list query with correct assignee and predecessor labels; `fetch_work_order` on the new trade returned `kind='trade'` (its own page loads); all five refusals fired with readable messages, including the case-insensitive duplicate guard ('roof' vs 'Roof'). Post-probe counts unchanged at 2 work orders / 0 trades / 2 jobs / 0 activity — **zero residue, no test data on real BMR records.** Route compiles and serves (785 modules, redirects to `/login` unauthenticated). `tsc --noEmit` and `next lint` clean. | Jacob + Claude Code |
| 2026-08-18 | **`database.types.ts` was stale against A1.1 — found and fixed while building A1.3a.** `work_orders` was missing **all six** columns A1.1 added (`job_id`, `kind`, `trade`, `assignee_type`, `assignee_ref`, `predecessor_id`), still declared `estimate_id` as `isOneToOne: true` though A1.1 dropped `work_orders_estimate_id_key`, and the `jobs` table was **absent from the types entirely**. A1.1 and A1.2 both shipped without regenerating them; nothing caught it because no code had yet read the new columns. This is the §4.7 divergence reappearing one layer up — the repo not representing the database — and it is worth noting that **`tsc` passing is not evidence the types match the schema**, only that the code agrees with whatever the types happen to say. Corrected by hand against `information_schema.columns` and `pg_constraint` on the live database. | Jacob + Claude Code |
| 2026-08-18 | **UI stopgap recorded, not silently absorbed: delete is no longer offered on a master that has trades.** Making trades creatable created a way to orphan them — `delete_work_order` does not yet know about children, so deleting a master would leave its trades behind with the job intact. The real fix is A1.4's *Done when* ("deleting a master with children is refused or cascades explicitly") and it belongs at the RPC layer. A1.3a only removes the button, which is a UI convenience and **not** enforcement: a direct RPC call still orphans. Flagged here so A1.4 does not mistake the missing button for a solved problem. | Jacob + Claude Code |

| 2026-08-19 | **A1.3b COMPLETE — child RPCs re-pointed to their level.** Migration `20260819002237_a1_3b_child_rpc_repoint_trade_and_master` applied via MCP. **Function DDL only — no table created, altered or dropped; no row inserted, updated or deleted.** First statement dropped the A1.2 shim `create_work_order_from_estimate(p_estimate_id uuid)`: signature copied verbatim from `pg_get_function_identity_arguments()`, a bare `DROP` rather than `DROP … IF EXISTS` so a wrong signature would fail loudly instead of silently succeeding (rule 2), zero repo callers proven by grep first, and 0 remaining re-verified in `pg_proc` after (rule 3). **TRADE level** — `add_material_item`, `add_schedule_block`, `create_check_in`, `get_or_create_production_packet` refuse a master. **MASTER level** — `record_work_order_sign_off`, `create_work_order_agreement`, `fetch_work_order_agreement` refuse a trade (`fetch_work_order_agreement` converted from `language sql` to plpgsql purely so it can raise; same name, args, `SETOF work_order_agreements` and STABLE, so a replacement not an overload). **CHILD-ID** — `update_material_item` and `delete_material_item` keep taking only a material-item id and resolve their level through the parent work order; adding a work-order argument would have let a caller name a level different from the one the row actually sits on. All nine kept their exact signatures, so every `CREATE OR REPLACE` is a true replacement — overload count verified at exactly 1 for all nine plus both new helpers. Advisors re-run: **0 ERROR** (358 WARN, 7 INFO, all pre-existing). | Jacob + Claude Code |
| 2026-08-19 | **DECISION — one shared `assert_work_order_level()` rather than the same guard inlined nine times.** Nine functions needed the identical three-part check (exists · in one of my orgs · right level). Nine copies is how nine functions drift apart, and it would have produced nine slightly different refusal messages. The helper returns `org_id` so callers keep their existing `v_org_id` flow, and the message register matches A1.2's — it names both the level found and the level required, plus a clause saying where that object actually belongs. `coalesce(v_kind, '')` rather than a bare `<>` is rule 5: a null kind makes the comparison null and PL/pgSQL reads a null IF as false, which would have let the wrong level straight through. **Neither helper is granted to `anon`/`authenticated`** — an explicit `revoke` in the same migration, since nothing outside the SECURITY DEFINER callers should reach them. Net effect on §6.9: the anon-executable security-definer surface went **110 → 109**, shrinking rather than growing. | Jacob + Claude Code |
| 2026-08-19 | **THREE SILENT BREAKAGES CAUGHT INSIDE A1.3b — none of them would have raised an error.** (1) *The after-sign-off audit trail (§4.3) would have gone dead.* Every `*_after_signoff` branch keyed off the work order's own `sign_off_at`; after the re-point that column is only ever set on a master while materials live on trades, so a trade's `sign_off_at` is null by construction and the audit would simply have stopped firing. New helper `job_master_sign_off()` resolves the master through `job_id`. (2) *The agreement snapshot would have serialised an empty material list.* `create_work_order_agreement` gathered materials and schedule with `where work_order_id = <the master>`; those rows now live on trades, so every signed agreement would have captured `[]` — the legal document silently losing its contents. It now gathers across the job's live trades with each entry labelled by trade. Safe to reshape rather than version because `work_order_agreements` is at zero rows and nothing in the UI reads `snapshot` (verified by grep), so rule 5b does not bite. (3) *`update_material_item`/`delete_material_item` checked only the material item's own `org_id`*, so a row whose org had drifted from its parent work order's would have passed on the item's org alone; both orgs are now checked and must match. **All three were found by asking what the re-point makes false, not by a failing test** — nothing in the *Done when* would have caught any of them. | Jacob + Claude Code |
| 2026-08-19 | **DECISION — after-sign-off activity is logged against the MASTER, not the trade.** What goes stale when a material changes after sign-off is the master's signed agreement, and the master is where a human looks for "what changed since I signed". The trade is named inside the logged value (`Standing seam panels (24ga) (qty 44) [Roof]`) so the detail survives. Consequence recorded as debt: "which trade changed?" is answerable only by parsing a string, and would want a `subject_work_order_id` column if it ever becomes a real query. | Jacob + Claude Code |
| 2026-08-19 | **A1.3b UI half — child forms render only where their object can exist.** Master page: sign-off panel and the trade list; **no** material or schedule forms. Trade page: material list, schedule blocks and their forms; **no** sign-off, **no** trade list. Progress chips are now level-aware — the sign-off chip always reads the MASTER's `sign_off_at` (a trade reading its own column would permanently show "not signed off" on a signed job), and material/schedule counts are job-wide on a master and own-trade on a trade. `canDelete` likewise: a master accounts for children it no longer owns directly. The master keeps a one-line roll-up saying where materials and schedule went rather than looking like it lost them. **This is not SCOPE §2.8 blocking** — §2.8 forbids disabling a control because *other data* is incomplete; nothing here is disabled pending anything, the control is simply absent at a level where its object cannot exist. The field module needed no change: it derives its list from `schedule_blocks`, which are now trade-scoped automatically. | Jacob + Claude Code |
| 2026-08-19 | **Verified BOTH directions, because a refusal that refuses everything also passes a negative-only *Done when*.** Rolled-back authenticated-role probe against a real BMR master. **Positive:** material item, schedule block, check-in and production packet all attached to a trade; sign-off recorded on the master; agreement created on the master with `materials=1 schedule=1` gathered across the trades and the first entry reading `{"name": "Standing seam panels", "trade": "Roof", "quantity": 42, "ready_by": "2026-08-24"}`; `fetch_work_order_agreement` returned 1 row on the master; the after-sign-off audit fired and both rows landed on the master with the trade named. **Negative:** all four child RPCs refused on the master, all three master RPCs refused on a trade. **Zero residue** — post-probe counts 2 work orders / 0 trades / 2 jobs / 0 materials / 0 blocks / 0 check-ins / 0 packets / 0 agreements / 0 activity / 0 signed off, all unchanged. No test data on real tenant records. | Jacob + Claude Code |
| 2026-08-19 | **§4.7 IS STALE — the divergence grew while A1 was running, and it is worse than "39".** Recounted 2026-08-19: **81 remote entries vs 47 local files; 78 remote entries have no version match; 49 have neither a version nor a name match — i.e. 49 remote migrations exist with no repo file at all**, against the 39 recorded in §4.7. Twenty-three of the 49 are `wh_*`. All five migrations applied on 8/18 (`cp3_tuesday_step0_backups_20260818`, `wh_price_history`, `wh_product_types`, `wh_product_roles`, `wh_variation_colors`) have **no repo file**, so the Material Matrix work is still being applied outside the repo *after* D7 recorded that no database change is made outside it. Reported, not fixed — §4.7's numbers should be corrected and A1.0 reconsidered, but not on A1.3b's day. | Jacob + Claude Code |
| 2026-08-19 | **CLAUDE.md migration-discipline rule 6 added** — "`tsc` passing is not evidence the generated types match the schema, only that the code agrees with whatever the types happen to say. Regenerate or hand-verify `database.types.ts` against `information_schema` in the same task as any migration that adds or drops a column, table or constraint." Promoted from the 2026-08-18 change-log row to a standing rule, with the A1.1 staleness cited as the case that produced it. | Jacob + Claude Code |
| 2026-08-19 | **§5.1 A1.3b *Done when* extended to three clauses** — added "and the master page no longer offers child-object forms it will refuse." A1.3a exists so refusals have somewhere to go; leaving the master rendering material and schedule forms that now always fail would have re-created the problem the A1.3a/A1.3b split was made to avoid. Directive set to v1.6. | Jacob + Claude Code |

| 2026-08-19 | **SCOPE CHANGE — D7 AMENDED.** Added: "D7 binds every migration against the `structtech` project, not only the OS app. Material Matrix work runs on the shared backend (D6) and is therefore in scope: every schema change originates in a repo migration file, whichever app or session applies it. A change applied without a repo file is a defect to be reported, not a shortcut to be absorbed." **Recorded as a scope change, not an implementation detail, because amending a Decision of Record is one (§3).** Reason: five migrations landed outside the repo on 2026-08-18 — `cp3_tuesday_step0_backups_20260818`, `wh_price_history`, `wh_product_types`, `wh_product_roles`, `wh_variation_colors` — **after** D7 was recorded on 2026-08-16, and §4.7's gap grew from 39 to 49 remote migrations with no repo file. D7 as originally worded was read as governing the OS app's own work; the amendment closes that reading. The shared backend is one database, so "outside the repo" has to mean outside the repo for everything that touches it. | Jacob + Claude Code |
| 2026-08-19 | **§4.7 CORRECTED with measured figures (2026-08-19).** 81 remote entries vs 47 local files; 78 remote entries with no version match; **49 with neither a version nor a name match — 49 remote migrations with no repo file at all, against the 39 recorded on 2026-08-16. Twenty-three of the 49 are `wh_*`.** The 2026-08-16 figures are retained above the correction rather than overwritten, per §10's rule that superseded text stays as written. **It grew by 5 in a single day.** That rate, not the absolute number, is what changed the plan: see the A1.0 row below. | Jacob + Claude Code |
| 2026-08-19 | **A1.0 SCHEDULED — first task after A1 acceptance, no longer indefinitely deferred.** A1.0 was reclassified to hygiene on 2026-08-16 on the reasoning that the divergence does not prevent new migrations. That reasoning still holds, but it assumed a static gap; the gap is growing at ~5/day. **A baseline reset against a divergence that is still growing is obsolete the week it is taken**, so the decision of 2026-08-19 is two-step and ordered: **stop the growth now** via the D7 amendment (§3), **then reset the baseline** once it has stopped. Recorded in §5.1 and in §11 under Sat 8/22. | Jacob + Claude Code |
| 2026-08-19 | **Carried debt recorded — `update_material_item` and `delete_material_item` enforce org but NOT level.** They rely on the invariant that no material item can exist on a master, because `add_material_item` refuses to create one. The invariant holds and the design is right — a child id should resolve its level through its parent rather than take a level argument. But it is **implicit, not enforced**: a row placed on a master by a service-role script or a future backfill would be freely editable and deletable by these two. **This is recorded because A1.4's INHERIT pass covers 13 more functions with exactly this shape, and the distinction is the work: "inherits its level from its parent" and "assumes an invariant nothing enforces" are indistinguishable from outside the function.** A1.4 must decide which of the 13 is which, per function — not confirm that they compile. | Jacob + Claude Code |
| 2026-08-19 | **STANDING CORRECTION on task ordering, controller-recorded.** The A1.3b brief ordered the migration before the UI inside a single task — which is the rule 5b shape the A1.3a/A1.3b split was created to prevent, and it opened a real window in which the deployed master page offered material and schedule forms the RPCs already refused. Flagging it rather than complying silently was correct. **The rule from here: within a single task the UI half is authored first, and the migration is the last thing that touches prod.** | Jacob + Claude Code |
| 2026-08-19 | **A1.3b close-out — directive synced to v1.7.** Docs only: no source file and no database object changed. §3 D7 amended (scope change, above) · §4.7 corrected with measured figures · §5.1 A1.0 rescheduled · §11 Sat 8/22 carries the A1.0 line · §1 carried debt now three items. Version 1.6 → 1.7 because §5 and §11 changed materially. | Jacob + Claude Code |

| 2026-08-19 | **CORRECTION, controller error.** The A1.3b brief asserted 'Jacob has confirmed the A1.3a trade surface is live in the browser' as a settled fact. He had not confirmed it; the controller supplied the premise. The shim was therefore dropped on an unmet gate. No harm resulted — nothing in the repo called the shim and the UI shipped in the same commit — but this is the same failure as a *Done when* marked pass on reasoning rather than evidence, applied to the controller's own gate. A gate is cleared by the person who holds it saying so, or it is not cleared. The browser check remains OUTSTANDING and now covers both A1.3a and A1.3b's UI. | Controller |
| 2026-08-19 | **§11 RE-DATED — the controller was reading UTC and called Tuesday "Wednesday".** A1.3a **and** A1.3b both shipped on **Tuesday 8/18**: the A1.3b migration is stamped `20260819002237`, which is 8:22 PM EDT on 8/18. The week is now Sun 8/16 Foundation+A1.1 · Mon 8/17 A1.2 · Tue 8/18 A1.3a+A1.3b · Wed 8/19 A1.4 · Thu 8/20 A1.5 · Fri 8/21 A1 Acceptance · Sat 8/22 buffer / A1.0 prep. **The buffer is restored** — splitting A1.3 cost no calendar time. The Wed 8/19 row, which read "✅ SHIPPED" and then continued in future tense, was rewritten: §11 is the live week, not a log, and a completed row reads as a record rather than a standing order. | Jacob + Claude Code |
| 2026-08-19 | **DECISION — `delete_work_order` on a MASTER WITH CHILDREN IS REFUSED, not cascaded.** §5.1's A1.4 *Done when* permits either ("refused or cascades explicitly"). Refuse is the decision (controller, 2026-08-19). Delete is irreversible; void is the reversible path and it already cascades. A delete cascade would let one call destroy a job's whole production record. The refusal names the child count and points at void: *"work order <id> is a master with 3 trade work order(s) under it and cannot be deleted — that would destroy the whole job's production record and cannot be undone. Void it instead: voiding a master voids its live trades and can be restored."* Deleting a childless master, or a trade, is unchanged. | Controller + Claude Code |
| 2026-08-19 | **DECISION — the cascade marker is an explicit column, not a matching timestamp.** `work_orders.void_cascade_source_id` (and the same on `work_order_agreements`, plus `void_cascade_prior_status`). NULL = live or voided in its own right; non-NULL = voided by that master's cascade. Void marks only trades that were LIVE at the time; restore clears only rows carrying that master's id. **Matching `voided_at` values were rejected as the mechanism:** `now()` is transaction-constant, so two unrelated voids in one transaction collide and two related voids in separate transactions do not match — the scheme is unprovable from the row. The Monday/Tuesday case is the proof and it passed: trade voided alone, then master voided, then master restored → the independently-voided trade stayed voided while the two cascade-voided trades came back. | Jacob + Claude Code |
| 2026-08-19 | **DECISION — restore DOES reactivate a cascade-voided agreement, to its exact prior status.** An agreement for a voided master is not active by definition, so voiding a master voids it in the same statement with `void_cascade_prior_status` preserved. Restore puts that status back — but only for agreements this cascade voided, and only when the work order has no active agreement already. A change order voids and replaces; reactivating a superseded agreement would produce two active documents. Stated explicitly in the function body rather than left to row order. | Jacob + Claude Code |
| 2026-08-19 | **DECISION — `fetch_work_order` was NOT re-typed; `fetch_work_order_tree` was added instead.** The brief asked for fetch_work_order to become hierarchy-aware. Its `returns setof work_orders` shape is exactly what the CURRENTLY DEPLOYED coordination and field pages read, and rule 5b forbids a migration that breaks the deployed UI before its own deploy lands. It does become hierarchy-aware for free — `void_cascade_source_id` is part of the row type, so every caller now receives it — and the tree itself (level, master id, per-trade voided/cascade state and counts) is served by the new `fetch_work_order_tree(uuid) returns jsonb`, which also replaced two ad-hoc job-scoped table queries and a second round trip in the page. **Recorded as a deviation from the literal brief, not absorbed silently.** | Claude Code |
| 2026-08-19 | **FINDING — the 13 INHERIT functions were 13/13 BROKEN, not "verify only".** §4.4 described them as inheriting their level from their parent. None of them reads the parent's `kind` at all; each reads `org_id` off its own row and nothing else. The guarantor that made them look like ASSUMES — `create_check_in` / `add_schedule_block` / `get_or_create_production_packet` / `add_material_item` refusing a master — **is bypassable**: the child tables' own `member insert own <table>` RLS INSERT policies test only `org_id`, so an authenticated user can insert a check-in, material item, schedule block or production packet straight onto a master. Probe-confirmed: the RPC refused and a plain `insert` of the same row succeeded in the same session. A guarantor that can be walked around is not a guarantor, so the verdict is BROKEN. All 13 now ENFORCE their level through the parent via `assert_work_order_level()`, which also moves their org check off the child's own row and onto the parent — A1.3b's silent breakage #3, which had been fixed for material items only. `update_material_item` and `delete_material_item` were fixed in the same pass, clearing the A1.3b debt: 15 functions. | Jacob + Claude Code |
| 2026-08-19 | **§4.4 CORRECTED and §6.9 extended.** §4.4's INHERIT row no longer says "verify only" — it records 13/13 BROKEN and the fix. §6.9 gains the RLS INSERT hole as an open item routed to A1.5, with the note that it contradicts CLAUDE.md's Supabase rule 3 as written (that rule describes the app's pattern, not a property of these tables). | Jacob + Claude Code |
| 2026-08-19 | **VERIFIED BOTH DIRECTIONS, again, because a lifecycle that refuses everything also passes a negative-only *Done when*.** Rolled-back authenticated-role probe against a real BMR master. **Positive:** cascade void 3/3 trades; restore 3/3; agreement voided on master-void and reactivated to `pending` on restore; independently-voided trade restorable by name once its master is live; childless-master delete and trade delete both succeed; `fetch_work_order` returns kind=master on the master and kind=trade on a trade; `fetch_work_order_tree` returns level+master_id+3 trades from either level; **15/15 child functions succeeded on a legitimately-parented row.** **Negative:** delete of a master with 2 trades refused naming the count; delete of a predecessor trade refused rather than raising a raw FK error; restore of a trade under a voided master refused; **15/15 child functions refused a row placed on a master by direct insert.** **Zero residue** — post-probe counts 2 work orders / 0 trades / 0 voided / 0 cascade-marked / 2 jobs / 0 materials / 0 blocks / 0 check-ins / 0 packets / 0 agreements / 0 activity / 0 signed off, all unchanged. No test data on real tenant records. Overload count 1 on all 21 touched functions. Advisors 0 ERROR. | Jacob + Claude Code |
| 2026-08-19 | **CONTRADICTION REPORTED, not reconciled — the repo/database divergence grew again TODAY.** Two more migrations landed on the `structtech` project on 2026-08-19 with no repo file: `cp3_wednesday_step0_backups_20260819` and `wh_catalog_editor_dual_write_rpc`. That is **after** the D7 amendment of the same day, which exists specifically to stop this. §4.7's count of 49 remote-without-repo is already stale in the direction of worse. Reported per D7's own wording — "a change applied without a repo file is a defect to be reported, not a shortcut to be absorbed" — and left for A1.0 rather than fixed on A1.4's day. | Claude Code |
| 2026-08-19 | **A1.4 close-out — directive synced to v1.8.** §1 rows advanced and carried debt rewritten (two items, the RLS INSERT hole and the activity-string item) · §4.4 INHERIT row corrected · §6.9 gained the RLS INSERT bullet · §11 Wed 8/19 marked shipped. Version 1.7 → 1.8 because §4.4 changed materially. | Jacob + Claude Code |
| 2026-08-20 | **DECISION — A1.5 does NOT invert `has_capability()`'s global default.** Controller, 2026-08-20. Flipping the fallback array would change what every existing member can see, mid-week, one day before acceptance — a behaviour change to a shipped, deployed mechanism, which is rule 5b's shape even though no migration breaks. Instead: a crew member is created with EXPLICIT permissions, and the master/dollar gates are enforced on their own terms at RPC and RLS. **Implementation:** two new functions, `can_view_master_work_order(uuid)` and `can_view_financials(uuid)`, with the same three-tier shape as `has_capability()` (manager short-circuit → explicit `org_members.permissions` key → default) but a **role-derived, closed** default: `role not in ('field','client_portal_viewer')`. No existing member's answer changes — all four current members are manager-tier and short-circuit to true. The permissive default is recorded in §6.9 with its own line and scheduled for A2. | Controller + Claude Code |
| 2026-08-20 | **THE CREW-ROLE PROBE — what it actually was.** `org_members.user_id` has an FK to `auth.users(id)`, so a synthetic uuid will not insert. The probe therefore creates a **real `auth.users` row and a real `org_members` row with `role='field'`** inside the rolled-back transaction, then `set local role authenticated` with that user's `sub`. It is a genuine crew-role member for every purpose RLS and `auth.uid()` can observe, and it leaves nothing behind. **Not a blocker, and not an owner-session dressed up as a crew test.** Note for the record: the directive says "crew"; the database's name for that role is **`field`** — `org_members_role_check` allows owner/admin/office/field/client_portal_viewer/agency_admin/member, and there is no value called 'crew'. | Jacob + Claude Code |
| 2026-08-20 | **MEASURED BEFORE, MEASURED AFTER — constraint 7 was being broken, with numbers.** Baseline as a real `role='field'` member, before any change: the MASTER readable both by RPC and by direct select; **4 estimates with `presented_total` up to 34000.00**; **21 estimate line items**; **191 deals with `value` up to 82000**; `fetch_estimate` returning 34000.00; and `has_capability(org,'view_financials')` returning **true**. After A1.5: master 0 / 0, estimates 0, line items 0, deals 0, `fetch_estimate` money NULL — while the crew still reads its own trade (1 by RPC, 1 by direct select), its own check-in and schedule block, and its job header via `fetch_field_jobs`. **Owner unchanged in the same transaction:** master 1, trade 1, 3 work orders, `presented_total` 34000.00, 191 deals. A gate that blocks everyone also passes a crew-only *Done when*; this one does not block the owner. | Jacob + Claude Code |
| 2026-08-20 | **DECISION — the crew gates are RESTRICTIVE policies, not edits to the existing permissive ones.** Every policy on the affected tables is PERMISSIVE, and permissive policies OR together — `deals` already carries a second one (`staff all deals`, `is_staff()`). Adding a condition to `member read own deals` would therefore have gated nothing. RESTRICTIVE policies AND with everything else and cannot be OR'd around by a policy that exists now or is added later. Six tables: `work_orders` (master), `work_order_agreements` and `work_order_activity` (master-level documents), `estimates`, `estimate_line_items` and `deals` (money). | Jacob + Claude Code |
| 2026-08-20 | **BOTH LAYERS, because neither is sufficient.** RLS does not protect a SECURITY DEFINER function — it runs as the owner and bypasses policies entirely — so the same gate is written into `fetch_work_order`, `fetch_work_order_tree` and `fetch_estimate` as well as into the policies. And an RPC gate alone is bypassable by a direct table read, which is the lesson A1.4 produced from the other direction. `fetch_estimate` keeps its name, argument and `setof estimates` return type but returns `subtotal`, `presented_total`, `tax_rate` and `tax_amount` as NULL to a caller without financials; new `fetch_field_jobs(uuid, date)` feeds the crew Today list from a select list containing **no money column at all**, so the field UI keeps its job header after `estimates` is closed to crew. | Jacob + Claude Code |
| 2026-08-20 | **A1.4's RLS WRITE HOLE CLOSED — and the app write path verified BEFORE, not assumed.** `check_ins`, `material_items`, `schedule_blocks` and `production_packets` now require, on INSERT **and** on UPDATE, that the referenced work order be in one of my orgs **and** be `kind='trade'` (`work_order_is_my_trade()`). UPDATE matters as much as INSERT: without it a legitimate row could be MOVED onto a foreign or wrongly-levelled work order after creation. **The check that made this safe to do:** a grep for `.insert(` / `.update(` / `.delete(` across `src/` returns **zero matches** — every write in the app goes through a SECURITY DEFINER RPC, which these member policies do not apply to. Probe: six attacks blocked (child onto master ×4, foreign `org_id`, and the UPDATE-move), two positive controls still passing (a direct update on a trade-parented row, and `update_check_in` through the RPC). | Jacob + Claude Code |
| 2026-08-20 | **§6.9 CORRECTED — the `anon` sweep is done, and the old entry's reassurance was false.** `revoke execute … from public, anon` over every postgres-owned security-definer function in `public` (signatures from `oid::regprocedure`, never retyped), paired with `alter default privileges for role postgres … revoke execute on functions from public, anon` — one is not a fix without the other, since the grant comes from BOTH a PUBLIC grant and an explicit `anon=X`. Advisor count **109 → 2**. `authenticated=X` is a separate explicit grant on 111 of 113, so no blanket re-grant was issued and A1.3b's two deliberately-revoked internal helpers stayed revoked. **The old claim that "every one of the 109 is refused on its first statement by `my_org_ids()`" is false:** `create_wh_order` opens `IF auth.uid() IS NULL THEN v_org := v_supplier` — an explicit anonymous branch — and is the Material Matrix storefront's order RPC. It and `get_wh_order` are the remaining 2, **deliberately excluded and reported**: revoking them would break live order placement on a customer-facing site this repo cannot test. | Jacob + Claude Code |
| 2026-08-20 | **CONTRADICTION REPORTED, not reconciled — the divergence grew again, twice more.** Since the A1.4 close-out three further migrations have landed on `structtech` with no repo file: `wh_catalog_editor_dual_write_rpc` and `cp3_wednesday_step0_backups_20260819` (2026-08-19), and `bmr_tickets_schema_standalone` (2026-08-20). The last one is visible in the advisors: 10 new `rls_enabled_no_policy` INFO findings (`bmr_ticket*`, `tg_agenda_*`) and 2 new `function_search_path_mutable` WARNs (`bmr_tickets.touch`, `public.bmr_ticket_touch`), none of them from A1.5. Reported per D7's own wording; it belongs to A1.0. | Claude Code |
| 2026-08-20 | **A1.5 close-out — directive synced to v1.9.** §1 rows advanced, carried debt rewritten as a four-item acceptance checklist, A1.4's debt marked cleared · §6.9's `anon` bullet struck through and corrected, plus two new findings (`has_capability` fails open; money columns outside A1.5's gates) · §11 Thu 8/20 marked shipped. Version 1.8 → 1.9 because §6.9 changed materially. | Jacob + Claude Code |
| 2026-08-20 | **FINDING — the `http` extension is live on production and `anon` + `authenticated` can execute all 14 of its functions.** Left behind by `tmp_http_for_bot_diagnosis` (`20260820020138`) with no drop after it; found by the controller while verifying A1.5. Version 1.6, schema `extensions`, grants inherited from a PUBLIC grant (`=X/supabase_admin`). **A1.5's `alter default privileges` sweep covers schema `public` only and does not reach it.** Repo grep for `http_get` / `http_post` / `http(` / `extensions.http` across `src/` and `supabase/`: **0 matches** — nothing in this repo calls it. | Controller + Claude Code |
| 2026-08-20 | **DECISION (Jacob) — revoke the `http_*` grants, KEEP the extension.** Not dropped: the tg_agenda bot is not in this repo and may call `http_*` at runtime, so dropping it needs that owner's confirmation. `postgres` and `service_role` to be left untouched so an edge function or a definer-owned caller keeps working; only direct anon/authenticated calls stop. | Jacob |
| 2026-08-20 | **BLOCKED — the decided revoke CANNOT BE PERFORMED from this connection, and a migration attempting it would report success while changing nothing.** Proven in a rolled-back test, not reasoned: the `http_*` functions are owned by `supabase_admin` and the PUBLIC grant was made by `supabase_admin`; only a grantor can revoke its own grant. `postgres` is **not** superuser (`rolsuper=false`), **cannot** `set role supabase_admin` (*permission denied to set role*), and **cannot** take ownership (*must be owner of function http_get*). The revoke executed anyway and `anon`/`authenticated` both still read `true` afterwards — Postgres emits a warning, not an error. **Same class of failure as migration-discipline rule 2, so no migration was written or applied.** Reported rather than routed around, per §0. | Claude Code |
| 2026-08-20 | **OPTION PREPARED, NOT APPLIED — `revoke usage on schema extensions from anon, authenticated`.** This one does work from `postgres`, which owns the `extensions` schema (`nspacl`: `anon=U/postgres, authenticated=U/postgres`), and it took effect in the same rolled-back test. **Blast radius measured:** `extensions` also holds `pgcrypto`, `uuid-ossp` and `pg_stat_statements`, but `public` has **0** column defaults, **0** constraints and **0** invoker-rights functions referencing `extensions.*`; SECURITY DEFINER functions run as their owner and are unaffected; `service_role`/`postgres` USAGE is untouched. **Not applied because it is a different mechanism from the one decided**, with a wider surface than `http_*`, on a shared backend serving two apps this repo cannot test, the day before A1 acceptance. Jacob's call. | Claude Code |
| 2026-08-20 | **OPEN AND UNVERIFIED — is `extensions` in the project's exposed schemas?** It decides how serious the finding is and it cannot be read from SQL: `pg_db_role_setting` for `authenticator` carries only `session_preload_libraries`, `statement_timeout` and `lock_timeout` — no `pgrst.db_schemas` — so the list lives in the Supabase API config. **Must be checked at Settings → API → Exposed schemas.** If `extensions` IS exposed, `http_get` was callable over `/rest/v1/rpc/` with the anon key, which is a server-side request-forgery surface on production and a materially worse finding than recorded. **Stated as unverified rather than assumed to be the safe default.** | Claude Code |
| 2026-08-20 | **§4.7 CORRECTED — fourteen non-A1 migrations landed on 2026-08-20, four of them after A1.5.** `tg_agenda_bot_schema`, `tg_agenda_bot_assets_bucket`, `tmp_enable_http_for_verification`, `tg_agenda_cleanup_unused_assets`, `tg_agenda_per_user_sessions_and_group_optin`, `tmp_enable_http_verify_v3`, `tmp_drop_http_after_verify`, `tmp_http_for_bot_diagnosis`, `bmr_field_ticket_schema`, `bmr_tickets_schema_standalone`, `cp3_thursday_backup_categories_20260820`, `wh_categories_image_url_backfill`, `cp3_thursday_backup_systems_20260820`, `wh_systems_hero_image_rehost` — none with a repo file. **The rate is the finding, not the total: ~5/day on 2026-08-16, 14 on 2026-08-20.** Four are named `tmp_`, and one of those left the `http` extension on production. The divergence has stopped being a bookkeeping problem and has become the delivery mechanism for un-reviewed security changes. **A1.0 does not slip again.** Also for the record: `tmp_drop_http_after_verify` (`20260820013529`) did drop `http` once, and `tmp_http_for_bot_diagnosis` re-installed it 46 minutes later and did not. | Claude Code |
> **Append a row here on every completed task and every decision change. Do not rewrite history.**

---

# 11 · ACTIVE EXECUTION WEEK

**Stage A1 — Job Spine · Sun Aug 16 → Sat Aug 22, 2026**

> If asked "what am I doing today," read this section together with §1. Today's directive is the row matching today's date. If §1 says the previous day's task did not pass its *Done when*, that task carries and the rest of the week shifts by one day — do not skip ahead.

| Date | Task | Directive |
|---|---|---|
| **Sun 8/16** | A1 Foundation + A1.1 | ✅ Anon exposure closed (backups archived, advisors clean). ✅ RPC surface inventoried — corrected 14 → 27, see §4.4. ✅ Directive committed to `docs/` + pointer in `CLAUDE.md`. ✅ Targeted pre-A1.1 backup (5 tables, row-count verified). ➖ A1.0 migration baseline reset — **DEFERRED**, hygiene not blocker (§4.7). ✅ **A1.1 shipped early** — job spine schema applied and verified. **Every migration goes through MCP `apply_migration`; never `db push` / `db reset`.** |
| **Mon 8/17** | A1.2 Creation RPCs | ✅ **SHIPPED.** `create_job_from_estimate` (job + master, returns jsonb) + `create_trade_work_order` (inherits org/estimate/job from the master; external subcontractor valid per D1). `create_work_order_from_estimate` retained as a deprecated shim per rule 5b, dropped in A1.3. Migration `20260817151709`, overload count 1 on all three, repo and call sites re-pointed in the same commit. **A1.1 was pulled forward to Sunday, so the rest of the week moves up a day.** |
| **Tue 8/18** | A1.3a + A1.3b | ✅ **BOTH SHIPPED, same day.** **A1.3a — trade surface, UI ONLY**, no migration and no database change: master page lists its job's trades (trade, assignee type, assignee ref, predecessor), each row linking to its own page; create-trade form calls `create_trade_work_order`; trade is **free text, never a fixed dropdown** — datalist suggestions only; RPC errors surfaced verbatim; trade pages do not offer "create trade". **A1.3b — child RPC re-pointing**, migration `20260819002237` (stamped 8:22 PM EDT on 8/18), advisors 0 ERROR, both directions probe-verified: shim dropped as the first statement, materials/schedule/check-ins/packets re-pointed to **trade**, sign-off and agreements to **master**, wrong-level calls refused, master page no longer offers forms it would refuse. **Browser confirmation on `os.structtek.com` is still OUTSTANDING and now covers both halves' UI** (§10, 2026-08-19 controller correction). |
| **Wed 8/19** | A1.4 Lifecycle | ✅ **SHIPPED.** UI authored first, migration `20260819233735` last. Cascade marker column on `work_orders` and on `work_order_agreements`; void cascades master→live trades and voids the active agreement; restore reverses only the cascade, so a deliberately-voided trade survives (Monday/Tuesday case proved); delete of a master with children **refused**, message names the count; `fetch_work_order` left alone per rule 5b and a new `fetch_work_order_tree` serves the tree. **The 13 INHERIT functions came back 13/13 BROKEN, not "verify only"** — all fixed, plus the two material-item functions carried from A1.3b. 15/15 positive and 15/15 negative in a rolled-back probe, zero residue, advisors 0 ERROR. New debt: the RLS INSERT hole, routed to A1.5. |
| **Thu 8/20** | A1.5 Crew visibility | ✅ **SHIPPED.** UI first, migration `20260820133834` last. **A1.4's RLS write hole closed** on INSERT and UPDATE across all four child tables (parent must be mine AND a trade) — verified first that no app write goes direct, so nothing in the write path could break. **§6.9 `anon` sweep done and paired** with `alter default privileges`: 109 → 2, the 2 being `create_wh_order`/`get_wh_order`, anon-callable by design for the Material Matrix storefront and reported rather than silently revoked — which also falsified §6.9's claim that all 109 were gated by `my_org_ids()`. **Crew visibility at BOTH layers** via two new closed-default capability functions, RESTRICTIVE policies on six tables, and the same gate inside `fetch_work_order`/`fetch_work_order_tree`/`fetch_estimate`. Probed with a real `role='field'` member: master 0 by RPC **and** 0 by direct select, estimates/line-items/deals 0, `fetch_estimate` money NULL, own trade still readable, owner unchanged. `has_capability`'s fails-open default deliberately NOT flipped — recorded in §6.9 and scheduled for A2. |
| **Fri 8/21** | A1 Acceptance | Run all A1 *Done when* checks end to end against real data. Update §1 and §10. Mark the A1 tracker items shipped. Read §5.2 and fix any gap in this document before Monday. **Done when** A1 closes on evidence and A2.1 is the stated next step. |
| **Sat 8/22** | Buffer / A1.0 prep | Unallocated slack, restored by A1.3a and A1.3b landing on the same day. If nothing slipped, use it to prepare **A1.0 (migration baseline reset)** — the FIRST task after A1 acceptance, see §5.1 and §4.7. It is no longer deferred, and the D7 amendment (§3) is what stops the divergence growing in the meantime. |

**Week guardrails.** One task per day · backup before any migration · blocked means stop and report, never a temporary shape that needs migrating later · Material Matrix support load is not A1 work — if it costs a day, the week shifts a day, it does not compress A1.3b or A1.5.

**The buffer is restored.** Splitting A1.3 into A1.3a and A1.3b cost **no calendar time** — both halves shipped on Tuesday 8/18 — so Saturday 8/22 is slack again. It is slack against a slipped day, not room for new scope. *(This replaces the "No buffer left" note, which was written on the assumption the split would consume a day.)*

**Nothing this week is blocked on another person.**

> **Replace this section at the start of each stage.** When A1 closes, §11 becomes the A2 week.
