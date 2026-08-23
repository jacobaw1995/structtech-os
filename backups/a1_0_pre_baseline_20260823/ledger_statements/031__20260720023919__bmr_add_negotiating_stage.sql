-- BMR kanban: add a `negotiating` stage between Estimate Presented and Won/Lost.
-- Context: docs/reference/BMR_DATA_MIGRATION_PLAN.md §5 / §7b-d.
do $$
begin
  if not exists (
    select 1 from public.tenant_modules
    where org_id = '9d32b5a9-e11e-401b-8fa7-969065b004ce'
      and module_key = 'crm'
  ) then
    raise exception 'bmr_add_negotiating_stage: no crm tenant_modules row for BMR (org_id 9d32b5a9-e11e-401b-8fa7-969065b004ce)';
  end if;
end $$;

update public.tenant_modules
set config = config || jsonb_build_object(
  'stages', jsonb_build_array(
    jsonb_build_object('key', 'new_lead',            'label', 'New Lead',            'cancel_pending_follow_ups', false, 'outcome', null),
    jsonb_build_object('key', 'qualified',           'label', 'Qualified',           'cancel_pending_follow_ups', true,  'outcome', null),
    jsonb_build_object('key', 'site_visit',          'label', 'Site Visit',          'cancel_pending_follow_ups', true,  'outcome', null),
    jsonb_build_object('key', 'estimate_presented',  'label', 'Estimate Presented',  'cancel_pending_follow_ups', true,  'outcome', null),
    jsonb_build_object('key', 'negotiating',         'label', 'Negotiating',         'cancel_pending_follow_ups', true,  'outcome', null),
    jsonb_build_object('key', 'won',                 'label', 'Won',                 'cancel_pending_follow_ups', true,  'outcome', 'won'),
    jsonb_build_object('key', 'lost',                'label', 'Lost',                'cancel_pending_follow_ups', true,  'outcome', 'lost')
  )
),
    updated_at = now()
where org_id = '9d32b5a9-e11e-401b-8fa7-969065b004ce'
  and module_key = 'crm';
