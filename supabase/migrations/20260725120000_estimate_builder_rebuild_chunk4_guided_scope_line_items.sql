-- StructTech OS — Estimate builder rebuild, Chunk 4: Guided mode scope-key line items
--
-- NOT APPLIED. Author-only migration file — ask before applying, same as
-- every other migration in this repo.
--
-- Guided mode generates estimate line items from the site-visit scope
-- checklist (deals.intake_checklist.site_visit_scope.*). Three things this
-- migration adds, all reviewed before this file was written:
--
--   1. estimate_line_items.scope_key — tags a line item as "generated from
--      this scope-checklist key," null for anything manual/free-typed.
--      This is what makes regeneration idempotent instead of duplicating
--      every time Guided mode re-runs.
--   2. A partial unique index on (estimate_id, scope_key) WHERE scope_key
--      IS NOT NULL — enforced by the database, not just app-logic
--      discipline. "Idempotent upsert" that's only idempotent because the
--      app is careful isn't; this makes the upsert a real ON CONFLICT.
--   3. upsert_estimate_scope_line_items(p_estimate_id, p_items jsonb) — the
--      RPC the ON CONFLICT actually lives in.
--
-- ARCHITECTURAL CHANGE from what I originally proposed (caught in review):
-- the scope-key -> line-item mapping is TENANT CONFIG
-- (tenant_modules.config where module_key='estimating', key
-- "scope_line_items"), not a TypeScript lookup table. Hardcoding BMR's
-- interpretation of its own scope checklist would be exactly the kind of
-- per-tenant hardcoding SCOPE.md §2.7/§12F rules out — and this mapping
-- doubles as the pricing matrix minus the rate, so config now means "the
-- matrix later is add unit_price per entry," not a rewrite. This migration
-- only adds the schema; the TS parser that reads scope_line_items
-- generically (mirroring command-center.ts's parseLeadControlCenterConfig
-- style) and the RPC caller are the next step, after this is approved.
--
-- Config shape (seeded for BMR below as the DEFAULT, not hardcoded
-- behavior — any tenant can edit their own tenant_modules.config row):
--   "scope_line_items": {
--     "roof_area_sqft":         { "generates": true,  "description": "Roof — tear off and replace", "unit": "sq", "factor": 0.01 },
--     "gutters_lf":             { "generates": true,  "description": "Gutters",        "unit": "lf" },
--     "fascia_lf":              { "generates": true,  "description": "Fascia",         "unit": "lf" },
--     "soffit_lf":              { "generates": true,  "description": "Soffit",         "unit": "lf" },
--     "pipe_boots":             { "generates": true,  "description": "Pipe boots",     "unit": "ea" },
--     "roof_vents":             { "generates": true,  "description": "Roof vents",     "unit": "ea" },
--     "osb_replacement_sheets": { "generates": true,  "description": "OSB replacement","unit": "sheet" },
--     "facets":                 { "generates": false },
--     "pitch_slope_notes":      { "generates": false },
--     "roof_color":             { "generates": false },
--     "roof_profile_style":     { "generates": false },
--     "gutter_color":           { "generates": false },
--     "ice_water_shield":       { "generates": false },
--     "drip_edge":              { "generates": false },
--     "scope_notes":            { "generates": false }
--   }
-- generates:false entries are skipped entirely by the (not-yet-written) TS
-- generator — whether they should ever append to notes_terms instead is
-- explicitly deferred, per instruction. ice_water_shield/drip_edge ARE
-- billable materials in real roofing practice, not just specs — defaulted
-- to generates:false here anyway because they're free-text fields today
-- (no stable numeric quantity to generate FROM), not because they're
-- unimportant. A tenant wanting them billable would need to change their
-- checklist field to a number type first — their config decision, not a
-- default we're making for them.
--
-- CHANGE 1 (100x quantity bug, caught in review): roof_area_sqft's raw
-- value is SQUARE FEET; "sq" as a roofing unit means squares (100 sq ft).
-- Without a conversion, a 3,200 sq ft roof would generate line quantity
-- 3200 with unit "sq" — 100x too high, landing on the single biggest line
-- of the quote. Added optional numeric `factor` (default 1 when absent):
-- quantity = raw_value * factor. roof_area_sqft needs factor 0.01
-- (3200 * 0.01 = 32 sq, correct). Audited every other generates:true entry
-- for the same class of mismatch: gutters_lf/fascia_lf/soffit_lf are
-- already linear feet in both the checklist and the "lf" billing unit
-- (1:1, factor omitted = default 1); pipe_boots/roof_vents/
-- osb_replacement_sheets are already raw counts matching "ea"/"sheet"
-- (1:1, same). Only roof_area_sqft has a unit mismatch.
--
-- CHANGE 4 (cross-module coupling, noted not solved): scope_line_items
-- (this module's config, module_key='estimating') references scope keys
-- OWNED by the site_visit_scope checklist (module_key='crm',
-- lead_control_center config, command-center.ts). Renaming or removing a
-- checklist field key in the crm config silently orphans its
-- scope_line_items entry — nothing here detects that directly. The
-- (not-yet-written) TS generator's "unmapped key" reporting (CHANGE 2 —
-- a filled checklist field with NO scope_line_items entry gets surfaced to
-- the operator, never silently skipped) is the practical safeguard: it
-- catches the dangerous direction (real scope data quietly not becoming a
-- line item) every time the generator runs. A config entry orphaned by a
-- checklist rename, by contrast, just never matches anything and stays
-- inert — annoying stale config, not a silent-data-loss risk — so no
-- separate orphan-detection pass was built for that direction.
--
-- Description-clobber question (raised in review): does a re-run overwrite
-- a hand-edited description? No — description is set ONLY on the initial
-- INSERT (from config at that moment); the ON CONFLICT branch below
-- updates quantity/unit only. This also sidesteps a harder problem — if a
-- tenant edits their scope_line_items config later, comparing "does the
-- current description still match the default" would be ambiguous (default
-- against OLD config or NEW config?). Never touching it after creation is
-- simpler and can't clobber a hand edit, full stop.
--
-- unit_price is likewise never touched by the upsert (insert-time default
-- 0 only) — no pricing matrix exists yet (docs/reference, SCOPE.md §12F:
-- no target table for products/pricing_config), so Guided has no price
-- opinion to assert, ever, on insert or refresh.

