-- BMR data migration — transform: raw staging -> deals / deal_notes / deal_activity.
--
-- NOT APPLIED. Do not run against the live project without Jacob's review —
-- same rule as every migration in this repo. This is a one-time DATA
-- transform, not a schema migration, so it lives here (docs/migration/),
-- not in supabase/migrations/.
--
-- Context: docs/reference/BMR_DATA_MIGRATION_PLAN.md — §4b (supersedes §2/§4,
-- audited against the REAL export) and §7b (checklist/ownership/activity,
-- confirmed against the real export) are authoritative; §4/§5/§7 are the
-- superseded first draft. Second review round (7/19/26) found the real
-- leads.json export had drifted from the plan's original schema guess (which
-- was built off an empty shell table, not the live old app) — this version
-- incorporates every correction from that review plus two live decisions:
-- lead_type populates from `homeowner_or_contractor` (reverses the original
-- "leave null" call — that call assumed no source field existed; one does),
-- and existing_roof_type/roof_type_requested get a full value-normalization
-- map with 4 new options added to BMR's config (Shingle/Metal/Copper/
-- Asbestos Shingle) rather than fabricating precision or dumping into Other.
--
-- PREREQUISITE: 20260723120000 (staging tables), 20260723130000 (negotiating
-- kanban stage), and 20260723140000 (roof-type config options) applied, and
-- the 4 *_raw tables populated from the real export (188/171/587/2 rows,
-- validated — plain JSON arrays, no json_agg wrapper).
--
-- HOW TO RUN (plan §8 steps 5-6):
--   1. Dry run:  BEGIN; \i bmr_transform.sql   then run the diagnostics
--      block at the bottom, eyeball it, then ROLLBACK.
--   2. For real: BEGIN; \i bmr_transform.sql   diagnostics look right,
--      COMMIT.
-- Every insert is idempotent (id_map rows are `on conflict do nothing`, and
-- deals/deal_notes/deal_activity are inserted with the id_map's stable id
-- and `on conflict (id) do nothing`), so re-running after a partial failure
-- or a prior real load is always safe — nothing duplicates.
--
-- BMR org (constant throughout): 9d32b5a9-e11e-401b-8fa7-969065b004ce
-- Isaac's profile (constant, owner override — see MUST-FIX 2 below): d63871d2-cb54-44b2-bac4-502d22a79d96

-- ============================================================================
-- 1. Identity map — old-app user -> public.profiles, matched by email.
--    Unmatched old users (departed/unknown) simply get no row here; every
--    downstream actor_id/created_by lookup is a LEFT JOIN, so they resolve
--    to NULL — the app already renders unattributed rows gracefully
--    (verified in Stage 5 Track C2). Both known users
--    (isaac@brothersmetalroofing.com, jacob@structtek.com) have matching
--    profiles, so NULL-actor rows are not expected in practice. NOTE: this
--    map is used for note authors and activity actors (real history). It is
--    NOT used for deals.owner_id — see MUST-FIX 2.
-- ============================================================================
insert into public.migration_bmr_id_map (entity, old_id, new_id)
select
  'user',
  (u.payload->>'id')::uuid,
  p.id
from public.migration_bmr_users_raw u
join public.profiles p
  on lower(p.email) = lower(u.payload->>'email')
on conflict (entity, old_id) do nothing;

-- ============================================================================
-- 2. Identity map — old lead -> new deal id (generated once, stable on rerun).
-- ============================================================================
insert into public.migration_bmr_id_map (entity, old_id, new_id)
select 'lead', old_id, gen_random_uuid()
from public.migration_bmr_leads_raw
on conflict (entity, old_id) do nothing;

-- ============================================================================
-- 3. leads -> deals
-- ============================================================================

