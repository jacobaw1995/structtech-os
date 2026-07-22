# CLAUDE.md — StructTech OS Build Directive

You are building **StructTech OS**: one modular, multi-tenant platform that runs StructTech's own business and is licensed, in configurable pieces, to StructTech's clients. **One build, licensed per tenant.** StructTech is tenant #1; contractor clients (e.g. Brothers Metal Roofing) are tenants granted a subset of modules.

**Read these first, in order, before writing any code:**
1. `docs/SCOPE.md` — authoritative product scope: tenant/module/role model, confirmed architecture decisions, data-model direction, non-goals. **If this file and SCOPE.md ever disagree, SCOPE.md wins.**
2. `docs/BUILD_PLAN_3WEEK.md` — the phased sequence and per-phase "done =" acceptance.
2b. `docs/BACKLOG.md` — the durable queue of deferred/queued work (what's owed and what's next). The queue lives here, NOT in this file's phase section or a session's memory.
3. `docs/wireframes/StructTech OS - HiFi (standalone).html` — the **locked visual source of truth**. Match it. Design tokens are extracted below.
4. `docs/reference/` — read-only reference: existing DB schema and domain specs to build on (do not treat as the base app; do not copy wholesale).

---

## Rules of engagement (non-negotiable)

- **Build only inside `structtech-os/`.** Never edit anything outside this folder. The legacy projects (`../structtech/`, `../Brothers Metal Roofing/`) are not accessible and are reference only.
- **Build the current phase only.** Right now that is **Week 1 — Foundation** (see §Current Phase). Do not build Week 2+ features unless told.
- **Do not fork the BMR app or `structtech-pipeline`.** Reuse *patterns*, never copy a whole app. The duplication between those two is exactly what this build ends.
- **Confirm before behavior-changing decisions.** If the user describes a behavior, confirm it's intended before "fixing" it. Never guess at product behavior.
- **Ask before:** applying any migration to the live Supabase project, adding a new dependency, changing auth/RLS/security, or anything touching `structtech_state`.
- **Small, reviewable commits.** One concern per commit. The user reviews diffs.

---

## Tech stack — decided, do not re-litigate

| Layer | Choice |
|---|---|
| Web | Next.js 14 (App Router) + TypeScript |
| Styling | Tailwind CSS (theme mapped to the design tokens below) |
| Backend | Supabase (Auth + Postgres + RLS + Realtime) — existing `structtech` project |
| Files/photos | Cloudflare R2 (S3-compatible) |
| Mobile (later phases) | React Native + Expo + PowerSync/SQLite |
| Email | Resend · **PDFs** | pdf-lib · **Scheduled sends** | Make.com scenario |

All secrets via env vars (`.env.local`). Never hardcode keys or project refs in source.

---

## Supabase + App Router — mandatory patterns

These are learned from repeated debugging. Every violation causes silent RLS failures, 404s, or auth bugs. Follow exactly.

1. **`getSession()` before every DB call.** `getUser()` alone does not load the session into the client; without it PostgREST sends no auth header and `auth.uid()` is null.
   ```ts
   const { data: { session } } = await supabase.auth.getSession()
   if (!session) redirect('/login')
   ```
