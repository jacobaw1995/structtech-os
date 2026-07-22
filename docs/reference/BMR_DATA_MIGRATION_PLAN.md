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

## 2a. ACTUAL source inventory (confirmed live 7/19 — supersedes assumptions)

Row counts from the real old-BMR database:

| Table | Rows | Disposition |
|---|---|---|
| `leads` | **188** | **MIGRATE** — the book of business |
| `lead_notes` | **171** | **MIGRATE** |
| `lead_activity` | **587** | **MIGRATE** (chunk the export if it truncates) |
| `profiles` | **2** | **MIGRATE as identity map** — old app had TWO users (see §6) |
| `products` | 11 | **EXPORT + ARCHIVE** — BMR's product catalog; the seed for the future pricing matrix (§12F) / catalogs (§12B). No target table exists yet — do NOT migrate, but do NOT lose. |
| `pricing_config` | 2 | **EXPORT + ARCHIVE** — same reason; this is how BMR actually prices |
| `estimate_document_templates` | 1 | **EXPORT + ARCHIVE** — seed for tenant doc templates (§12E) |
| `lead_appointments` | 5 | **PARK** — Stage 6 (scheduling) is on hold and no target table exists; only 5 rows, re-enterable. Export for safekeeping. |
| `estimates` / `estimate_line_items` / `estimate_activity` / `rep_estimate_settings` | 1 / 5 / 2 / 2 | **ARCHIVE ONLY** — effectively test data (a single estimate). Not worth migrating; BMR's real estimating starts fresh in StructTech OS. |
| `lead_import_batches` | 1 | **SKIP** — import metadata |
| `brief_item_overrides`, `estimate_signing_invites`, `project_handoffs` | 0 | **SKIP** — empty |

