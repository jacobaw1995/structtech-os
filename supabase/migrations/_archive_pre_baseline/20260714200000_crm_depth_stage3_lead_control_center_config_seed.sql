-- StructTech OS — CRM Depth Stage 3: Lead Control Center config seed (BMR)
--
-- NOT APPLIED. Author-only migration file — ask before applying, same as
-- every other migration in this repo. Depends on the Stage 3 schema/RPC
-- migration (20260714180000) already being applied — this is data-only,
-- no schema changes, but conceptually follows it.
--
-- SCOPE §12F correction: the command-stage/field/checklist DEFINITIONS
-- are per-tenant config (tenant_modules.config), not hardcoded TS — same
-- pattern as the existing 'stages' key (kanban pipeline config, seeded by
-- 20260712130000). This migration seeds BMR's config with the exact set
-- previously hardcoded in src/lib/crm/command-center.ts /
-- intake-checklist.ts / scope-fields.ts (that TS is being refactored to
-- READ this config generically, not hold the definitions itself — see the
-- config-shape note delivered in chat alongside this file).
--
-- Merged via config || jsonb_build_object(...), same as the existing
-- stage-config seed — does not touch the live 'stages' (kanban) or
-- 'follow_up_cadence_days' keys already on BMR's crm tenant_modules row.
--
-- BMR only. StructTech's own internal crm (scan -> sold funnel) is a
-- different process, not a roofing lead-intake flow — not seeded here.
-- Same "targeting by tenant_type, not org_id" caveat already flagged in
-- the Week 2 stage-config migration applies: this targets the one
-- existing contractor org; revisit by org_id once a second contractor
-- tenant exists.
--
-- No dropdown "options" for select-type fields (roof colors, metal types,
-- etc.) — that's catalog/pricing-matrix territory, explicitly out of
-- scope now (BACKLOG.md). Fields are typed "select" but carry no options
-- array yet.
--
-- scope checklist field_keys are bare, stable keys (roof_area_sqft, not
-- site_visit_scope.roof_area_sqft) — deliberately decoupled from storage
-- location (each field's own source.path says where it's actually kept)
-- so a future pricing matrix can reference "gutters_lf" without caring
-- that it lives under intake_checklist.site_visit_scope in the DB.

do $$
begin
  if not exists (
    select 1 from public.tenant_modules tm
    join public.organizations o on o.id = tm.org_id
    where o.tenant_type = 'contractor' and tm.module_key = 'crm'
  ) then
    raise exception 'lead_control_center config seed: no crm tenant_modules row for a contractor org';
  end if;
end $$;

