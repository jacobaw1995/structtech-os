-- BMR roof-type fields: add 4 options Isaac actually uses (Shingle, Metal,
-- Copper, Asbestos Shingle) to both existing_roof_type and roof_type_requested.
--
-- NOT APPLIED. Author-only migration file — ask before applying to the live
-- Supabase project, same as every other migration in this repo.
--
-- Context: docs/reference/BMR_DATA_MIGRATION_PLAN.md §4b-d. The real BMR
-- export's roof-type values include `Shingle` (116x), `Metal` (165x),
-- `Copper` (3x), `Asbestos Shingle` (1x) — none of which exist in the
-- seeded option list (Asphalt Shingle / Architectural Shingle / Metal -
-- Standing Seam / Metal - Corrugated / Metal - Stone Coated / Tile / Flat /
-- Membrane / Wood Shake / Slate / Other).
--
-- These are NOT ambiguous data needing a guess — they're Isaac's actual
-- recorded vocabulary, meaning "type known, profile not yet specified."
-- Force-fitting `Metal` to `Metal - Standing Seam` fabricates precision he
-- never recorded; dumping `Shingle`+`Metal` into `Other` erases 281 of 342
-- roof-type values. `Asbestos Shingle` is the most consequential one to get
-- right despite being a single lead — it's a hazmat/abatement flag with real
-- safety and cost consequences on a tear-off, and must not be buried in a
-- generic `Other` bucket.
--
-- Extending the tenant's own config (rather than the DB schema) for this is
-- the same move as the `negotiating` kanban stage (20260723130000) — no code
-- change, Isaac refines to a specific profile per lead as he works it.
do $$
begin
  if not exists (
    select 1 from public.tenant_modules
    where org_id = '9d32b5a9-e11e-401b-8fa7-969065b004ce'
      and module_key = 'crm'
  ) then
    raise exception 'bmr_add_roof_type_options: no crm tenant_modules row for BMR (org_id 9d32b5a9-e11e-401b-8fa7-969065b004ce)';
  end if;
end $$;

update public.tenant_modules
set config = jsonb_set(
  jsonb_set(
    config,
    '{lead_control_center,fields,existing_roof_type,options}',
    '[
      {"label": "Asphalt Shingle", "value": "Asphalt Shingle"},
      {"label": "Architectural Shingle", "value": "Architectural Shingle"},
      {"label": "Metal - Standing Seam", "value": "Metal - Standing Seam"},
      {"label": "Metal - Corrugated", "value": "Metal - Corrugated"},
      {"label": "Metal - Stone Coated", "value": "Metal - Stone Coated"},
      {"label": "Tile", "value": "Tile"},
      {"label": "Flat / Membrane", "value": "Flat / Membrane"},
      {"label": "Wood Shake", "value": "Wood Shake"},
      {"label": "Slate", "value": "Slate"},
      {"label": "Shingle", "value": "Shingle"},
      {"label": "Metal", "value": "Metal"},
      {"label": "Copper", "value": "Copper"},
      {"label": "Asbestos Shingle", "value": "Asbestos Shingle"},
      {"label": "Other", "value": "Other"}
    ]'::jsonb
  ),
  '{lead_control_center,fields,roof_type_requested,options}',
  '[
    {"label": "Asphalt Shingle", "value": "Asphalt Shingle"},
    {"label": "Architectural Shingle", "value": "Architectural Shingle"},
    {"label": "Metal - Standing Seam", "value": "Metal - Standing Seam"},
    {"label": "Metal - Corrugated", "value": "Metal - Corrugated"},
    {"label": "Metal - Stone Coated", "value": "Metal - Stone Coated"},
    {"label": "Tile", "value": "Tile"},
    {"label": "Flat / Membrane", "value": "Flat / Membrane"},
    {"label": "Wood Shake", "value": "Wood Shake"},
    {"label": "Slate", "value": "Slate"},
    {"label": "Shingle", "value": "Shingle"},
    {"label": "Metal", "value": "Metal"},
    {"label": "Copper", "value": "Copper"},
    {"label": "Asbestos Shingle", "value": "Asbestos Shingle"},
    {"label": "Other", "value": "Other"}
  ]'::jsonb
),
    updated_at = now()
where org_id = '9d32b5a9-e11e-401b-8fa7-969065b004ce'
  and module_key = 'crm';
