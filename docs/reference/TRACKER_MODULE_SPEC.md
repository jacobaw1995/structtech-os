# Tracker Module — Spec (internal multi-project work tracker)

**Raised:** 7/19/26 · **Priority:** small v1 NOW (before/alongside Isaac's Mon go-live)
**Why now:** Isaac goes live Monday and will generate a burst of bug reports and feature requests in
week one that need same-week resolution. Without a home they land in texts, Zoom notes, and memory.
This replaces a throwaway Claude artifact (ephemeral, single-user, no persistence, no data links) with
a real, durable, org-scoped tool inside the OS.

## What it is
An **internal, multi-project work tracker**: tasks, bugs (reported by customers OR caught by Jacob),
feature requests, and ideas — a way to map and scope what has to get done to keep things rolling.
**Fluid: add a project at will.** Not limited to StructTech OS — e.g. the Windy Hill shop overhaul
needs its own scoped punch-list before it can go live.

## Placement
- **New module: `tracker`. Internal tenants only** (StructTech). Not licensed to clients in v1.
- Route: `/w/[orgId]/tracker`. Requires a `tenant_modules` row for the StructTech org.
- *Don't preclude:* a stripped version is plausibly licensable later to contractors as a punch-list /
  job-issue tracker. Keep the model generic enough that entitling a contractor tenant is a config act.

## Data model (2 tables — keep v1 tight)

**`tracker_projects`** — `id`, `org_id` (StructTech's; RLS scope), `name`, `description`,
`status` (active/paused/shipped/archived), `linked_org_id` (**nullable** FK → `organizations`, so a
BMR-specific project can attach to BMR; Windy Hill has none), `created_at`, `updated_at`,
`archived_at`, `created_by`.

**`tracker_items`** — `id`, `org_id`, `project_id` FK, `type` (task/bug/feature/idea), `title`,
`description`, `status`, `priority` (low/normal/high/urgent), `assignee_id` (nullable → profiles),
`position` (board ordering), `created_by`, `created_at`, `updated_at`, `resolved_at`, `archived_at`,
**plus the client-intake hooks (model now, surface later):**
- `source` (`internal` | `client`, default `internal`)
- `reported_by_org_id` (nullable → which client org reported it)
- `reported_by_profile_id` (nullable → which user reported it)

That trio is what lets a future in-app "Report an issue" button in a *client's* workspace insert
straight into this tracker with correct attribution — **no rework, just a new intake surface.**

## Config-driven definitions (NON-NEGOTIABLE — SCOPE §2.7 / §12F)
**Item `status` and `type` sets live in `tenant_modules.config` for the `tracker` module**, seeded
with a default set, read generically by the engine — the same pattern as CRM pipeline stages. Do NOT
hardcode them. Seeded default statuses: **`inbox` → `next` → `in_progress` → `blocked` → `done`**
(an `inbox` state matters: dump fast, triage later). Seeded default types: task / bug / feature / idea.

## Writes + security
- All writes via **security-definer RPCs** (platform pattern): `create_tracker_project`,
  `update_tracker_project`, `archive_tracker_project`, `create_tracker_item`, `update_tracker_item`,
  `archive_tracker_item` (+ delete where appropriate).
- RLS: `org_id in (select my_org_ids())`; module entitlement gates the route/nav.
- Actor stamping (`created_by` from `auth.uid()`→profile, NULL-safe) per the Stage 5 C2 pattern.
- **Full CRUD from the UI (§2.6)** — every project and item editable/archivable/deletable.

## UI (v1 — small, and mobile-capture matters most)
- **Project list + "New project"** (fluid creation, minimal fields).
- **Board per project**, columns = config statuses (reuse the existing kanban patterns from the CRM
  pipeline — do not build a new board engine).
- **Quick-add item: THE critical UX.** Title + type + priority in ~2 taps, from a phone. Jacob will be
  capturing Isaac's feedback live on a Zoom and right after. Friction here kills the tool.
- **Item detail:** edit all fields, change status/priority/assignee, archive/delete.
- **Cross-project "All open" view** — everything open across projects, filterable by type/priority.
- Mobile-first for capture; desktop for triage/scoping.

## Seed
Create projects: **StructTech OS**, **Windy Hill Shop**, **Brothers Metal Roofing** (linked_org_id =
BMR). Jacob adds more at will.

## Explicitly deferred (fast-follows, NOT v1)
- **Client intake surface** — the "Report an issue" button inside a client workspace + triage/notify.
  Data model supports it now (`source`/`reported_by_*`); the surface is later.
- **`docs/BACKLOG.md` sync** — decided: *"both, kept in sync"* — the tracker becomes the authoring UI
  and BACKLOG.md is **generated** from it, so Claude Code's session-start workflow is unchanged.
  v1.1 = a one-way **markdown export** (open items grouped by project/type → BACKLOG.md).
  **Until the export exists, avoid split-brain with this rule:** BACKLOG.md remains the authoritative
  build queue CC reads; the tracker holds the *new inflow* (Isaac's reports, Windy Hill, fresh ideas).
  When the export lands, the tracker becomes canonical and BACKLOG.md becomes generated output.
- **Append-only activity/history per item.** SCOPE's activity principle applies platform-wide, but for
  a personal internal tracker the audit value is low and it's cheap to add later (additive column +
  table, no rework). Flagged as a conscious v1 omission, not an oversight.
- Due dates, effort estimates, labels, linking items to deals/estimates, GitHub sync.

## Done =
Jacob can, on his phone during/after the Isaac Zoom, add a bug or feature request against a project in
seconds; triage it on a board later; edit/archive anything; and see everything open across all projects
in one view — with Windy Hill's pre-launch punch-list scoped in the same tool.
