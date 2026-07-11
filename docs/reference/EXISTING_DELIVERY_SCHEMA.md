# StructTech OS — Buildout Schedule Feature (Spec v1)

**Session:** Plan + schema design (7/6/26). No app code this session — this doc is the alignment artifact.
**Owner:** Jacob · **Controller:** pm-app-controller skill

---

## What this is

The **buildout / delivery schedule**: the layer that turns a static client roadmap into a
living timeline the client watches in their portal. It answers the questions the roadmap
alone can't — *which level are we on, what's happening now, and when does each piece land.*

It is the bridge between **sold** (`closed_won`) and **delivered**.

## Where it fits in the lifecycle

Wired today (sales side):
```
Scan (audit_leads) → Roadmap auto-gen (client_roadmaps + roadmap_playbook)
  → Deal pipeline (deals) → Present Mode → closed_won
```

The gap this fills (delivery side):
```
closed_won → Engagement starts → Schedule materialized (each level gets a target window)
  → StructTech works levels, ticks milestones + logs check-ins
  → Client portal shows live Gantt + current status
  → PROVE hit → level complete → next level → Handoff → engagement complete
```

**Cross-feature payoffs:**
- Present Mode "next-steps / start date" slide pulls from the schedule.
- `org_invoices` can later bill **per level** as each completes.
- Client portal becomes a living document instead of a read-only list.

---

## Decisions locked (7/6/26)

1. **Dates the client sees:** level bars display as **"week of"** target windows. **Client
   check-ins carry hard calendar dates.** Real internal actual-dates tracked but not
   necessarily surfaced.
2. **View:** a **Gantt** in the client portal. Convention: **bars = levels** (sequential
   order-of-ops), **milestones + check-ins = diamonds** on the bars. No per-milestone bars —
   keeps it visual, not overwhelming.
3. **Data model:** **normalize** the roadmap out of JSONB into real rows so each level /
   milestone can carry dates + status and be queried. JSONB stays as the generated draft;
   materialize to rows at `closed_won`.

---

## Schema — LIVE ✅ (verified in `structtech` DB 7/6/26)

All four tables exist and are seeded (2 engagements, 6 levels, 32 milestones, 1 check-in).
RLS enabled on all. `org_id` is denormalized onto every engagement_* table so RLS scopes by
org without walking the FK chain. Inserts / JSONB→rows materialization via
**security-definer RPCs**, per OS patterns.

```
engagements
  id                uuid pk
  deal_id           uuid → deals          UNIQUE  (one engagement per closed-won deal)
  roadmap_id        uuid → client_roadmaps
  org_id            uuid → organizations
  start_date        date
  target_end_date   date
  status            text  (active | paused | complete)
  created_at, updated_at  timestamptz

engagement_levels                    -- normalized from roadmap JSONB
  id                uuid pk
  engagement_id     uuid → engagements
  org_id            uuid → organizations
  level_no          int
  title             text
  why               text
  area              text            -- maps to scan focus area (lead response, etc.)
  sort_order        int
  depends_on_level_id uuid → engagement_levels   -- sequential gate (Level 2 after Level 1)
  planned_start     date            -- rendered "week of"
  planned_end       date            -- rendered "week of"
  actual_start      date            -- internal
  actual_end        date            -- internal
  status            text  (not_started | in_progress | blocked | complete)

engagement_milestones                -- deliverables / behaviors within a level
  id                uuid pk
  level_id          uuid → engagement_levels
  org_id            uuid → organizations
  owner             text  (jacob | client)
  body              text
  is_win_condition  bool
  sort_order        int
  status            text  (open | complete)
  completed_at      timestamptz
  -- checkable sub-items under the active level. NO own dates — dates live on check-ins.

engagement_checkins                  -- hard-dated meetings, distinct from milestones
  id                uuid pk
  engagement_id     uuid → engagements
  level_id          uuid → engagement_levels   -- nullable
  org_id            uuid → organizations
  title             text
  scheduled_at      timestamptz     -- HARD date/time
  status            text  (scheduled | done | missed | rescheduled)
  notes             text
  -- rendered as fixed-date diamonds; feeds "next check-in" chip in portal
```

**Design that fell out of the locked decisions:** milestones carry no dates of their own —
level bars supply the "week of" windows, check-ins supply the hard dates, cleanly separating
the two date types as decided. Level `status` / % complete derive from milestone completion
+ actuals, so the Gantt updates just by ticking milestones.

**Materialization RPC:** `create_engagement_from_roadmap(p_deal_id)` — fires at `closed_won`,
reads `client_roadmaps.levels` JSONB, writes `engagements` + `engagement_levels` +
`engagement_milestones` in one transaction. Check-ins added manually after.

---

## Portal rendering

- **Client Gantt:** lightweight read-only (SVG/CSS), not DHTMLX PRO — that's overkill for a
  view-only client timeline. Level bars (week-of windows), milestone diamonds, check-in
  diamonds (hard dates), current level highlighted, WIN CONDITION strip on the active level.
- **"Next check-in" chip:** nearest `engagement_checkins.scheduled_at`.
- **Admin side:** Jacob edits planned windows, ticks milestones, logs/moves check-ins.

---

## Out of scope this session / follow-ups

- **Security workstream (separate dedicated session):** granular RLS on all tables, migrate
  admin off the soft SHA-256 gate to Supabase Auth, enable RLS on `structtech_state`
  (currently disabled — exposed to anon key). Required before client-visible schedule data
  goes live.
- Per-level invoicing (`org_invoices` link) — later phase.
- Present Mode next-steps slide wiring — after schema ships.
- Migration SQL + admin/portal UI — next build session.
```
