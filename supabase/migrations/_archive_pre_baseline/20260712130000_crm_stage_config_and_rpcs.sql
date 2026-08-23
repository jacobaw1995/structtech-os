-- StructTech OS — Week 2 Stage 1: per-tenant CRM stage config + RPCs
--
-- NOT APPLIED. Author-only migration file — ask before applying, same as
-- every other migration in this repo. Depends on Stage 0
-- (20260711120100_backfill_org_id_crm.sql, 20260712120000_org_scoped_rls_crm.sql)
-- already being applied — this migration reads/writes org_id columns and
-- relies on my_org_ids()-scoped RLS that Stage 0 put in place.
--
-- What this does, in order:
--   1. Three small read-only helpers (crm_stage_config / crm_stage_entry /
--      crm_follow_up_cadence_days) that resolve an org's per-tenant CRM
--      config out of tenant_modules.config — the single source of truth
--      the trigger and RPCs below both read from, instead of hardcoding
--      StructTech's stage vocabulary the way the live functions do today.
--   2. Seeds StructTech's config to its real current stage list, verbatim
--      (so nothing about StructTech's live behavior changes), and BMR's to
--      its own list.
--   3. Rewrites deal_stage_side_effects() and auto_create_deal() to read
--      from that config instead of hardcoded stage-name lists — this is
--      also the fix for the live create_engagement_from_roadmap()
--      misfire risk found during Week 2 planning (see inline comment).
--   4. Adds create_deal / fetch_deal / update_deal_stage / add_deal_note —
--      the security-definer RPCs Stage 2's pipeline UI calls. No UI in
--      this migration.
--
-- Deliberately NOT done here:
--   * No email-copy templating system. auto_create_deal()'s scan-specific
--     copy ("your Revenue Leak Report", $-leak figures) is untouched
--     wording — only the day-2/day-5 numbers become config-driven.
--     create_deal()'s follow-ups (BMR + manual StructTech deals) get
--     generic placeholder copy, not scan-specific copy; refining that is a
--     content task, not a schema one.
--   * No actual sending — follow_ups.status stays 'pending'; the Make
--     scenario that sends them is still out of scope (BUILD_PLAN: "schema
--     + UI now").
--   * No NOT NULL on deals.org_id yet — noted in Stage 0's backfill file,
--     still true here.

-- ============================================================================
-- 1a. crm_stage_config(org_id) — the org's configured stage list (jsonb
-- array), or '[]' if the org has no crm module row / no stages configured
-- yet. No caller-membership guard, on purpose: auto_create_deal() (below)
-- fires from an ANON-role trigger (the public scan intake's "Allow anon
-- insert" policy on audit_leads) and calls this internally — an
-- auth.uid()-based guard here would make my_org_ids() return empty for
-- that anon context and break the scan flow. The data exposed (stage
-- labels/keys) isn't sensitive; org-scoped RLS on tenant_modules already
-- protects the actual entitlement data if this is ever called directly.
-- ============================================================================
create or replace function public.crm_stage_config(p_org_id uuid)
returns jsonb
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(tm.config -> 'stages', '[]'::jsonb)
  from public.tenant_modules tm
  where tm.org_id = p_org_id
    and tm.module_key = 'crm'
  limit 1;
$$;

comment on function public.crm_stage_config(uuid) is
  'The org''s configured CRM stage list (tenant_modules.config->stages), or [] if unset. Internal helper — see header comment for why it has no auth guard.';

-- 1b. crm_stage_entry(org_id, stage_key) — the single stage config object
-- matching stage_key, or null if that key isn't in the org's config.
create or replace function public.crm_stage_entry(p_org_id uuid, p_stage_key text)
returns jsonb
language sql
security definer
stable
set search_path = public
as $$
  select stage
  from jsonb_array_elements(public.crm_stage_config(p_org_id)) as stage
  where stage ->> 'key' = p_stage_key
  limit 1;
$$;

-- 1c. crm_follow_up_cadence_days(org_id) — the org's [day, day, ...]
-- follow-up schedule from config, defaulting to [2, 5] (today's live
-- behavior) if unset or malformed.
create or replace function public.crm_follow_up_cadence_days(p_org_id uuid)
returns int[]
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(
    (
      select array_agg((x)::int order by ordinality)
      from jsonb_array_elements_text(
        (select tm.config -> 'follow_up_cadence_days'
         from public.tenant_modules tm
         where tm.org_id = p_org_id and tm.module_key = 'crm'
         limit 1)
      ) with ordinality as t(x, ordinality)
    ),
    array[2, 5]
  );
$$;

-- ============================================================================
-- 2. Seed the stage config. StructTech's list is copied verbatim from the
-- live hardcoded values in deal_stage_side_effects() today (cancel_pending
-- follow_ups = true for every stage past new_scan/contacted, matching the
-- current `in ('call_booked','call_done','proposal_sent','negotiating',
-- 'closed_won','closed_lost')` check) — this migration changes WHERE that
-- rule lives, not what it does for StructTech. BMR's list is new, per
-- product decision (New Lead -> Qualified -> Site Visit -> Estimate
-- Presented -> Won/Lost); cancel_pending_follow_ups defaults to true for
-- every stage past the first (mirrors StructTech's "cancel once actively
-- engaged" shape) — tunable later purely as config, no code change, since
-- that's the entire point of this migration.
--
-- Caveat: the BMR update targets "the" contractor-type org. Correct today
-- (BMR is the only one), but will need revisiting — targeting by org_id,
-- not tenant_type — once a second contractor client exists.
-- ============================================================================
do $$
begin
  if not exists (
    select 1 from public.tenant_modules tm
    join public.organizations o on o.id = tm.org_id
    where o.tenant_type = 'internal' and tm.module_key = 'crm'
  ) then
    raise exception 'crm_stage_config seed: no crm tenant_modules row for the internal org';
  end if;

  if not exists (
    select 1 from public.tenant_modules tm
    join public.organizations o on o.id = tm.org_id
    where o.tenant_type = 'contractor' and tm.module_key = 'crm'
  ) then
    raise exception 'crm_stage_config seed: no crm tenant_modules row for a contractor org';
  end if;
end $$;

update public.tenant_modules tm
set config = tm.config || jsonb_build_object(
  'stages', jsonb_build_array(
    jsonb_build_object('key', 'new_scan',      'label', 'New Scan',      'cancel_pending_follow_ups', false, 'outcome', null),
    jsonb_build_object('key', 'contacted',     'label', 'Contacted',     'cancel_pending_follow_ups', false, 'outcome', null),
    jsonb_build_object('key', 'call_booked',   'label', 'Call Booked',   'cancel_pending_follow_ups', true,  'outcome', null),
    jsonb_build_object('key', 'call_done',     'label', 'Call Done',     'cancel_pending_follow_ups', true,  'outcome', null),
    jsonb_build_object('key', 'proposal_sent', 'label', 'Proposal Sent', 'cancel_pending_follow_ups', true,  'outcome', null),
    jsonb_build_object('key', 'negotiating',   'label', 'Negotiating',   'cancel_pending_follow_ups', true,  'outcome', null),
    jsonb_build_object('key', 'closed_won',    'label', 'Won',           'cancel_pending_follow_ups', true,  'outcome', 'won'),
    jsonb_build_object('key', 'closed_lost',   'label', 'Lost',          'cancel_pending_follow_ups', true,  'outcome', 'lost')
  ),
  'follow_up_cadence_days', jsonb_build_array(2, 5)
),
    updated_at = now()
from public.organizations o
where tm.org_id = o.id
  and o.tenant_type = 'internal'
  and tm.module_key = 'crm';

update public.tenant_modules tm
set config = tm.config || jsonb_build_object(
  'stages', jsonb_build_array(
    jsonb_build_object('key', 'new_lead',            'label', 'New Lead',            'cancel_pending_follow_ups', false, 'outcome', null),
    jsonb_build_object('key', 'qualified',           'label', 'Qualified',           'cancel_pending_follow_ups', true,  'outcome', null),
    jsonb_build_object('key', 'site_visit',          'label', 'Site Visit',          'cancel_pending_follow_ups', true,  'outcome', null),
    jsonb_build_object('key', 'estimate_presented',  'label', 'Estimate Presented',  'cancel_pending_follow_ups', true,  'outcome', null),
    jsonb_build_object('key', 'won',                 'label', 'Won',                 'cancel_pending_follow_ups', true,  'outcome', 'won'),
    jsonb_build_object('key', 'lost',                'label', 'Lost',                'cancel_pending_follow_ups', true,  'outcome', 'lost')
  ),
  'follow_up_cadence_days', jsonb_build_array(2, 5)
),
    updated_at = now()
from public.organizations o
where tm.org_id = o.id
  and o.tenant_type = 'contractor'
  and tm.module_key = 'crm';

-- ============================================================================
-- 3a. deal_stage_side_effects() — rewritten to read cancel_pending_follow_ups
-- / outcome from the deal's org's stage config instead of hardcoded stage
-- lists. The create_engagement_from_roadmap() call is now gated on
-- outcome='won' AND tenant_type='internal' — today it fires on any
-- closed_won deal with no tenant check, which is harmless only because no
-- BMR deal has ever reached that stage (create_engagement_from_roadmap()
-- requires a client_roadmaps row, which BMR deals will never have; the
-- call is wrapped in `exception when others`, so it wouldn't crash, but it
-- would silently log a bogus engagement_materialize_failed activity row on
-- every BMR "Won" once BMR starts using this table). Fixed here before
-- that becomes live.
-- ============================================================================
create or replace function public.deal_stage_side_effects()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_stage_entry jsonb;
  v_org_tenant_type text;
begin
  if new.stage <> old.stage then
    insert into public.deal_activity (deal_id, org_id, action, from_value, to_value)
    values (new.id, new.org_id, 'stage_changed', old.stage, new.stage);

    v_stage_entry := public.crm_stage_entry(new.org_id, new.stage);

    if coalesce((v_stage_entry ->> 'cancel_pending_follow_ups')::boolean, false) then
      update public.follow_ups set status = 'cancelled'
      where deal_id = new.id and status = 'pending';
    end if;

    if (v_stage_entry ->> 'outcome') in ('won', 'lost') then
      new.closed_at := now();
    end if;

    if (v_stage_entry ->> 'outcome') = 'won' then
      select o.tenant_type into v_org_tenant_type
      from public.organizations o
      where o.id = new.org_id;

      if v_org_tenant_type = 'internal' then
        begin
          perform public.create_engagement_from_roadmap(new.id);
        exception when others then
          insert into public.deal_activity (deal_id, org_id, action, to_value)
          values (new.id, new.org_id, 'engagement_materialize_failed', sqlerrm);
        end;
      end if;
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$function$;

-- ============================================================================
-- 3b. auto_create_deal() — now stamps org_id = StructTech's internal org
-- (previously left null; Stage 0's backfill covered existing rows, this
-- covers every new one going forward) and reads the follow-up day offsets
-- from crm_follow_up_cadence_days() instead of hardcoded '2 days'/'5 days'
-- intervals. Copy/wording is untouched — this is a StructTech-scan-only
-- trigger (audit_leads is StructTech's public intake), so its email
-- templates staying scan-specific is correct, not a gap.
-- ============================================================================
create or replace function public.auto_create_deal()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  d_id uuid;
  v_org_id uuid;
  v_cadence int[];
begin
  select id into v_org_id
  from public.organizations
  where tenant_type = 'internal'
  order by created_at asc
  limit 1;

  insert into public.deals (org_id, lead_id, contact_name, company, email, trade, crew_size, stage, source)
  values (v_org_id, new.id, coalesce(new.name,'—'), new.company, new.email, new.trade, new.crew_size, 'new_scan', 'scan')
  returning id into d_id;

  insert into public.deal_activity (deal_id, org_id, action, to_value) values (d_id, v_org_id, 'created', 'from scan');

  -- follow-up sequence (only if we have an email)
  if new.email is not null and new.email like '%@%' then
    v_cadence := public.crm_follow_up_cadence_days(v_org_id);
    if coalesce(array_length(v_cadence, 1), 0) < 2 then
      v_cadence := array[2, 5];
    end if;

    insert into public.follow_ups (deal_id, org_id, send_at, to_email, subject, body) values
    (d_id, v_org_id, now() + make_interval(days => v_cadence[1]), new.email,
     'Quick question about your Revenue Leak Report, ' || coalesce(split_part(new.name,' ',1),'') ,
     'Hey ' || coalesce(split_part(new.name,' ',1),'there') || E',\n\nJacob here from StructTech. Your scan flagged about $' || coalesce(new.monthly_leak,0) || E'/month leaking out of your operation — did the report line up with what you''re seeing day to day?\n\nIf you want to walk through it live, grab 30 minutes here: structtek.com/operational-audit\n\nNo pitch — just your numbers.\n\nJacob Walker\nStructTech LLC · 937.467.2660'),
    (d_id, v_org_id, now() + make_interval(days => v_cadence[2]), new.email,
     'The ' || coalesce(new.trade,'contractor') || ' math on $' || coalesce(new.monthly_leak,0) || '/month',
     'Hey ' || coalesce(split_part(new.name,' ',1),'there') || E',\n\nLast note from me. That $' || coalesce(new.monthly_leak,0) || E'/month your scan surfaced doesn''t fix itself — it compounds. Most crews your size get the first system live inside 30 days.\n\nIf now''s not the time, no sweat. If it is: structtek.com/operational-audit\n\nJacob');
    insert into public.deal_activity (deal_id, org_id, action, to_value)
    values (d_id, v_org_id, 'followup_scheduled', 'day-' || v_cadence[1] || ' + day-' || v_cadence[2]);
  end if;

  return new;
end $function$;

-- ============================================================================
-- 4a. create_deal(...) — the pipeline's insert RPC (rule 3: all inserts go
-- through security-definer RPCs). Org-scoped from the caller's own
-- membership, not a caller-supplied trust assumption. Sets the deal's
-- initial stage to the org's configured first stage (index 0) rather than
-- a hardcoded value, so this one RPC serves both StructTech's own
-- manually-added deals (referrals, per EXISTING_CRM_SCHEMA.md) and BMR's
-- pipeline. Schedules follow-ups on the same config-driven cadence as
-- auto_create_deal(), with generic (non-scan-specific) copy.
-- ============================================================================
create or replace function public.create_deal(
  p_org_id uuid,
  p_contact_name text,
  p_company text default null,
  p_email text default null,
  p_phone text default null,
  p_value numeric default null,
  p_trade text default null,
  p_crew_size int default null,
  p_source text default 'manual'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deal_id uuid;
  v_first_stage text;
  v_cadence int[];
begin
  if p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of organization %', p_org_id;
  end if;

  select stages -> 0 ->> 'key'
  into v_first_stage
  from (select public.crm_stage_config(p_org_id) as stages) s;

  if v_first_stage is null then
    raise exception 'organization % has no crm stage config', p_org_id;
  end if;

  insert into public.deals (org_id, contact_name, company, email, phone, value, trade, crew_size, stage, source)
  values (p_org_id, p_contact_name, p_company, p_email, p_phone, p_value, p_trade, p_crew_size, v_first_stage, p_source)
  returning id into v_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, to_value)
  values (v_deal_id, p_org_id, 'created', p_source);

  if p_email is not null and p_email like '%@%' then
    v_cadence := public.crm_follow_up_cadence_days(p_org_id);
    if coalesce(array_length(v_cadence, 1), 0) < 2 then
      v_cadence := array[2, 5];
    end if;

    insert into public.follow_ups (deal_id, org_id, send_at, to_email, subject, body) values
    (v_deal_id, p_org_id, now() + make_interval(days => v_cadence[1]), p_email,
     'Following up, ' || coalesce(split_part(p_contact_name,' ',1), ''),
     'Hey ' || coalesce(split_part(p_contact_name,' ',1),'there') || E',\n\nJust checking in on where things stand — happy to answer any questions.\n\n— StructTech'),
    (v_deal_id, p_org_id, now() + make_interval(days => v_cadence[2]), p_email,
     'Still here if you need anything',
     'Hey ' || coalesce(split_part(p_contact_name,' ',1),'there') || E',\n\nLast check-in from me for now — reach out whenever works.\n\n— StructTech');

    insert into public.deal_activity (deal_id, org_id, action, to_value)
    values (v_deal_id, p_org_id, 'followup_scheduled', 'day-' || v_cadence[1] || ' + day-' || v_cadence[2]);
  end if;

  return v_deal_id;
end;
$$;

comment on function public.create_deal(uuid, text, text, text, text, numeric, text, int, text) is
  'Pipeline insert RPC. Org-scoped from caller membership; stage defaults to the org''s configured first stage; schedules config-driven follow-ups (generic copy) if an email is given.';

-- ============================================================================
-- 4b. fetch_deal(id) — single-record fetch RPC (rule 4).
-- ============================================================================
create or replace function public.fetch_deal(p_deal_id uuid)
returns setof public.deals
language sql
security definer
stable
set search_path = public
as $$
  select d.*
  from public.deals d
  where d.id = p_deal_id
    and d.org_id in (select my_org_ids());
$$;

-- ============================================================================
-- 4c. update_deal_stage(id, stage) — validates the target stage is in the
-- deal's org's config before writing; deal_stage_side_effects() handles
-- everything else (activity log, follow-up cancellation, closed_at,
-- engagement creation) as a consequence of the UPDATE.
-- ============================================================================
create or replace function public.update_deal_stage(p_deal_id uuid, p_new_stage text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_stage_valid boolean;
begin
  select org_id into v_org_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  select exists (
    select 1
    from jsonb_array_elements(public.crm_stage_config(v_org_id)) as stage
    where stage ->> 'key' = p_new_stage
  ) into v_stage_valid;

  if not v_stage_valid then
    raise exception 'stage % is not configured for organization %', p_new_stage, v_org_id;
  end if;

  update public.deals set stage = p_new_stage where id = p_deal_id;
end;
$$;

-- ============================================================================
-- 4d. add_deal_note(id, content) — insert + activity log together (notes
-- are append-only, per SCOPE.md's North Star §12A).
-- ============================================================================
create or replace function public.add_deal_note(p_deal_id uuid, p_content text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_note_id uuid;
begin
  select org_id into v_org_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  insert into public.deal_notes (deal_id, org_id, content)
  values (p_deal_id, v_org_id, p_content)
  returning id into v_note_id;

  insert into public.deal_activity (deal_id, org_id, action, to_value)
  values (p_deal_id, v_org_id, 'note_added', left(p_content, 140));

  return v_note_id;
end;
$$;