2. **Always `createClient()` from `@/lib/supabase/server`** in server contexts. Never import `createServerClient` directly; never use the browser client server-side.
3. **All inserts go through security-definer RPCs.** Direct `.insert()` on RLS tables fails even with a valid session.
4. **All single-record fetches (`by id`) go through security-definer RPCs.** Direct `.select().eq('id', x).single()` fails RLS. Always pass `org_id` for RLS context.
5. **List queries are fine with direct table access** after `getSession()` — they resolve through the RLS helper.
6. **Server actions `redirect()`, never `return` data.**
7. **All RLS policies use the existing `my_org_ids()` helper** — never subquery `org_members` directly in a policy (infinite recursion). (This function already exists and is used by 8 live policies; reuse it, don't recreate or alias it.)
   ```sql
   create policy "t_select" on <table> for select
     using (org_id in (select my_org_ids()));
   ```
8. **`Cannot find module './vendor-chunks/...'` / `ChunkLoadError`** = stale build cache, not a code bug: `rm -rf .next && npm run dev`.
9. **R2 browser uploads require CORS** on the bucket (`GET PUT POST DELETE HEAD`, `AllowedHeaders: *`, `ExposeHeaders: ETag`) — set before testing in-browser.

RPC templates (insert returns uuid; fetch returns `setof <table>`, `stable`) live in `docs/reference/` — mirror them for every new entity.

---

## Multi-tenancy model — the core of the whole build

- **Every domain table carries `org_id`.** RLS scopes every read/write by org via `my_org_ids()`.
- **`organizations`** — one row per tenant. `tenant_type` ∈ (`internal`, `contractor`).
- **`memberships`** — (`org_id`, `user_id`, `role`). A user can belong to multiple orgs.
- **`tenant_modules`** — (`org_id`, `module_key`, `enabled`, `config` jsonb). This is the entitlement layer. Nav and route guards render from it.
- **Two axes of access:** *tenant entitlements* (which modules exist for the org) × *user role* (which screens within them). Nav bends to both.
- **Agency operator layer:** StructTech admins operate inside client tenants. Model this simply as a **membership in the client org with role `agency_admin`** — so `my_org_ids()` returns it and RLS needs no special case. The top-bar tenant switcher changes the active org context.
- **License activation = inserting rows** (`organizations` + `tenant_modules` + `memberships`), never provisioning a new database.
- **Escape hatch:** a future enterprise client needing hard isolation can be siloed onto its own Supabase project with the same code — do not design anything that blocks that, but do not build it now.

### Module registry
| module_key | entitled tenant types | notes |
|---|---|---|
| `crm` | all | pipeline; **stages are per-tenant config** |
| `estimating` | contractor | live on-site estimate → sign |
| `coordination` | contractor | sign-off → work order → materials (ready-by gates schedule) |
| `field` | contractor | crew mobile; role-scoped; no pipeline/$ |
| `delivery` | internal (admin) + surfaced read-only inside the client tenant | engagement execution → client portal |
| `scan` + `roadmap` | internal only | already live in the DB |

---

## Design system — match the locked hi-fi

Map these into the Tailwind theme / CSS variables. Pull exact spacing/radius from the hi-fi html.

```
--bg:        oklch(98%   0.004 90)
--surface:   oklch(99.5% 0.002 90)
--surface2:  oklch(95.3% 0.004 90)
--text:      oklch(22%   0.006 90)
--muted:     oklch(48%   0.006 90)
--border:    oklch(88%   0.006 90)
--accent:        oklch(0.55 0.16 250)
--accent-strong: oklch(0.42 0.16 250)
--accent-soft:   oklch(0.93 0.03 250)
--warn:      oklch(0.55 0.15 45)
--warn-soft: oklch(0.94 0.04 45)
```

- **Fonts:** IBM Plex Sans (UI) · IBM Plex Mono (money, measurements, IDs) · IBM Plex Serif (client-portal headings only).
- **Accessibility:** small white-text buttons/chips use **`--accent-strong`**, not `--accent` (AA contrast). `--accent` is fine for large text and fills.
- **Field & estimating (mobile):** outdoor high-contrast mode (black bg) is **available via a toggle, NOT default-on** (updated 7/13 per Jacob — crews switch it on if they need it; default to the normal light theme); **≥56dp touch targets**; single thumb column; never show pipeline or dollar figures in the `field` role.
- **Sync status** is a first-class UI element on all field screens (offline / syncing / synced) — offline-first is a core principle.

---

## Data model direction

**Extend the existing `structtech` Supabase project — do not start a new database.**

> **Reality note (confirmed 7/9):** `organizations` and `org_members` **already exist** in the live project (serving `org_systems`, `tickets`, `org_invoices`, `org_invites`, and the `engagement_*` FKs). They ARE the tenant/workspace concept — **extend them, never create a parallel org concept.** Concretely: add `tenant_type` to `organizations` (+ backfill); use the existing **`org_members` as the membership table** ("memberships" in this doc = `org_members`; expand its role values for `owner`/`agency_admin`/office/crew); `my_org_ids()` reads from `org_members`. Only **`tenant_modules`** is genuinely new. Because this alters tables live features depend on, **branch-test before applying.**

- **Add (Week 1 foundation):** extend `organizations` (add `tenant_type`), extend `org_members` (roles), add `tenant_modules`; the `my_org_ids()` RLS helper (reads `org_members`); org-scoped policies; security-definer insert/fetch RPCs. Backfill `org_id` onto existing tables as a **separate** migration.
- **Reuse (already live — see `docs/reference/`):** `audit_leads`, `client_roadmaps`, `roadmap_playbook()`, `deals` + `follow_ups`, `engagements` / `engagement_levels` / `engagement_milestones` / `engagement_checkins`.
- **Later phases add per module:** estimates + line_items + signatures; work_orders + material_items + schedule_blocks; check_ins + production_packets.

---

## Design so as not to preclude (North Star)

Do **not** build these now, but do **not** make choices that block them (full detail: `docs/SCOPE.md` §12–13):
- **Business logic lives in server actions / RPCs, never buried in components** — this action layer becomes the AI assistant's tool surface later.
- **Append-only activity/history on every domain entity** — it's the audit trail and the AI's "what changed" source.
- **Estimate line items (Week 2) must allow an optional `product_id`** link, not free-text only — client catalogs and the shop plug in here.
- **Org isolation is the default, but don't hard-wire it** so a controlled cross-tenant "published supplier catalog" (StructTech's live shop prices, readable by contractor tenants) becomes impossible. No shared-catalog code now — just don't preclude it.
- **`pgvector`** gets enabled when semantic search arrives — not now.

