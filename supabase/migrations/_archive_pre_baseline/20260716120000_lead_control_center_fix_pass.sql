-- StructTech OS — Lead Control Center fix pass (Jacob's phone test, 7/16)
--
-- 1. BUG FIX: update_intake_checklist_field's jsonb_set(intake_checklist,
--    p_field_path, p_value, true) silently no-ops for any 2-level path
--    whose parent key doesn't exist yet (estimate_inputs.*, all 15
--    site_visit_scope.* fields) — confirmed live: BMR's test lead's
--    intake_checklist only has main_issue/site_visit_scheduled_at
--    (1-level paths); estimate_inputs was never created despite the UI
--    letting you type into those rows. Postgres's jsonb_set only creates
--    the FINAL path segment when create_missing=true — it does not
--    auto-vivify intermediate containers. Fix: when the path has 2
--    elements, first ensure the parent object exists (coalesce to '{}'),
--    then set the leaf. Same signature — CREATE OR REPLACE, no DROP
--    needed.
--
-- 2 & 3 are config-only (tenant_modules.config->lead_control_center),
-- BMR only, same '||'/jsonb_set merge precedent as every prior seed:
--
-- 2. site_visit_scheduled_at field type: date -> datetime (capture a
--    time, not just a date). Pure config + the engine's FieldType/input
--    mapping (separate code change, not in this file).
--
-- 3. existing_roof_type / roof_type_requested get a seeded default
--    options list so they render as dropdowns instead of free-text
--    comma-separated input. Same list for both (what it is now / what
--    they want share the same vocabulary). Editable later via the
--    (not-yet-built) config authoring UI.

create or replace function public.update_intake_checklist_field(p_deal_id uuid, p_field_path text[], p_value jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_org_id uuid;
  v_intake jsonb;
begin
  if array_length(p_field_path, 1) is null or array_length(p_field_path, 1) not between 1 and 2 then
    raise exception 'p_field_path must have 1 or 2 elements, got %', p_field_path;
  end if;

  select org_id, coalesce(intake_checklist, '{}'::jsonb)
  into v_org_id, v_intake
  from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  -- Ensure the parent object exists before setting the leaf — jsonb_set's
  -- create_missing only creates the last path segment, not this one.
  if array_length(p_field_path, 1) = 2 then
    v_intake := jsonb_set(
      v_intake,
      p_field_path[1:1],
      coalesce(v_intake -> p_field_path[1], '{}'::jsonb),
      true
    );
  end if;

  v_intake := jsonb_set(v_intake, p_field_path, p_value, true);

  update public.deals
  set intake_checklist = v_intake,
      updated_at = now()
  where id = p_deal_id;
end;
$function$;

update public.tenant_modules tm
set config = jsonb_set(
  tm.config,
  '{lead_control_center,fields,site_visit_scheduled_at,type}',
  '"datetime"'
),
    updated_at = now()
from public.organizations o
where tm.org_id = o.id
  and o.tenant_type = 'contractor'
  and tm.module_key = 'crm';

update public.tenant_modules tm
set config = jsonb_set(
  jsonb_set(
    tm.config,
    '{lead_control_center,fields,existing_roof_type,options}',
    (select jsonb_agg(jsonb_build_object('value', v, 'label', v)) from unnest(array[
      'Asphalt Shingle', 'Architectural Shingle', 'Metal - Standing Seam', 'Metal - Corrugated',
      'Metal - Stone Coated', 'Tile', 'Flat / Membrane', 'Wood Shake', 'Slate', 'Other'
    ]) as v)
  ),
  '{lead_control_center,fields,roof_type_requested,options}',
  (select jsonb_agg(jsonb_build_object('value', v, 'label', v)) from unnest(array[
    'Asphalt Shingle', 'Architectural Shingle', 'Metal - Standing Seam', 'Metal - Corrugated',
    'Metal - Stone Coated', 'Tile', 'Flat / Membrane', 'Wood Shake', 'Slate', 'Other'
  ]) as v)
),
    updated_at = now()
from public.organizations o
where tm.org_id = o.id
  and o.tenant_type = 'contractor'
  and tm.module_key = 'crm';