update public.tenant_modules tm
set config = tm.config || jsonb_build_object(
  'lead_control_center', jsonb_build_object(

    'lead_type_options', jsonb_build_array(
      jsonb_build_object('value', 'homeowner', 'label', 'Homeowner'),
      jsonb_build_object('value', 'contractor', 'label', 'Contractor (GC)'),
      jsonb_build_object('value', 'property_management', 'label', 'Property Management'),
      jsonb_build_object('value', 'commercial', 'label', 'Commercial-Other')
    ),

    'command_stages', jsonb_build_array(
      jsonb_build_object('key', 'new_lead', 'label', 'New Lead', 'vital_field_keys',
        jsonb_build_array('first_name','last_name','phone','email','lead_type','main_issue','existing_roof_type','roof_type_requested','remodel_or_new_construction','service_address','source')),
      jsonb_build_object('key', 'site_visit', 'label', 'Site Visit', 'vital_field_keys',
        jsonb_build_array('service_address','visit_status','phone','existing_roof_type','roof_type_requested')),
      jsonb_build_object('key', 'scope', 'label', 'Scope', 'vital_field_keys',
        jsonb_build_array('service_address','existing_roof_type','roof_type_requested','scope_status')),
      jsonb_build_object('key', 'quote', 'label', 'Quote', 'vital_field_keys',
        jsonb_build_array('service_address','existing_roof_type','roof_type_requested','main_issue','key_decision_maker')),
      jsonb_build_object('key', 'negotiating', 'label', 'Negotiating', 'vital_field_keys',
        jsonb_build_array('value','roof_type_requested','stage','last_note')),
      jsonb_build_object('key', 'closed', 'label', 'Closed', 'vital_field_keys',
        jsonb_build_array('value','outcome'))
    ),

    'checklists', jsonb_build_object(
      'intake_call', jsonb_build_object(
        'title', 'Intake Call Checklist',
        'field_keys', jsonb_build_array(
          'first_name','last_name','phone','email','lead_type','service_address','main_issue',
          'existing_roof_type','roof_type_requested','remodel_or_new_construction',
          'site_visit_scheduled_at','estimate_inputs.approx_roof_area','estimate_inputs.pitch','estimate_inputs.metal_type'
        )
      ),
      'site_visit_scope', jsonb_build_object(
        'title', 'Site Visit Scope Checklist',
        'field_keys', jsonb_build_array(
          'roof_area_sqft','facets','pitch_slope_notes','gutters_lf','fascia_lf','soffit_lf',
          'pipe_boots','roof_vents','osb_replacement_sheets','roof_color','roof_profile_style',
          'gutter_color','ice_water_shield','drip_edge','scope_notes'
        )
      )
    ),

    'fields', jsonb_build_object(
      'first_name', jsonb_build_object('label', 'First name', 'empty_hint', 'Get their first name', 'type', 'text',
        'source', jsonb_build_object('kind', 'column', 'column', 'first_name')),
      'last_name', jsonb_build_object('label', 'Last name', 'empty_hint', 'Get their last name', 'type', 'text',
        'source', jsonb_build_object('kind', 'column', 'column', 'last_name')),
      'phone', jsonb_build_object('label', 'Cell phone', 'empty_hint', 'Get a cell number', 'type', 'phone',
        'source', jsonb_build_object('kind', 'column', 'column', 'phone')),
      'email', jsonb_build_object('label', 'Email', 'empty_hint', 'Get an email', 'type', 'email',
        'source', jsonb_build_object('kind', 'column', 'column', 'email')),
      'lead_type', jsonb_build_object('label', 'Customer type', 'empty_hint', 'Homeowner, contractor, property management, or commercial?', 'type', 'select',
        'source', jsonb_build_object('kind', 'column', 'column', 'lead_type')),
      'existing_roof_type', jsonb_build_object('label', 'Existing roof type(s)', 'empty_hint', 'Current roof material(s)?', 'type', 'roof_types',
        'source', jsonb_build_object('kind', 'column', 'column', 'existing_roof_type')),
      'roof_type_requested', jsonb_build_object('label', 'Requested roof type(s)', 'empty_hint', 'What roof do they want?', 'type', 'roof_types',
        'source', jsonb_build_object('kind', 'column', 'column', 'roof_type_requested')),
      'remodel_or_new_construction', jsonb_build_object('label', 'Remodel or new construction', 'empty_hint', 'Remodel or new construction?', 'type', 'select',
        'source', jsonb_build_object('kind', 'column', 'column', 'remodel_or_new_construction')),
      'source', jsonb_build_object('label', 'Source', 'empty_hint', '', 'type', 'readonly', 'counts_toward_completion', false,
        'source', jsonb_build_object('kind', 'column', 'column', 'source')),
      'value', jsonb_build_object('label', 'Quote amount', 'empty_hint', 'Set a quote amount', 'type', 'number', 'counts_toward_completion', false,
        'source', jsonb_build_object('kind', 'column', 'column', 'value')),
      'stage', jsonb_build_object('label', 'Pipeline stage', 'empty_hint', '', 'type', 'readonly', 'counts_toward_completion', false,
        'source', jsonb_build_object('kind', 'column', 'column', 'stage')),

      'service_address', jsonb_build_object('label', 'Service address', 'empty_hint', 'Get the job site address', 'type', 'address',
        'source', jsonb_build_object('kind', 'columns', 'columns', jsonb_build_array('service_address_street','service_address_city','service_address_state','service_address_zip'))),

      'main_issue', jsonb_build_object('label', 'Main issue', 'empty_hint', E'What\'s the problem?', 'type', 'textarea',
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('main_issue'))),
      'general_notes', jsonb_build_object('label', 'General notes', 'empty_hint', '', 'type', 'textarea', 'counts_toward_completion', false,
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('general_notes'))),
      'site_visit_scheduled_at', jsonb_build_object('label', 'Site visit scheduled', 'empty_hint', 'Schedule the site visit', 'type', 'date',
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('site_visit_scheduled_at'))),
      'key_decision_maker', jsonb_build_object('label', 'Key decision maker', 'empty_hint', 'Who signs off on this?', 'type', 'text', 'counts_toward_completion', false,
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('key_decision_maker'))),

      'estimate_inputs.approx_roof_area', jsonb_build_object('label', 'Approx. roof area (sq ft)', 'empty_hint', 'Ballpark roof area for a preliminary estimate', 'type', 'number',
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('estimate_inputs','approx_roof_area'))),
      'estimate_inputs.pitch', jsonb_build_object('label', 'Approx. pitch', 'empty_hint', 'Ballpark pitch', 'type', 'text',
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('estimate_inputs','pitch'))),
      'estimate_inputs.metal_type', jsonb_build_object('label', 'Likely metal type', 'empty_hint', 'Likely metal type', 'type', 'select',
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('estimate_inputs','metal_type'))),

      'roof_area_sqft', jsonb_build_object('label', 'Roof area (sq ft)', 'empty_hint', 'Measure the roof area', 'type', 'number',
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('site_visit_scope','roof_area_sqft'))),
      'facets', jsonb_build_object('label', 'Facets', 'empty_hint', 'Count the roof facets', 'type', 'number',
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('site_visit_scope','facets'))),
      'pitch_slope_notes', jsonb_build_object('label', 'Pitch / slope notes', 'empty_hint', 'Note the pitch/slope', 'type', 'textarea',
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('site_visit_scope','pitch_slope_notes'))),
      'gutters_lf', jsonb_build_object('label', 'Gutters (lf)', 'empty_hint', 'Measure gutters', 'type', 'number',
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('site_visit_scope','gutters_lf'))),
      'fascia_lf', jsonb_build_object('label', 'Fascia (lf)', 'empty_hint', 'Measure fascia', 'type', 'number',
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('site_visit_scope','fascia_lf'))),
      'soffit_lf', jsonb_build_object('label', 'Soffit (lf)', 'empty_hint', 'Measure soffit', 'type', 'number',
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('site_visit_scope','soffit_lf'))),
      'pipe_boots', jsonb_build_object('label', 'Pipe boots', 'empty_hint', 'Count pipe boots', 'type', 'number',
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('site_visit_scope','pipe_boots'))),
      'roof_vents', jsonb_build_object('label', 'Roof vents', 'empty_hint', 'Count roof vents', 'type', 'number',
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('site_visit_scope','roof_vents'))),
      'osb_replacement_sheets', jsonb_build_object('label', 'OSB replacement (sheets)', 'empty_hint', 'Estimate OSB sheets needed', 'type', 'number',
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('site_visit_scope','osb_replacement_sheets'))),
      'roof_color', jsonb_build_object('label', 'Roof color', 'empty_hint', 'Pick a roof color', 'type', 'select',
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('site_visit_scope','roof_color'))),
      'roof_profile_style', jsonb_build_object('label', 'Roof profile / style', 'empty_hint', 'Pick a profile/style', 'type', 'select',
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('site_visit_scope','roof_profile_style'))),
      'gutter_color', jsonb_build_object('label', 'Gutter color', 'empty_hint', 'Pick a gutter color', 'type', 'select',
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('site_visit_scope','gutter_color'))),
      'ice_water_shield', jsonb_build_object('label', 'Ice & water shield', 'empty_hint', 'Note ice & water shield scope', 'type', 'text',
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('site_visit_scope','ice_water_shield'))),
      'drip_edge', jsonb_build_object('label', 'Drip edge', 'empty_hint', 'Note drip edge scope', 'type', 'text',
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('site_visit_scope','drip_edge'))),
      'scope_notes', jsonb_build_object('label', 'Scope notes / extras', 'empty_hint', 'Any extra scope notes', 'type', 'textarea', 'counts_toward_completion', false,
        'source', jsonb_build_object('kind', 'json', 'path', jsonb_build_array('site_visit_scope','scope_notes'))),

      'visit_status', jsonb_build_object('label', 'Visit status', 'empty_hint', '', 'type', 'readonly', 'counts_toward_completion', false,
        'source', jsonb_build_object('kind', 'computed', 'id', 'visit_status')),
      'scope_status', jsonb_build_object('label', 'Scope status', 'empty_hint', '', 'type', 'readonly', 'counts_toward_completion', false,
        'source', jsonb_build_object('kind', 'computed', 'id', 'scope_status')),

      'last_note', jsonb_build_object('label', 'Last note', 'empty_hint', 'No notes yet', 'type', 'readonly', 'counts_toward_completion', false,
        'source', jsonb_build_object('kind', 'external')),
      'outcome', jsonb_build_object('label', 'Outcome', 'empty_hint', '', 'type', 'readonly', 'counts_toward_completion', false,
        'source', jsonb_build_object('kind', 'external'))
    )
  )
),
    updated_at = now()
from public.organizations o
where tm.org_id = o.id
  and o.tenant_type = 'contractor'
  and tm.module_key = 'crm';