**Key takeaway:** the migration proper is 4 tables (leads / notes / activity / profiles). `products` +
`pricing_config` are the sleeper value — they're the real-world seed data for the pricing-matrix tool,
so they get exported and stored even though nothing consumes them yet.

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
- **Identity remap — RESOLVED 7/19. Map by EMAIL, never by id** (different Supabase projects ⇒ different
  auth user ids; the old ids do NOT carry over):

  | Old (BMR app) | Email | New (StructTech OS) |
  |---|---|---|
  | `f1828102-3185-494e-988c-78d02256bc78` | isaac@brothersmetalroofing.com | `d63871d2-cb54-44b2-bac4-502d22a79d96` (Isaac Smith) |
  | `d1b5a72a-3bd4-468b-a2de-c5261e1e1bf5` | jacob@structtek.com | `09a25143-e069-401b-a49d-a6879fe43d7c` (Jacob Walker) |

  Both old users exist in StructTech OS ⇒ **100% attribution preserved** across 171 notes + 587 activity
  rows. No NULL-actor fallback needed. Both were `manager` in the old app, consistent with Isaac's
  `profiles.role='manager'` set in Track B2. Any id not in this map → NULL (shouldn't occur).

## 4b. ⚠️ CORRECTED FIELD MAP — audited against the REAL export (7/19). SUPERSEDES §2/§4.

**§2/§4 were derived from the empty shell schema in the `structtech` project. The real export has
DRIFTED from it.** Auditing every key in `leads.json` against the transform found dropped fields and
two milestone keys that don't exist. Corrections:

### (a) Milestone timestamps — the shell renames were WRONG (silent data loss)
The export already uses **our** names. No rename needed; the transform was reading nonexistent keys:

| Transform reads (WRONG) | Actual export key | Populated |
|---|---|---|
| `site_visit_complete_at` ❌ does not exist | **`site_survey_complete_at`** → same name in `deals` | 2 |
| `scope_ordered_at` ❌ does not exist | **`roof_scope_ordered_at`** → same name in `deals` | 0 |
| `quote_presented_at` ✅ correct | `quote_presented_at` | 2 |

Left unfixed, milestones vanish → command stages never derive. Also present: `inspection_scheduled_at` (0).

### (b) Address blocks — "street_address = billing" was WRONG
Measured across 188 rows: `street_address` == `service_street_address` **176×**; `address` matches both
**176×**; `billing_*` == service only **161×** (so billing genuinely differs on ~15 leads).

- **Service** = `service_street_address/service_city/service_state/service_zip` → `service_address_*` ✅ (already right)
- **Billing** = **`billing_street_address/billing_city/billing_state/billing_zip`** → `billing_address` (concat).
  The transform currently concats `street_address/city/state/zip`, which is a **duplicate of the service
  address** — that would put the wrong value in billing on the ~15 leads where they differ.
- **`address`, `street_address/city/state/zip`** = redundant duplicates of the service address → **drop**.

### (c) Fields we have columns for but never mapped (real data being thrown away)

| Export field | Populated | → `deals` column | Notes |
|---|---|---|---|
| `homeowner_or_contractor` | 180 | `lead_type` | 'Homeowner'→`homeowner`, 'Contractor'→`contractor`, null→null. **Reverses decision 6** — that decision rejected *inferring* from `company_name`; this is a direct human-entered source field. Verify against the 4-value CHECK constraint. |
| `existing_roof_type` | 165 | `existing_roof_type` (**text[]**) | string → array; see (d) |
| `roof_type_requested` | 177 | `roof_type_requested` (**text[]**) | string → array; comma-separated values split; see (d) |
| `remodel_or_new_construction` | 176 | `remodel_or_new_construction` | 'Remodel' 174 / 'New Construction' 2. Field is a `select` with no option list ⇒ pass through as-is. |

**Ignore:** `closed_won_project_created` (all false), `import_batch_id` (import metadata), `claim_locked`.

### (d) Roof types — normalize vocabularies, and EXTEND the tenant option list
Values are **strings in two vocabularies** (Title Case + snake_case) and must become `text[]`.
Our seeded options: Asphalt Shingle · Architectural Shingle · Metal - Standing Seam · Metal - Corrugated ·
Metal - Stone Coated · Tile · Flat / Membrane · Wood Shake · Slate · Other.

**COMPLETE map — all 15 distinct values across both fields (nothing falls through to `Other`):**

| Old value | Count | → New value |
|---|---|---|
| `Standing Seam` | 35 | `Metal - Standing Seam` |
| `metal_standing_seam` | 5 | `Metal - Standing Seam` |
| `metal_exposed_fastener` | 5 | `Metal - Corrugated` (exposed-fastener = corrugated/ag-panel family) |
| `asphalt_shingle` | 6 | `Asphalt Shingle` |
| `Cedar Shake` | 2 | `Wood Shake` |
| `wood_shake` | 1 | `Wood Shake` |
| `Slate` | 1 | `Slate` |
| `Flat` | 2 | `Flat / Membrane` |
| `tpo_membrane` | 1 | `Flat / Membrane` |
| `rubber_epdm` | 1 | `Flat / Membrane` |
| `PVC` | 1 | `Flat / Membrane` |
| **`Shingle`** | **116** | **`Shingle` — ADD to config** |
| **`Metal`** | **165** | **`Metal` — ADD to config** |
| **`Copper`** | **3** | **`Copper` — ADD to config** |
| **`Asbestos Shingle`** | **1** | **`Asbestos Shingle` — ADD to config** |

Comma-joined values (e.g. `metal_exposed_fastener,metal_standing_seam`) split into 2 array entries.
TPO / EPDM / PVC → `Flat / Membrane` is definitional (all low-slope membrane systems), not a guess.

⚠️ **Add 4 options to BOTH roof-type lists in BMR's config: `Shingle`, `Metal`, `Copper`,
`Asbestos Shingle`.** Rationale:
- `Shingle` (116) and `Metal` (165) are **not ambiguous data — they're Isaac's actual vocabulary**,
  meaning "type known, profile not yet specified." Forcing them to `Asphalt Shingle` /
  `Metal - Standing Seam` fabricates precision he never recorded; dumping them in `Other` erases 281
  of 342 values. Keeping them lets him refine per-lead as he works each one.
- **`Asbestos Shingle` must NOT become `Other`.** It's only 1 lead, but asbestos is a hazmat/abatement
  flag with real safety, cost, and liability consequences on a tear-off. Burying it in `Other` hides a
  job-safety fact. This is the single most consequential value in the list.

Result: **zero values fabricated, zero lost, zero `Other`.** Final list = the seeded 10 + these 4.

⚠️ **Add `Metal` and `Copper` to BMR's roof-type option lists** (both fields) rather than force-fitting.
`Metal` alone is **165 values** — BMR is a metal roofer and mostly didn't record a specific profile.
Guessing a profile would fabricate data; `Other` would erase it. Extending the tenant's own config is the
same call we made for the `negotiating` stage. Isaac refines to a specific profile as he works each lead.

### (e) Lesson
`source` is also drifted (shell said enum `webhook|manual|referral`; export has `Phone Call` 170,
`Referral` 9, `Google Search` 3, …). Harmless — our column is free text. **Rule: map from the EXPORT,
never from the shell schema.**

## 7b. CONFIRMED FROM THE ACTUAL EXPORT (7/19) — supersedes §7's "unknown"

Export validated: 188 / 171 / 587 / 2 rows, all valid JSON, plain arrays (no `json_agg` wrapper —
Jacob copied the expanded cell), no truncation.

### (a) Checklist key drift is REAL — use this rename map
Only **5 of 188** leads have any checklist data (183 are empty), so blast radius is small — but without
this map those 5 render blank. Old container `site_visit` ≠ our `site_visit_scope`:

| Old key | New path |
|---|---|
| `main_issue` | `main_issue` ✅ unchanged |
| `general_notes` | `general_notes` ✅ unchanged |
| `estimate_inputs.pitch_estimate` | `estimate_inputs.pitch` ⚠️ rename |
| `site_visit.*` | `site_visit_scope.*` ⚠️ **container rename (all keys)** |
| `site_visit.roof_sqft` | `site_visit_scope.roof_area_sqft` ⚠️ |
| `site_visit.pitch_notes` | `site_visit_scope.pitch_slope_notes` ⚠️ |
| `site_visit.osb_sheets` | `site_visit_scope.osb_replacement_sheets` ⚠️ |
| `site_visit.roof_style` | `site_visit_scope.roof_profile_style` ⚠️ |
| `facets`, `fascia_lf`, `soffit_lf`, `gutters_lf`, `pipe_boots`, `roof_color`, `roof_vents`, `scope_notes`, `gutter_color`, `ice_water_shield`, `drip_edge` | same name under `site_visit_scope` ✅ |

Any old key not in this map → **drop it and log it** (don't blind-copy unknown keys into the checklist).

### (b) Ownership: REASSIGN to Isaac (do NOT map faithfully)
Old owners: Jacob **159**, Isaac **25**, null **4** — because Jacob ran the CSV import, not because he
works the leads. **Set `owner_id` = Isaac (`d63871d2-…`) on all 188.** Rationale: `owner_id` is an
*operational* field (who works it now), not history. Faithful mapping would leave Isaac with 159 leads
owned by "Jacob Walker", breaking his my-leads view and edit-by-ownership. **History stays faithful
separately** — note authors and activity actors keep their real old identities (§6).

### (c) Activity: migrate all 587, but resolve ids → names
Volume is fine (median **3** events/lead, max 8 — no Revision History flooding). Action map:

| Old action (count) | New action |
|---|---|
| `created` (188) | `created` |
| `reassigned` (329) | `owner_assigned` |
| `stage_changed` (23) | `stage_changed` |
| `status_changed` (25) | `stage_changed` |
| `edited` (17) | `details_updated` |
| `value_set` (5) | `details_updated` |

⚠️ Old `reassigned` rows carry **raw UUIDs** in `from_value`/`to_value` (e.g. `unclaimed` →
`f1828102-…`). Our C1 convention writes **names**. Resolve via the §6 identity map:
`unclaimed`/null → `'Unassigned'`, old id → full name. Otherwise the UI shows raw UUIDs.

### (d) Expected post-migration distribution (verify against this)
Stage × status maps to: **`new_lead` 157 · `lost` 24 · `negotiating` 3 · `qualified` 3 · `won` 1** = 188.
The board will look heavily weighted to `new_lead` — that's **correct**, not a mapping bug: 177 of 188
leads were bulk-imported 2026-06-26 and never worked. Pipeline history is ~3 weeks (2026-06-23 → 07-09).
Note the `negotiating` decision affects only **3** leads.

## 7. `intake_checklist` key alignment (the one real unknown — now RESOLVED, see §7b)

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
3. **Owners — CONFIRMED multi-user: old `profiles` has 2 rows.** Identify both before transforming.
   Best case (likely) they're Isaac + Jacob, who *both* already have profiles in StructTech OS → 1:1 map,
   **zero attribution loss** across 171 notes and 587 activity rows. If user #2 is a departed rep with no
   new account, their `created_by`/`actor_id` would go NULL (UI degrades gracefully, verified in C2) and
   the name is lost — in that case either create a placeholder profile for historical attribution or
   accept the loss. **Decide before the transform, not after.**
4. **Phones:** old has both `phone` and `cell_phone` — confirm `cell_phone` is the primary.
5. **Dropped fields:** `proposal_sent_at`, `last_contacted_at`, `claim_locked` — park in the checklist JSON
   or drop?
6. **`lead_type`** (Homeowner / GC / Property Mgmt / Commercial) doesn't exist in the old data — leave null
   for Isaac to fill, or infer (company_name present → contractor)?

## 11. Timing note

This does **not** have to block Monday's walkthrough. If the export happens this weekend, the load can be
done before Monday; otherwise walk Isaac through on current data and load his book immediately after. The
gating item is the **export** — everything downstream is ours.