-- Roof-type vocabulary normalization (plan §4b-d) — complete map, all 15
-- distinct values across both old fields, nothing falls through to 'Other'.
-- `Shingle`/`Metal`/`Copper`/`Asbestos Shingle` are Isaac's actual recorded
-- vocabulary (not ambiguous data we're guessing at) and were added as real
-- options to BMR's config (20260723140000) rather than force-fit or binned
-- into Other — Asbestos Shingle in particular is a hazmat/safety flag that
-- must not be silently absorbed into a generic bucket.
with roof_type_map (old_value, new_value) as (
  values
    ('Standing Seam',        'Metal - Standing Seam'),
    ('metal_standing_seam',  'Metal - Standing Seam'),
    ('metal_exposed_fastener','Metal - Corrugated'),
    ('asphalt_shingle',      'Asphalt Shingle'),
    ('Cedar Shake',          'Wood Shake'),
    ('wood_shake',           'Wood Shake'),
    ('Slate',                'Slate'),
    ('Flat',                 'Flat / Membrane'),
    ('tpo_membrane',         'Flat / Membrane'),
    ('rubber_epdm',          'Flat / Membrane'),
    ('PVC',                  'Flat / Membrane'),
    ('Shingle',              'Shingle'),
    ('Metal',                'Metal'),
    ('Copper',               'Copper'),
    ('Asbestos Shingle',     'Asbestos Shingle')
),
src as (
  select
    old_id,
    payload,
    payload->>'first_name'                        as first_name,
    payload->>'last_name'                         as last_name,
    payload->>'name'                              as contact_name,
    nullif(payload->>'company_name', '')          as company,
    nullif(payload->>'phone', '')                 as old_phone,
    nullif(payload->>'cell_phone', '')             as cell_phone,
    nullif(payload->>'secondary_phone', '')        as old_secondary_phone,
    nullif(payload->>'email', '')                 as email,
    -- Service address: clean 1:1, unchanged from the first draft.
    nullif(payload->>'service_street_address', '') as service_street,
    nullif(payload->>'service_city', '')           as service_city,
    nullif(payload->>'service_state', '')          as service_state,
    nullif(payload->>'service_zip', '')            as service_zip,
    -- Billing address: §4b-b correction. The REAL billing source is
    -- billing_street_address/city/state/zip, NOT street_address/city/state/
    -- zip (which is a byte-for-byte duplicate of the service address in
    -- 176/176 rows where both are present — it's not billing data at all).
    -- `address` is likewise a derived duplicate of street_address; neither
    -- is read here.
    nullif(payload->>'billing_street_address', '') as billing_street,
    nullif(payload->>'billing_city', '')           as billing_city,
    nullif(payload->>'billing_state', '')          as billing_state,
    nullif(payload->>'billing_zip', '')            as billing_zip,
    nullif(payload->>'source', '')                 as source,
    nullif(payload->>'referral_name', '')          as referral_name,
    payload->>'stage'                              as old_stage,
    payload->>'status'                             as old_status,
    nullif(payload->>'value', '')::numeric         as value,
    nullif(payload->>'lost_reason', '')            as lost_reason,
    coalesce(payload->'intake_checklist', '{}'::jsonb) as old_checklist,
    -- Milestones: §4b-a correction. The export ALREADY uses our column
    -- names (site_survey_complete_at, roof_scope_ordered_at) — the plan's
    -- first draft was reading site_visit_complete_at/scope_ordered_at,
    -- keys that DO NOT EXIST in the real export, so both milestones would
    -- have silently landed NULL for every lead (payload->>'missing_key'
    -- returns NULL, not an error) and command-stage derivation would have
    -- been quietly broken.
    nullif(payload->>'site_survey_complete_at', '')::timestamptz as site_survey_complete_at,
    nullif(payload->>'roof_scope_ordered_at', '')::timestamptz   as roof_scope_ordered_at,
    nullif(payload->>'quote_presented_at', '')::timestamptz     as quote_presented_at,
    nullif(payload->>'proposal_sent_at', '')::timestamptz       as proposal_sent_at,
    nullif(payload->>'last_contacted_at', '')::timestamptz      as last_contacted_at,
    (payload->>'created_at')::timestamptz          as created_at,
    (payload->>'updated_at')::timestamptz          as updated_at,
    nullif(payload->>'closed_at', '')::timestamptz as closed_at,
    -- §4b-c: fields we have columns for but the first draft never mapped.
    nullif(payload->>'homeowner_or_contractor', '') as homeowner_or_contractor,
    -- remodel_or_new_construction: old values are 'Remodel' / 'New
    -- Construction' (Title Case); our CHECK constraint requires the exact
    -- lowercase/underscore form ('remodel' / 'new_construction'). The plan
    -- says "pass through as-is" (no lookup TABLE needed, unlike roof
    -- types), but a literal pass-through would fail the CHECK constraint on
    -- all 176 populated rows — so this still normalizes case/format, it
    -- just isn't a judgment call the way the roof-type map is.
    case nullif(payload->>'remodel_or_new_construction', '')
      when 'Remodel' then 'remodel'
      when 'New Construction' then 'new_construction'
      else null
    end as remodel_or_new_construction,
    (
      select array_agg(m.new_value order by t.ord)
      from unnest(string_to_array(nullif(payload->>'existing_roof_type', ''), ',')) with ordinality as t(val, ord)
      join roof_type_map m on m.old_value = btrim(t.val)
    ) as existing_roof_type,
    (
      select array_agg(m.new_value order by t.ord)
      from unnest(string_to_array(nullif(payload->>'roof_type_requested', ''), ',')) with ordinality as t(val, ord)
      join roof_type_map m on m.old_value = btrim(t.val)
    ) as roof_type_requested
  from public.migration_bmr_leads_raw
),
derived as (
  select
    src.*,
    -- Decision 4: cell_phone is primary. Old landline `phone` parks in
    -- secondary_phone ONLY if secondary_phone was empty (never overwrites
    -- a real secondary number, never doubles up cell_phone into both slots).
    coalesce(cell_phone, old_phone) as new_phone,
    coalesce(
      old_secondary_phone,
      case when cell_phone is not null then old_phone else null end
    ) as new_secondary_phone,
    nullif(concat_ws(', ', billing_street, billing_city, concat_ws(' ', billing_state, billing_zip)), '') as billing_address,
    -- Stage mapping per plan §5: status wins over stage for closed records.
    -- Applies the accepted "optional refinement" — a lead with
    -- site_survey_complete_at set (but not closed) lands in `site_visit`
    -- rather than `qualified`. Only 2 of 188 leads have this milestone set
    -- at all, so this affects at most 2 rows; the plan's expected
    -- distribution (§7b-d: new_lead 157 / lost 24 / negotiating 3 /
    -- qualified 3 / won 1, no site_visit bucket) was computed without
    -- cross-checking against this refinement — the diagnostics block below
    -- compares actual vs. expected and flags any variance for review rather
    -- than assuming either is right.
    case
      when old_status = 'closed_won' then 'won'
      when old_status = 'closed_lost' then 'lost'
      when old_stage = 'lead_captured' then 'new_lead'
      when old_stage = 'qualified' and site_survey_complete_at is not null then 'site_visit'
      when old_stage = 'qualified' then 'qualified'
      when old_stage = 'proposal_sent' then 'estimate_presented'
      when old_stage = 'negotiating' then 'negotiating'
      -- Edge case (plan §5): `closed` stage with neither closed status set.
      -- SHOULD-FIX 5: never default an ambiguous record to WON (would
      -- inflate revenue-positive outcomes) — default to 'lost' instead.
      -- Confirmed dead code on this export (every closed-stage row has a
      -- closed status), kept as a defensive fallback; flagged in
      -- diagnostics below either way.
      else 'lost'
    end as new_stage,
    -- Decision 5: park dropped-but-not-lost fields in intake_checklist
    -- instead of losing them; drop claim_locked entirely (doesn't exist in
    -- the real export anyway — confirmed).
    jsonb_strip_nulls(jsonb_build_object(
      'legacy_proposal_sent_at', proposal_sent_at,
      'legacy_last_contacted_at', last_contacted_at
    )) as legacy_fields,
    -- MUST-FIX 1 (plan §7b-a): checklist container/key rename. Only 5 of
    -- 188 leads have any checklist data; any key not explicitly listed here
    -- is dropped (not blind-copied) — see the diagnostics block for a
    -- dropped-key check against the real 5 records.
    jsonb_strip_nulls(jsonb_build_object(
      'main_issue', old_checklist->'main_issue',
      'general_notes', old_checklist->'general_notes',
      'estimate_inputs',
        case when old_checklist ? 'estimate_inputs' then
          nullif(jsonb_strip_nulls(jsonb_build_object(
            'pitch', old_checklist #> '{estimate_inputs,pitch_estimate}'
          )), '{}'::jsonb)
        else null end,
      'site_visit_scope',
        case when old_checklist ? 'site_visit' then
          nullif(jsonb_strip_nulls(jsonb_build_object(
            'roof_area_sqft',         old_checklist #> '{site_visit,roof_sqft}',
            'pitch_slope_notes',      old_checklist #> '{site_visit,pitch_notes}',
            'osb_replacement_sheets', old_checklist #> '{site_visit,osb_sheets}',
            'roof_profile_style',     old_checklist #> '{site_visit,roof_style}',
            'facets',                 old_checklist #> '{site_visit,facets}',
            'fascia_lf',              old_checklist #> '{site_visit,fascia_lf}',
            'soffit_lf',              old_checklist #> '{site_visit,soffit_lf}',
            'gutters_lf',             old_checklist #> '{site_visit,gutters_lf}',
            'pipe_boots',             old_checklist #> '{site_visit,pipe_boots}',
            'roof_color',             old_checklist #> '{site_visit,roof_color}',
            'roof_vents',             old_checklist #> '{site_visit,roof_vents}',
            'scope_notes',            old_checklist #> '{site_visit,scope_notes}',
            'gutter_color',           old_checklist #> '{site_visit,gutter_color}',
            'ice_water_shield',       old_checklist #> '{site_visit,ice_water_shield}',
            'drip_edge',              old_checklist #> '{site_visit,drip_edge}'
          )), '{}'::jsonb)
        else null end
    )) as mapped_checklist
  from src
)
insert into public.deals (
  id, org_id, contact_name, first_name, last_name, company, email, phone, secondary_phone,
  billing_address, service_address_street, service_address_city, service_address_state, service_address_zip,
  source, referral_name, stage, value, lost_reason, owner_id, intake_checklist,
  lead_type, remodel_or_new_construction, existing_roof_type, roof_type_requested,
  site_survey_complete_at, roof_scope_ordered_at, quote_presented_at,
  created_at, updated_at, closed_at
)
select
  m.new_id,
  '9d32b5a9-e11e-401b-8fa7-969065b004ce',
  d.contact_name,
  d.first_name,
  d.last_name,
  d.company,
  d.email,
  d.new_phone,
  d.new_secondary_phone,
  d.billing_address,
  d.service_street,
  d.service_city,
  d.service_state,
  d.service_zip,
  d.source,
  d.referral_name,
  d.new_stage,
  round(d.value)::integer,
  d.lost_reason,
  -- MUST-FIX 2 (plan §7b-b): owner_id is operational (who works the lead
  -- NOW), not history — set to Isaac for all 188 regardless of the old
  -- owner_id (which was Jacob on 159 of them purely because he ran the CSV
  -- import). Note authors and activity actors below keep real identities.
  'd63871d2-cb54-44b2-bac4-502d22a79d96',
  d.mapped_checklist || d.legacy_fields,
  -- §4b-c: direct source field, not an inference from company_name.
  case d.homeowner_or_contractor
    when 'Homeowner' then 'homeowner'
    when 'Contractor' then 'contractor'
    else null
  end,
  d.remodel_or_new_construction,
  d.existing_roof_type,
  d.roof_type_requested,
  d.site_survey_complete_at,
  d.roof_scope_ordered_at,
  d.quote_presented_at,
  d.created_at,
  d.updated_at,
  d.closed_at
from derived d
join public.migration_bmr_id_map m
  on m.entity = 'lead' and m.old_id = d.old_id
on conflict (id) do nothing;

-- ============================================================================
-- 4. lead_notes -> deal_notes
-- ============================================================================
insert into public.migration_bmr_id_map (entity, old_id, new_id)
select 'note', old_id, gen_random_uuid()
from public.migration_bmr_notes_raw
on conflict (entity, old_id) do nothing;

insert into public.deal_notes (id, deal_id, org_id, content, created_by, created_at)
select
  note_map.new_id,
  lead_map.new_id,
  '9d32b5a9-e11e-401b-8fa7-969065b004ce',
  n.payload->>'content',
  author_map.new_id,
  (n.payload->>'created_at')::timestamptz
from public.migration_bmr_notes_raw n
join public.migration_bmr_id_map note_map
  on note_map.entity = 'note' and note_map.old_id = n.old_id
join public.migration_bmr_id_map lead_map
  on lead_map.entity = 'lead' and lead_map.old_id = (n.payload->>'lead_id')::uuid
left join public.migration_bmr_id_map author_map
  on author_map.entity = 'user' and author_map.old_id = nullif(n.payload->>'author_id', '')::uuid
on conflict (id) do nothing;

-- ============================================================================
-- 5. lead_activity -> deal_activity
--    Action map per plan §7b-c, confirmed as a live decision in chat review
--    (7/19): ONLY `reassigned` is remapped (-> `owner_assigned`, since C1
--    writes that exact verb). `created`, `stage_changed`, `status_changed`,
--    `edited`, `value_set` all pass through as their raw old verb — mapping
--    them is lossy, and activityLabel() (src/lib/crm/stages.ts) already
--    falls back to the raw string via its switch's `default` case, so an
--    unrecognized legacy verb renders as-is instead of crashing or vanishing.
--
--    MUST-FIX 3: `reassigned` rows carry RAW UUIDs in from_value/to_value
--    (confirmed in the real export: 'unclaimed' -> 'f1828102-…'). Resolve
--    through the identity map to names, matching the C1 convention. This
--    resolution applies ONLY to reassigned/owner_assigned rows — every other
--    action's from_value/to_value is a plain stage/status string (confirmed:
--    'lead_captured' -> 'proposal_sent', etc.) and must NOT be run through
--    UUID resolution.
-- ============================================================================
insert into public.migration_bmr_id_map (entity, old_id, new_id)
select 'activity', old_id, gen_random_uuid()
from public.migration_bmr_activity_raw
on conflict (entity, old_id) do nothing;

with activity_src as (
  select
    old_id,
    payload,
    payload->>'action'   as old_action,
    payload->>'from_value' as raw_from,
    payload->>'to_value'   as raw_to,
    (payload->>'created_at')::timestamptz as created_at,
    nullif(payload->>'actor_id', '')::uuid as actor_id_old
  from public.migration_bmr_activity_raw
),
activity_resolved as (
  select
    s.*,
    case when old_action = 'reassigned' then 'owner_assigned' else old_action end as new_action,
    case
      when old_action <> 'reassigned' then raw_from
      when raw_from is null or raw_from = '' or lower(raw_from) = 'unclaimed' then 'Unassigned'
      when raw_from ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        coalesce(
          (select p.full_name from public.migration_bmr_id_map m
             join public.profiles p on p.id = m.new_id
           where m.entity = 'user' and m.old_id = raw_from::uuid),
          raw_from
        )
      else raw_from
    end as resolved_from,
    case
      when old_action <> 'reassigned' then raw_to
      when raw_to is null or raw_to = '' or lower(raw_to) = 'unclaimed' then 'Unassigned'
      when raw_to ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        coalesce(
          (select p.full_name from public.migration_bmr_id_map m
             join public.profiles p on p.id = m.new_id
           where m.entity = 'user' and m.old_id = raw_to::uuid),
          raw_to
        )
      else raw_to
    end as resolved_to
  from activity_src s
)
insert into public.deal_activity (id, deal_id, org_id, action, from_value, to_value, actor_id, created_at)
select
  activity_map.new_id,
  lead_map.new_id,
  '9d32b5a9-e11e-401b-8fa7-969065b004ce',
  a.new_action,
  a.resolved_from,
  a.resolved_to,
  actor_map.new_id,
  a.created_at
from activity_resolved a
join public.migration_bmr_id_map activity_map
  on activity_map.entity = 'activity' and activity_map.old_id = a.old_id
join public.migration_bmr_id_map lead_map
  on lead_map.entity = 'lead' and lead_map.old_id = (a.payload->>'lead_id')::uuid
left join public.migration_bmr_id_map actor_map
  on actor_map.entity = 'user' and actor_map.old_id = a.actor_id_old
on conflict (id) do nothing;

-- ============================================================================
-- 6. Diagnostics — run after the transform, before deciding COMMIT/ROLLBACK.
--    Mirrors plan §9's verification checklist.
-- ============================================================================

-- Row counts. SHOULD-FIX 4: join to migration_bmr_id_map rather than a raw
-- org_id count — BMR already has ~8 pre-existing deals plus test notes/
-- activity, so a raw org_id filter overcounts and looks like a false failure.
select
  (select count(*) from public.migration_bmr_leads_raw) as source_leads,
  (select count(*) from public.deals d join public.migration_bmr_id_map m on m.entity = 'lead' and m.new_id = d.id) as loaded_deals,
  (select count(*) from public.migration_bmr_notes_raw) as source_notes,
  (select count(*) from public.deal_notes n join public.migration_bmr_id_map m on m.entity = 'note' and m.new_id = n.id) as loaded_notes,
  (select count(*) from public.migration_bmr_activity_raw) as source_activity,
  (select count(*) from public.deal_activity a join public.migration_bmr_id_map m on m.entity = 'activity' and m.new_id = a.id) as loaded_activity;

-- Kanban distribution — compare against plan §7b-d's expected new_lead 157 /
-- lost 24 / negotiating 3 / qualified 3 / won 1 (=188, no site_visit bucket).
-- A `site_visit` row here (at most 2) is the accepted refinement firing, not
-- a bug — see the comment on `new_stage` above.
select stage, count(*)
from public.deals d
join public.migration_bmr_id_map m on m.entity = 'lead' and m.new_id = d.id
group by stage
order by count(*) desc;

-- Edge-case flag: old `closed` stage with neither closed_won nor
-- closed_lost status. Plan says this is dead code on the real export
-- (confirm zero rows here).
select old_id, payload->>'name', payload->>'stage', payload->>'status', payload->>'lost_reason', payload->>'closed_at'
from public.migration_bmr_leads_raw
where payload->>'stage' = 'closed'
  and payload->>'status' not in ('closed_won', 'closed_lost');

-- Unmatched actors: old author/actor ids with no id_map('user') row —
-- should be empty given the known 2-user identity map, but confirms it.
-- (owner_id is no longer checked here — MUST-FIX 2 makes it a constant.)
select 'note_author' as role, old_id
from public.migration_bmr_notes_raw
where nullif(payload->>'author_id', '') is not null
  and not exists (
    select 1 from public.migration_bmr_id_map m
    where m.entity = 'user' and m.old_id = (payload->>'author_id')::uuid
  )
union all
select 'activity_actor', old_id
from public.migration_bmr_activity_raw
where nullif(payload->>'actor_id', '') is not null
  and not exists (
    select 1 from public.migration_bmr_id_map m
    where m.entity = 'user' and m.old_id = (payload->>'actor_id')::uuid
  );

-- Roof-type mapping coverage: any row where the raw token count doesn't
-- match the mapped count means some token wasn't in roof_type_map — the
-- plan claims the map is complete (nothing falls through); this proves it
-- against the real data instead of trusting the claim.
select old_id, payload->>'existing_roof_type' as raw_existing, payload->>'roof_type_requested' as raw_requested
from public.migration_bmr_leads_raw r
where
  (
    (select array_length(string_to_array(nullif(r.payload->>'existing_roof_type', ''), ','), 1))
    is distinct from
    (select count(*) from unnest(string_to_array(nullif(r.payload->>'existing_roof_type', ''), ',')) as t(val)
       join (values
         ('Standing Seam','x'),('metal_standing_seam','x'),('metal_exposed_fastener','x'),('asphalt_shingle','x'),
         ('Cedar Shake','x'),('wood_shake','x'),('Slate','x'),('Flat','x'),('tpo_membrane','x'),('rubber_epdm','x'),
         ('PVC','x'),('Shingle','x'),('Metal','x'),('Copper','x'),('Asbestos Shingle','x')
       ) as m(old_value, _) on m.old_value = btrim(t.val))
  )
  or
  (
    (select array_length(string_to_array(nullif(r.payload->>'roof_type_requested', ''), ','), 1))
    is distinct from
    (select count(*) from unnest(string_to_array(nullif(r.payload->>'roof_type_requested', ''), ',')) as t(val)
       join (values
         ('Standing Seam','x'),('metal_standing_seam','x'),('metal_exposed_fastener','x'),('asphalt_shingle','x'),
         ('Cedar Shake','x'),('wood_shake','x'),('Slate','x'),('Flat','x'),('tpo_membrane','x'),('rubber_epdm','x'),
         ('PVC','x'),('Shingle','x'),('Metal','x'),('Copper','x'),('Asbestos Shingle','x')
       ) as m(old_value, _) on m.old_value = btrim(t.val))
  );

-- intake_checklist sample — all 5 populated real records, before vs. after,
-- to eyeball against tenant_modules.config->lead_control_center->fields.
select
  old_id,
  payload->'intake_checklist' as old_checklist,
  d.intake_checklist as new_checklist
from public.migration_bmr_leads_raw r
join public.deals d on d.id = (select new_id from public.migration_bmr_id_map m where m.entity='lead' and m.old_id = r.old_id)
where payload->'intake_checklist' is not null and payload->'intake_checklist' <> '{}'::jsonb;
