-- StructTech OS — CRM Depth Stage 5, Track C2: actor identity on every deal_activity write.
--
-- Context: docs/reference/STAGE5_GOLIVE_GATE.md, Track C2. deal_activity records
-- action/from_value/to_value/created_at but not who. RevisionHistory can say
-- "stage changed New Lead -> Site Visit" but never "Isaac changed...".
--
-- Findings from reading every RPC body live (7/19) — corrects two assumptions:
--   * update_deal_stage itself never writes deal_activity. The 'stage_changed'
--     row is written by the BEFORE UPDATE trigger deal_stage_side_effects()
--     (trg_deal_stage on public.deals) — that's what gets actor_id, not the RPC.
--   * complete_site_survey / order_scope / present_quote (the 3 milestone
--     timestamp RPCs) write NO deal_activity today — this migration adds the
--     insert (with actor_id), not just a stamp on an existing one, so these
--     milestones become visible in RevisionHistory for the first time.
-- Also stamps 2 RPCs not named in the plan but genuinely in scope ("every RPC
-- that writes deal_activity"): create_deal (created/followup_scheduled) and
-- add_deal_note (note_added — deal_notes.created_by was already stamped
-- Stage 4, but the activity row for it never was).
--
-- No RPC signature changes — actor comes from auth.uid() inside each function
-- body (session-level GUC, unaffected by SECURITY DEFINER's role switch), not
-- a new parameter. No DROP-then-CREATE needed; every function below is a
-- plain CREATE OR REPLACE with its existing signature.
--
-- actor_id is nullable and NULL-safe throughout, mirroring add_deal_note's
-- existing created_by pattern: `select id into v_actor_id from public.profiles
-- where id = auth.uid()` resolves to NULL if the caller has no profile row
-- (shouldn't happen post-Track-B1, but costs nothing to keep safe).

-- ============================================================================
-- 1. Column
-- ============================================================================
alter table public.deal_activity
  add column actor_id uuid references public.profiles(id);

-- ============================================================================
-- 2. add_deal_note — reuses the note's own v_created_by lookup as actor_id.
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
  v_created_by uuid;
begin
  select org_id into v_org_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  select id into v_created_by from public.profiles where id = auth.uid();

  insert into public.deal_notes (deal_id, org_id, content, created_by)
  values (p_deal_id, v_org_id, p_content, v_created_by)
  returning id into v_note_id;

  insert into public.deal_activity (deal_id, org_id, action, to_value, actor_id)
  values (p_deal_id, v_org_id, 'note_added', left(p_content, 140), v_created_by);

  return v_note_id;
end;
$$;

-- ============================================================================
-- 3. create_deal — stamps both activity rows it writes (created, followup_scheduled).
-- ============================================================================
create or replace function public.create_deal(p_org_id uuid, p_contact_name text DEFAULT NULL::text, p_company text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_value numeric DEFAULT NULL::numeric, p_trade text DEFAULT NULL::text, p_crew_size integer DEFAULT NULL::integer, p_source text DEFAULT 'manual'::text, p_lead_type text DEFAULT NULL::text, p_project_address text DEFAULT NULL::text, p_billing_address text DEFAULT NULL::text, p_first_name text DEFAULT NULL::text, p_last_name text DEFAULT NULL::text, p_secondary_phone text DEFAULT NULL::text, p_remodel_or_new_construction text DEFAULT NULL::text, p_existing_roof_type text[] DEFAULT NULL::text[], p_roof_type_requested text[] DEFAULT NULL::text[], p_service_address_street text DEFAULT NULL::text, p_service_address_city text DEFAULT NULL::text, p_service_address_state text DEFAULT NULL::text, p_service_address_zip text DEFAULT NULL::text, p_referral_name text DEFAULT NULL::text, p_owner_id uuid DEFAULT NULL::uuid, p_tags text[] DEFAULT NULL::text[])
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deal_id uuid;
  v_first_stage text;
  v_cadence int[];
  v_contact_name text;
  v_actor_id uuid;
begin
  if p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of organization %', p_org_id;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  v_contact_name := coalesce(
    nullif(trim(p_contact_name), ''),
    nullif(trim(concat_ws(' ', p_first_name, p_last_name)), '')
  );

  if v_contact_name is null then
    raise exception 'create_deal requires p_contact_name or p_first_name/p_last_name';
  end if;

  select stages -> 0 ->> 'key'
  into v_first_stage
  from (select public.crm_stage_config(p_org_id) as stages) s;

  if v_first_stage is null then
    raise exception 'organization % has no crm stage config', p_org_id;
  end if;

  insert into public.deals
    (org_id, contact_name, company, email, phone, value, trade, crew_size, stage, source,
     lead_type, project_address, billing_address,
     first_name, last_name, secondary_phone, remodel_or_new_construction,
     existing_roof_type, roof_type_requested,
     service_address_street, service_address_city, service_address_state, service_address_zip,
     referral_name, owner_id, tags)
  values
    (p_org_id, v_contact_name, p_company, p_email, p_phone, p_value, p_trade, p_crew_size, v_first_stage, p_source,
     p_lead_type, p_project_address, p_billing_address,
     p_first_name, p_last_name, p_secondary_phone, p_remodel_or_new_construction,
     p_existing_roof_type, p_roof_type_requested,
     p_service_address_street, p_service_address_city, p_service_address_state, p_service_address_zip,
     p_referral_name, p_owner_id, p_tags)
  returning id into v_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, to_value, actor_id)
  values (v_deal_id, p_org_id, 'created', p_source, v_actor_id);

  if p_email is not null and p_email like '%@%' then
    v_cadence := public.crm_follow_up_cadence_days(p_org_id);
    if coalesce(array_length(v_cadence, 1), 0) < 2 then
      v_cadence := array[2, 5];
    end if;

    insert into public.follow_ups (deal_id, org_id, send_at, to_email, subject, body) values
    (v_deal_id, p_org_id, now() + make_interval(days => v_cadence[1]), p_email,
     'Following up, ' || coalesce(split_part(v_contact_name,' ',1), ''),
     'Hey ' || coalesce(split_part(v_contact_name,' ',1),'there') || E',\n\nJust checking in on where things stand — happy to answer any questions.\n\n— StructTech'),
    (v_deal_id, p_org_id, now() + make_interval(days => v_cadence[2]), p_email,
     'Still here if you need anything',
     'Hey ' || coalesce(split_part(v_contact_name,' ',1),'there') || E',\n\nLast check-in from me for now — reach out whenever works.\n\n— StructTech');

    insert into public.deal_activity (deal_id, org_id, action, to_value, actor_id)
    values (v_deal_id, p_org_id, 'followup_scheduled', 'day-' || v_cadence[1] || ' + day-' || v_cadence[2], v_actor_id);
  end if;

  return v_deal_id;
end;
$$;

-- ============================================================================
-- 4. update_deal_details
-- ============================================================================
create or replace function public.update_deal_details(p_deal_id uuid, p_contact_name text DEFAULT NULL::text, p_company text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_value numeric DEFAULT NULL::numeric, p_trade text DEFAULT NULL::text, p_crew_size integer DEFAULT NULL::integer, p_lead_type text DEFAULT NULL::text, p_project_address text DEFAULT NULL::text, p_billing_address text DEFAULT NULL::text, p_first_name text DEFAULT NULL::text, p_last_name text DEFAULT NULL::text, p_secondary_phone text DEFAULT NULL::text, p_remodel_or_new_construction text DEFAULT NULL::text, p_existing_roof_type text[] DEFAULT NULL::text[], p_roof_type_requested text[] DEFAULT NULL::text[], p_service_address_street text DEFAULT NULL::text, p_service_address_city text DEFAULT NULL::text, p_service_address_state text DEFAULT NULL::text, p_service_address_zip text DEFAULT NULL::text, p_referral_name text DEFAULT NULL::text, p_owner_id uuid DEFAULT NULL::uuid, p_tags text[] DEFAULT NULL::text[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_derived_contact_name text;
  v_actor_id uuid;
begin
  select org_id into v_org_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  v_derived_contact_name := coalesce(
    nullif(trim(p_contact_name), ''),
    nullif(trim(concat_ws(' ', p_first_name, p_last_name)), '')
  );

  update public.deals
  set contact_name = coalesce(v_derived_contact_name, contact_name),
      company = coalesce(p_company, company),
      email = coalesce(p_email, email),
      phone = coalesce(p_phone, phone),
      value = coalesce(p_value, value),
      trade = coalesce(p_trade, trade),
      crew_size = coalesce(p_crew_size, crew_size),
      lead_type = coalesce(p_lead_type, lead_type),
      project_address = coalesce(p_project_address, project_address),
      billing_address = coalesce(p_billing_address, billing_address),
      first_name = coalesce(p_first_name, first_name),
      last_name = coalesce(p_last_name, last_name),
      secondary_phone = coalesce(p_secondary_phone, secondary_phone),
      remodel_or_new_construction = coalesce(p_remodel_or_new_construction, remodel_or_new_construction),
      existing_roof_type = coalesce(p_existing_roof_type, existing_roof_type),
      roof_type_requested = coalesce(p_roof_type_requested, roof_type_requested),
      service_address_street = coalesce(p_service_address_street, service_address_street),
      service_address_city = coalesce(p_service_address_city, service_address_city),
      service_address_state = coalesce(p_service_address_state, service_address_state),
      service_address_zip = coalesce(p_service_address_zip, service_address_zip),
      referral_name = coalesce(p_referral_name, referral_name),
      owner_id = coalesce(p_owner_id, owner_id),
      tags = coalesce(p_tags, tags),
      updated_at = now()
  where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, actor_id)
  values (p_deal_id, v_org_id, 'details_updated', v_actor_id);
end;
$$;

-- ============================================================================
-- 5. archive_deal
-- ============================================================================
create or replace function public.archive_deal(p_deal_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_actor_id uuid;
begin
  select org_id into v_org_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals set archived_at = now() where id = p_deal_id;

  update public.follow_ups set status = 'cancelled'
  where deal_id = p_deal_id and status = 'pending';

  insert into public.deal_activity (deal_id, org_id, action, actor_id)
  values (p_deal_id, v_org_id, 'archived', v_actor_id);
end;
$$;

-- ============================================================================
-- 6. restore_deal
-- ============================================================================
create or replace function public.restore_deal(p_deal_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_actor_id uuid;
begin
  select org_id into v_org_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals set archived_at = null where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, actor_id)
  values (p_deal_id, v_org_id, 'restored', v_actor_id);
end;
$$;

-- ============================================================================
-- 7. deal_stage_side_effects() — the actual writer of 'stage_changed', fired by
--    trg_deal_stage (BEFORE UPDATE ON deals). auth.uid() still resolves here:
--    it reads a session-level GUC set by PostgREST from the caller's JWT,
--    unaffected by this function's (or update_deal_stage's) SECURITY DEFINER.
-- ============================================================================
create or replace function public.deal_stage_side_effects()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stage_entry jsonb;
  v_org_tenant_type text;
  v_actor_id uuid;
begin
  if new.stage <> old.stage then
    select id into v_actor_id from public.profiles where id = auth.uid();

    insert into public.deal_activity (deal_id, org_id, action, from_value, to_value, actor_id)
    values (new.id, new.org_id, 'stage_changed', old.stage, new.stage, v_actor_id);

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
          insert into public.deal_activity (deal_id, org_id, action, to_value, actor_id)
          values (new.id, new.org_id, 'engagement_materialize_failed', sqlerrm, v_actor_id);
        end;
      end if;
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- ============================================================================
-- 8. complete_site_survey — was a bare timestamp write with NO activity log.
--    Now logs 'site_survey_completed' (to_value = new timestamp, or 'cleared'
--    for an explicit-null call) with actor_id.
-- ============================================================================
create or replace function public.complete_site_survey(
  p_deal_id uuid,
  p_completed_at timestamptz default now()
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_actor_id uuid;
begin
  select org_id into v_org_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals
  set site_survey_complete_at = p_completed_at,
      updated_at = now()
  where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, to_value, actor_id)
  values (p_deal_id, v_org_id, 'site_survey_completed', coalesce(p_completed_at::text, 'cleared'), v_actor_id);
end;
$$;

-- ============================================================================
-- 9. order_scope — same pattern, was a bare timestamp write.
-- ============================================================================
create or replace function public.order_scope(
  p_deal_id uuid,
  p_ordered_at timestamptz default now()
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_actor_id uuid;
begin
  select org_id into v_org_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals
  set roof_scope_ordered_at = p_ordered_at,
      updated_at = now()
  where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, to_value, actor_id)
  values (p_deal_id, v_org_id, 'scope_ordered', coalesce(p_ordered_at::text, 'cleared'), v_actor_id);
end;
$$;

-- ============================================================================
-- 10. present_quote — same pattern, was a bare timestamp write.
-- ============================================================================
create or replace function public.present_quote(
  p_deal_id uuid,
  p_presented_at timestamptz default now()
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_actor_id uuid;
begin
  select org_id into v_org_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals
  set quote_presented_at = p_presented_at,
      updated_at = now()
  where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, to_value, actor_id)
  values (p_deal_id, v_org_id, 'quote_presented', coalesce(p_presented_at::text, 'cleared'), v_actor_id);
end;
$$;