-- ============================================================================
-- 1. scope_key column
-- ============================================================================
alter table public.estimate_line_items
  add column scope_key text;

comment on column public.estimate_line_items.scope_key is
  'Tags a line item as generated by Guided mode from this site-visit-scope checklist key. Null for manual/free-typed lines. Never set by the UI directly — only upsert_estimate_scope_line_items() writes it.';

-- ============================================================================
-- 2. Partial unique index — the real idempotency guarantee
-- ============================================================================
create unique index estimate_line_items_estimate_scope_key_uidx
  on public.estimate_line_items (estimate_id, scope_key)
  where scope_key is not null;

-- ============================================================================
-- 3. upsert_estimate_scope_line_items — insert-or-refresh by scope_key
-- ============================================================================
create or replace function public.upsert_estimate_scope_line_items(
  p_estimate_id uuid,
  p_items jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_status text;
  v_next_sort int;
  v_item jsonb;
begin
  select org_id, status into v_org_id, v_status
  from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  if v_status in ('signed', 'void') then
    raise exception 'estimate % is locked (status: %) — line items can only change before signing', p_estimate_id, v_status;
  end if;

  select coalesce(max(sort_order) + 1, 0) into v_next_sort
  from public.estimate_line_items where estimate_id = p_estimate_id;

  -- p_items: jsonb array of {scope_key, description, quantity, unit} —
  -- built entirely in TS from tenant config + the deal's current scope
  -- checklist values. This function has no opinion on WHICH scope keys
  -- exist or what they mean; it only knows how to file one by scope_key.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    insert into public.estimate_line_items
      (org_id, estimate_id, scope_key, description, quantity, unit, unit_price, product_id, sort_order)
    values
      (v_org_id, p_estimate_id, v_item->>'scope_key', v_item->>'description',
       (v_item->>'quantity')::numeric, v_item->>'unit', 0, null, v_next_sort)
    on conflict (estimate_id, scope_key) where scope_key is not null
    do update set
      quantity = excluded.quantity,
      unit = excluded.unit,
      updated_at = now();
      -- description and unit_price deliberately absent from this SET list
      -- — see the header note. A line item this function already created
      -- keeps whatever description/price it has forever, only its
      -- quantity/unit stay mirrored to the live scope value.

    v_next_sort := v_next_sort + 1;
  end loop;
end;
$$;

-- ============================================================================
-- 4. Seed BMR's default scope_line_items config — DEFAULT DATA, not code.
-- Merged (||) into the existing (currently empty {}) config, never
-- overwrites other keys (branding, etc.) that may exist on this row.
-- ============================================================================
update public.tenant_modules
set config = config || jsonb_build_object(
  'scope_line_items', jsonb_build_object(
    'roof_area_sqft', jsonb_build_object('generates', true, 'description', 'Roof — tear off and replace', 'unit', 'sq', 'factor', 0.01),
    'gutters_lf', jsonb_build_object('generates', true, 'description', 'Gutters', 'unit', 'lf'),
    'fascia_lf', jsonb_build_object('generates', true, 'description', 'Fascia', 'unit', 'lf'),
    'soffit_lf', jsonb_build_object('generates', true, 'description', 'Soffit', 'unit', 'lf'),
    'pipe_boots', jsonb_build_object('generates', true, 'description', 'Pipe boots', 'unit', 'ea'),
    'roof_vents', jsonb_build_object('generates', true, 'description', 'Roof vents', 'unit', 'ea'),
    'osb_replacement_sheets', jsonb_build_object('generates', true, 'description', 'OSB replacement', 'unit', 'sheet'),
    'facets', jsonb_build_object('generates', false),
    'pitch_slope_notes', jsonb_build_object('generates', false),
    'roof_color', jsonb_build_object('generates', false),
    'roof_profile_style', jsonb_build_object('generates', false),
    'gutter_color', jsonb_build_object('generates', false),
    'ice_water_shield', jsonb_build_object('generates', false),
    'drip_edge', jsonb_build_object('generates', false),
    'scope_notes', jsonb_build_object('generates', false)
  )
)
where module_key = 'estimating'
  and org_id = '9d32b5a9-e11e-401b-8fa7-969065b004ce'; -- Brothers Metal Roofing, confirmed live this session
