-- BMR kanban: add a `negotiating` stage between Estimate Presented and Won/Lost.
--
-- NOT APPLIED. Author-only migration file — ask before applying to the live
-- Supabase project, same as every other migration in this repo.
--
-- Context: docs/reference/BMR_DATA_MIGRATION_PLAN.md §5, decision resolved
-- 7/19 — the old standalone BMR app had a `negotiating` stage that BMR's new
-- kanban (seeded in 20260712130000) doesn't. Rather than flattening those
-- leads into `estimate_presented`, add the stage back so the migrated data
-- (and Isaac's future workflow) reflects his real working stages. This is a
-- nice live demo of the config-driven stage model too — no code change, one
-- config edit.
--
-- Scoped to BMR's org_id specifically, NOT `tenant_type = 'contractor'`
-- generally (contrast with 20260712130000's seed, which targets by tenant
-- type because it applies to every contractor org at once). BMR is the only
-- contractor tenant today, but this stage exists to match Isaac's old-app
-- history — a future contractor tenant onboarded fresh shouldn't inherit it
-- by default.
--
-- Command-tab `negotiating` already exists (config's `command_stages`, which
-- is a separate, already-6-stage list: derived from milestone data, not
-- stored on the row) — this migration only touches the *kanban* `stages`
-- array, which was missing it.
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
