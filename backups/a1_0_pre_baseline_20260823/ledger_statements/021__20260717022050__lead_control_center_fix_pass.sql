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
