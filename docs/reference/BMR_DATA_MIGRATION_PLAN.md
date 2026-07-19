# BMR Sales Pipeline → StructTech OS — Data Migration Plan

**Goal:** bring Isaac's real book of business (leads + notes + stages + activity + milestones) out of the
old BMR Sales Pipeline app and into StructTech OS as BMR-org `deals`, preserving history and dates.
**Written 7/19/26.**

---

## 1. Where the data actually is

- The `leads` / `lead_notes` / `lead_activity` / `lead_appointments` cluster **inside the `structtech`
  project is an EMPTY SHELL** (0 rows, confirmed 7/19). The old schema was scaffolded here (the
  `structtech-pipeline` fork) but never populated. **It is not the source.**
- The real data lives in the **old BMR app's own Supabase project**, which is *not* in this Supabase
  account (only `structtech`, `jared-walker-platform`, `construction-pm-app` are visible). Export must
  come from there.
- **Silver lining:** that empty shell documents the old schema exactly, so the mapping below is built
  from real column definitions, not guesswork.

## 2. Source schema (old BMR)

**`leads`** — `id, first_name, last_name, name (NOT NULL), company_name, phone, cell_phone,
secondary_phone, email, street_address/city/state/zip, service_street_address/service_city/service_state/
service_zip, source (enum), referral_name, stage (enum), status (enum), value (numeric), owner_id,
claim_locked, lost_reason, intake_checklist (jsonb NOT NULL), site_visit_complete_at, scope_ordered_at,
quote_presented_at, proposal_sent_at, last_contacted_at, created_at, updated_at, closed_at`

**`lead_notes`** — `id, lead_id, author_id, content, created_at`
**`lead_activity`** — `id, lead_id, actor_id, action (enum), from_value, to_value, created_at`

**Enums:** `lead_source` = webhook | manual | referral · `lead_stage` = lead_captured | qualified |
proposal_sent | negotiating | closed · `lead_status` = active | closed_won | closed_lost

## 3. Target (BMR live, org `9d32b5a9-e11e-401b-8fa7-969065b004ce`)

Kanban stages: `new_lead | qualified | site_visit | estimate_presented | won | lost`
Command stages (**derived from data, not stored**): `new_lead | site_visit | scope | quote | negotiating | closed`

> Because command stage is *derived* from the milestone timestamps, migrating those timestamps
> automatically lands each lead on the correct command tab. No explicit command-stage mapping needed.

---

## 4. Field mapping — `leads` → `deals`

| Old | New | Notes |
|---|---|---|
| `name` | `contact_name` | both NOT NULL — direct |
| `first_name` / `last_name` | `first_name` / `last_name` | direct |
| `company_name` | `company` | direct |
| `cell_phone` | `phone` | `phone = coalesce(cell_phone, phone)` |
| `phone` (old landline) | `secondary_phone` | only if `secondary_phone` empty — **decide** |
| `secondary_phone` | `secondary_phone` | direct (wins over old `phone`) |
| `email` | `email` | direct |
| `service_street_address/city/state/zip` | `service_address_street/city/state/zip` | clean 1:1 |
| `street_address/city/state/zip` | `billing_address` | **ours is a single TEXT field** → `concat_ws(', ', …)` |
| `source` (enum) | `source` (text) | cast to text |
| `referral_name` | `referral_name` | direct |
| `value` (numeric) | `value` (**integer**) | `round()` — type differs |
| `lost_reason` | `lost_reason` | direct |
| `owner_id` | `owner_id` | **REMAP** old user id → new `profiles.id` (see §6) |
| `intake_checklist` (jsonb) | `intake_checklist` (jsonb) | passthrough — **verify key alignment** (§7) |
| `site_visit_complete_at` | `site_survey_complete_at` | renamed |
| `scope_ordered_at` | `roof_scope_ordered_at` | renamed |
| `quote_presented_at` | `quote_presented_at` | direct |
| `created_at` / `updated_at` / `closed_at` | same | **preserve — do not default to now()** (pipeline aging) |
| `stage` + `status` | `stage` | see §5 |
| `proposal_sent_at`, `last_contacted_at`, `claim_locked` | — | no target; park in `intake_checklist` or drop — **decide** |
| — | `org_id` | = BMR org (constant) |
| — | `lead_type` | **no source equivalent** → null; Isaac fills in (or infer from `company_name`) |

## 5. Stage mapping — `stage` + `status` → kanban `stage`

Status wins over stage for closed records:

| Condition | New stage |
|---|---|
| `status = 'closed_won'` | `won` |
| `status = 'closed_lost'` | `lost` |
| active + `lead_captured` | `new_lead` |
| active + `qualified` | `qualified` |
| active + `proposal_sent` | `estimate_presented` |
| active + `negotiating` | `estimate_presented` ⚠️ **decide** — see below |
| active + `closed` (no closed status) | edge case — resolve by `closed_at` |