---

## Migration discipline — learned the hard way, do not skip

1. **`CREATE OR REPLACE` with a CHANGED SIGNATURE creates an OVERLOAD, not a replacement.** Adding even a
   trailing optional param counts. Always `DROP FUNCTION` the exact old signature first. "Safe for existing
   callers" is about *callers* — it says nothing about overloads. (Hit 3+ times: line-item RPCs, milestone
   RPCs, `update_estimate_details`.)
2. **`DROP FUNCTION IF EXISTS` with a mistyped signature SILENTLY SUCCEEDS.** `IF EXISTS` suppresses the
   no-match error, so a hand-transcribed type list that's off by one `text` drops nothing and reports
   success. **Copy the signature verbatim from `pg_get_function_identity_arguments()`; never retype it.**
   (Hit 7/24 on `update_deal_details`.)
3. **Verify DB state after applying — never trust the success response.** Both traps above were caught only
   by re-querying `pg_proc` afterward. Confirm overload counts and that drops actually dropped.
4. **CHECK-constraint value changes need DROP → UPDATE rows → ADD.** Updating rows to a value the *old*
   constraint forbids aborts the migration. (Hit on `lead_type`, again on `estimates.status`.)
5b. **Migrations hit prod IMMEDIATELY; UI deploys lag. A migration must stay backward-compatible with
   the CURRENTLY-DEPLOYED UI until the matching UI ships.** Chunk 1 narrowed `estimates.status` vocabulary
   in prod while the deployed wizard still read the old values — which silently broke estimate *creation*
   (bug #4) AND *step advancement* (flow.ts) in production for days. If a migration changes a value set,
   constraint, or default the live UI depends on, either ship the UI in the same window or keep the change
   additive/backward-compatible until you do. When in doubt, test the DEPLOYED commit against the migrated
   schema (git worktree at the prod commit + live DB) — reasoning isn't enough.
5. **PL/pgSQL treats a NULL `IF` condition as FALSE.** `if not (is_manager or v_owner_id = auth.uid())`
   silently *allows* the action when `owner_id IS NULL`. Wrap nullable comparisons in
   `coalesce(..., false)`. (Hit 7/24 — a real authorization bypass on unowned rows.)

---

## CURRENT PHASE — DEPTH PASS (set 7/20, after Isaac's first real demo)

**STOP BUILDING NEW MODULES.** First client demo exposed the gap: the *foundation* held (security,
tenancy, attribution, the 946-row BMR migration) but the *workflow surface* did not. Estimating,
coordination and field were built fast in Weeks 2–3 as skeletons and never got a depth pass.

**The rule now: depth on what exists, in Isaac's real workflow order, until he'd CHOOSE this over his
old app rather than tolerate it.** No new modules until then.

**Full priority list + detail: `docs/BACKLOG.md` → "🔴 ISAAC FEEDBACK (7/20) — DEPTH PASS."**
Order: **P0** stage-gating removal (SCOPE §2.8) → **P1** estimate builder as a Joist-style
document-as-editor (Manual/Guided toggle), real coordination sign-off (signature + document + homeowner
confirmation), field depth (office-side upload + per-role file permissions), dashboard → **P2** Present
Mode as a true multi-section sales deck that *sells the roof*.

**NEW NON-NEGOTIABLE — SCOPE §2.8 "Never block the user."** Never disable a tab, button, or field
because other data is incomplete. Guidance is advisory. Enforcement is per-tenant config, default OFF.
This ranks with §2.6 (full CRUD) and §2.7 (configurable platform) — all three came from real users
telling us the software was in their way.

---

## PREVIOUS PHASE (COMPLETE 7/19) — CRM Depth (turn the pipeline into a real CRM)

**Weeks 1–3 COMPLETE and live at os.structek.com** — foundation/auth/multi-tenancy/shell (W1); pipeline both tenants + BMR live estimating (W2); BMR coordination + field + management-controls retrofit (W3). All the create/edit/delete controls exist per §2.6.

**Why this phase exists:** what shipped for `crm` is a thin **sales-pipeline view**, not a CRM. Isaac is currently on the BMR app (which he's outgrowing) and StructTech OS's CRM must not be a downgrade. **Full requirements + grounding: `docs/reference/CRM_DEPTH_REQUIREMENTS.md`** — adopt the BMR spec's *features & logic*, NOT its UI/UX/workflow (design fresh from the hi-fi). Every entity gets full CRUD (§2.6).

**RE-FOUNDED 7/14: the CRM Depth phase IS building the Lead Control Center** — the per-lead command center that opens when you click a lead (3-panel desktop/tablet + mobile). What shipped is a thin deal panel; the real design is a stage-driven command center where **every row is a form field AND a checklist item at once.** **Authoritative spec: `docs/reference/LEAD_CONTROL_CENTER_SPEC.md`** (dual-track model, per-stage vital fields, the two checklists, confirmed 3-panel layout). Grounded in BMR's `command-center.ts`/`intake-checklist.ts`/`scope-fields.ts` — **adopt features & logic, design UI fresh.**

**Staged (each reviewable; migrations tight, UI faster):**

1. ✅ **DONE — contact & address data** (shipped): `deals` got `lead_type`/`project_address`/`billing_address`; new-lead form; estimate carries the address.
2. ✅ **DONE — full lead data model** (shipped): split names, structured service address, `intake_checklist` JSONB, milestone timestamps, `owner_id`, tags + RPCs.
3. ✅ **DONE — config-driven command-stage + checklist engine** (shipped): definitions in per-tenant `tenant_modules.config`, TS engine reads config generically. BMR seeded as default.
4. ✅ **DONE + LIVE — Lead Control Center UI** (shipped 7/16, verified on mobile): 3-panel command center, form==checklist inline rows, owner + author-stamped notes. Fix-pass shipped (nested-jsonb completion bug, datetime + roof-type-options fields, add-form → first/last + structured address flowing to checklist + estimate).
5. **✅ DONE (7/19) — Go-live gate: SECURITY + BMR ACCOUNTS + ownership/attribution.** Track A (RLS
   leaks closed, advisor-clean), B (profile-per-user trigger + Isaac seeded as BMR owner, isolation
   probe-verified), C (actor identity on every mutation + owner assignment + edit-by-ownership,
   13-scenario synthetic-rep verified). Isaac can log in scoped to BMR only. Deeper RLS enforcement +
   funnel null-org stopgap tracked in BACKLOG. Original plan text below.
   **← WAS: Go-live gate — SECURITY + BMR ACCOUNTS + ownership/attribution.** **Authoritative plan + live security audit (7/17): `docs/reference/STAGE5_GOLIVE_GATE.md`.** Three tracks, hard-sequenced: **(A) Security** — kill the confirmed `qual=true` leaks (`audit_leads` read, `audits`/`proposals`/`prospects` ALL, `client_roadmaps` update) and re-scope `profiles` + `lead_appointments` off `is_pipeline_user()` (= "any profiled user", not org-scoped); harden `my_org_ids()` search_path; **advisor re-run is the DoD.** (B) Accounts — profile-per-user trigger + backfill the 1 orphan, then seed **Isaac as `owner` in the BMR org via Auth invite (never `staff_users`).** (C) Ownership — owner assignment, actor identity on every mutation, edit-by-ownership (salesman/manager). **Rule: Track A must be advisor-clean BEFORE Isaac's login exists — separate commit.** (Note: RLS-on-structtech_state and most is_staff→my_org_ids items from the old backlog are already done / unnecessary — see the spec.)
6. **Scheduling** — `appointments` (site_survey/inspection; scheduled_at/duration/status). The Schedule quick action → completes the Site Visit stage. (Google Calendar sync later, §13.)
7. **Scope → estimate wiring** — the site-visit **scope checklist feeds the estimate/quote** (closes the site-survey→estimate loop).
8. **Views** — table + calendar (kanban exists). Quick actions are native links now (`tel:`/`sms:`/`mailto:`); Twilio/Gmail integration later (§13).

**Done =** clicking a BMR lead opens a working 3-panel command center: per-stage form==checklist with live completion, owner + author-stamped notes/activity, quick actions, schedulable site visit, the scope checklist flowing into the estimate — all editable/deletable (§2.6), fresh UI, matching Jacob's hi-fi. Isaac can run his whole sales process here instead of the old BMR app.

Pace: tight review on migrations/RLS, faster on UI.

---

## Definition of done (every phase)

- TypeScript builds clean; `npm run dev` runs without console errors.
- RLS verified: a user in org A cannot read org B's rows (write an explicit check).
- Matches the locked hi-fi visually.
- Behavior confirmed with the user before anything ambiguous ships.
- **Full user CRUD (SCOPE §2.6):** every entity the phase creates can be **edited and deleted/archived/voided by the user in the UI** — not just created and advanced. If the user could make it, the user can fix or remove it, without a developer or SQL. No create-only happy paths.
