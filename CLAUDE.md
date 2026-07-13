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
- **Field & estimating (mobile):** outdoor high-contrast mode (black bg) is the **default** for the crew role; **≥56dp touch targets**; single thumb column; never show pipeline or dollar figures in the `field` role.
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

## CURRENT PHASE — Week 3: BMR operational system (DEADLINE-DRIVEN)

**Weeks 1 & 2 COMPLETE and live** — foundation/auth/multi-tenancy/shell (W1); pipeline for both tenants + BMR live estimating lead→estimate→sign→PDF (W2).

**Why this phase exists / the bar:** BMR (the one signed client, Isaac) must have a **functional system he can actually run real roofing jobs in by end of week**, or the client is at risk. Goal is *usable*, not polished. Cut scope toward "Isaac can operate his post-sale job flow," defer everything else to `docs/BACKLOG.md`.

**Priority order (build in this order; ship what's functional):**
1. **Coordination (`contractor`/BMR)** — the post-sale workflow Isaac needs the day a job signs: signed estimate → **work order** → **material list** → **schedule** (crew + dates). This is #1 because it's the immediate operational gap after Week 2's sign step. Wireframes 1d/2d. Homeowner sign-off gate and material-ready-by-gates-scheduling are nice-to-have — include if cheap, defer if they cost the deadline.
2. **Field (`contractor`/BMR, mobile)** — crew execution: **Today** job list → **daily check-in** (photos, hours, materials, blockers) → **visual production packet** (job details, photos, callouts). Field-first: outdoor high-contrast, ≥56dp, single thumb column. Wireframe 3a. The full annotated trim-map layer is deferrable; a functional packet (work-order detail + photos + text callouts) is the MVP.
3. **Delivery / portal — DEFER (slip candidate).** This is StructTech-facing engagement tracking, NOT part of BMR running roofing jobs. Do NOT build it this phase unless 1 and 2 are done with time to spare. Moves to BACKLOG otherwise.

**Data model (extend, org-scoped, RLS via `my_org_ids()`, RPCs per patterns):** coordination — `work_orders`, `material_items`, `schedule_blocks`; field — `check_ins`, `production_packets`. New tables (no legacy data) → org_id NOT NULL, clean `my_org_ids()` RLS, no `is_staff()` layering.

**Done (deadline definition) =** in BMR: a signed estimate becomes a work order → materials + a schedule; the crew opens a Today list, submits a daily check-in, and views a production packet for a job. All on live data, usable on a phone.

**Pace note:** aggressive deadline — keep tight review on migrations/RLS (the risky part), move faster on UI. Defer polish and delivery/portal before cutting into coordination or field. Consult `docs/BACKLOG.md` for what's already deferred.

---

## Definition of done (every phase)

- TypeScript builds clean; `npm run dev` runs without console errors.
- RLS verified: a user in org A cannot read org B's rows (write an explicit check).
- Matches the locked hi-fi visually.
- Behavior confirmed with the user before anything ambiguous ships.
- **Full user CRUD (SCOPE §2.6):** every entity the phase creates can be **edited and deleted/archived/voided by the user in the UI** — not just created and advanced. If the user could make it, the user can fix or remove it, without a developer or SQL. No create-only happy paths.