⚠️ **Decision:** the old app had a **negotiating** stage; BMR's new *kanban* doesn't (only the command
tabs do). Either (a) add a `negotiating` kanban stage to BMR's config (trivial config edit — and a nice
demo of configurability), or (b) fold it into `estimate_presented`. **(a) is recommended** — it preserves
Isaac's real working stages rather than flattening them.

Note: the new kanban has a **`site_visit`** stage the old enum lacks. Optional refinement: leads with
`site_visit_complete_at` set (but not closed) could land in `site_visit` rather than `qualified`.

## 6. Notes / activity / identity mapping

- **`lead_notes` → `deal_notes`:** `lead_id`→`deal_id` (via id map), `content`, **`created_at` preserved**,
  `author_id`→`created_by` (remapped), `org_id` = BMR.
- **`lead_activity` → `deal_activity`:** `lead_id`→`deal_id`, `action` (enum→text; map old vocabulary to
  ours where it overlaps, else keep the raw label), `from_value`/`to_value`, `created_at`, `actor_id`
  (remapped), `org_id` = BMR.
- **Identity remap:** export the old app's users/profiles table too. Build `old_user_id → new profiles.id`.
  If the old app had only Isaac, everything maps to him. Unknown/departed users → **NULL** (our columns are
  nullable and the UI already falls back gracefully for null actors — verified in C2).

## 7. `intake_checklist` key alignment (the one real unknown)

Our new checklist config was **modeled on BMR's**, so the JSON keys should largely match — but this must
be **verified against a real export sample**, not assumed. Steps: export 5 representative leads, diff their
`intake_checklist` keys against BMR's seeded `lead_control_center.fields` paths, and write a key-rename map
for any drift. Mis-mapped keys don't error — they just silently fail to display, which is the dangerous
failure mode.

---

## 8. Execution approach (staging-then-transform, idempotent)

1. **Export** from the old project — 4 tables: `leads`, `lead_notes`, `lead_activity`, users/profiles.
   Easiest reliable route: in the old project's SQL editor run `select json_agg(t) from public.leads t;`
   (repeat per table) and save each as JSON; or `pg_dump --data-only -t public.leads …`; or CSV export.
   Drop the files in `docs/migration/bmr-export/` (gitignore if they contain PII).
2. **Land raw** into staging tables in `structtech` (`migration_bmr_leads_raw`, etc.) — **untransformed**.
   Makes the transform re-runnable and auditable without re-exporting.
3. **Provenance + idempotency:** a `migration_bmr_id_map(entity, old_id, new_id)` table (or a `legacy_id`
   column). Every transform is `on conflict do nothing` keyed on the old id, so re-running never duplicates
   and you can trace any new row back to its source — and reverse it.
4. **Transform** raw → `deals` / `deal_notes` / `deal_activity` per §4–6, stamping `org_id`, preserving
   `created_at`. Inserts bypass the definer RPCs (admin migration) — fine, and `deal_stage_side_effects`
   is a BEFORE **UPDATE** trigger so inserts won't fire spurious activity.
5. **Dry run inside a transaction** → print counts + a sample diff → `rollback`. Review before committing.
6. **Load for real**, then verify (§9).

## 9. Verification checklist

- Row counts match source (leads / notes / activity), minus anything deliberately excluded.
- Spot-check **5 leads field-by-field** against the old app UI — including one closed-won, one closed-lost,
  one mid-pipeline with notes.
- Notes attach to the right leads, in the right order, with right authors + original dates.
- Kanban distribution looks sane (no giant pile in one column = a stage-mapping bug).
- Command tabs land correctly (driven by the migrated milestone timestamps).
- `intake_checklist` renders in the Lead Control Center (not silently blank) for a sampled lead.
- **Isaac spot-checks leads he knows** — the real acceptance test.

## 10. Open decisions (Jacob)

1. **Scope:** migrate everything, or exclude test rows / closed-lost older than N months?
2. **`negotiating` stage:** add it to BMR's kanban config (recommended) or fold into `estimate_presented`?
3. **Owners:** was the old app multi-user? Map each old user to a new profile (needs accounts) or assign
   all to Isaac?
4. **Phones:** old has both `phone` and `cell_phone` — confirm `cell_phone` is the primary.
5. **Dropped fields:** `proposal_sent_at`, `last_contacted_at`, `claim_locked` — park in the checklist JSON
   or drop?
6. **`lead_type`** (Homeowner / GC / Property Mgmt / Commercial) doesn't exist in the old data — leave null
   for Isaac to fill, or infer (company_name present → contractor)?

## 11. Timing note

This does **not** have to block Monday's walkthrough. If the export happens this weekend, the load can be
done before Monday; otherwise walk Isaac through on current data and load his book immediately after. The
gating item is the **export** — everything downstream is ours.
