-- StructTech OS — Phase A Week 1: assistant capability role, chunk 4 of 5.
--
-- NOT APPLIED. Author-only migration file — ask before applying.
--
-- Interaction 1 from the resolved design (roadmap "Assistant role —
-- capability flags (hide $)" / BACKLOG.md (c)): widen the C3 edit gate so
-- a capability-granted caller can edit ANY lead in the org, not just
-- leads she owns, WITHOUT promoting her to a manager role. She stays
-- 'member' — has_capability(org,'edit_leads') is a third OR-branch
-- alongside the existing is_org_manager / owner_id=auth.uid() checks, not
-- a role change.
--
-- All 6 functions below are CREATE OR REPLACE with UNCHANGED signatures —
-- pulled from LIVE pg_get_functiondef immediately before writing this
-- file (not from migration history, which drifted at least once already —
-- add_deal_note gained actor-stamping in a migration this feature's
-- earlier chunks never touched). Confirmed single overload each via
-- pg_get_function_identity_arguments. No drop-first needed.
--
-- ============================================================================
-- 1-5. The C3 edit gate, widened identically in all 5 deal-mutating RPCs
-- the design names. Old: is_org_manager(org) OR owner_id=auth.uid()
-- (already coalesce-guarded per the 7/26 NULL-authorization-gap fix). New:
-- OR has_capability(org, 'edit_leads'). assign_deal_owner is deliberately
-- NOT touched — reassigning ownership stays manager-only, per the
-- resolved design ("capabilities = see/change scope, ownership-reassignment
-- is a separate manager-only action").
-- ============================================================================

create or replace function public.update_deal_fields(p_deal_id uuid, p_patch jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_owner_id uuid;
  v_actor_id uuid;
  v_key text;
  v_allowed text[] := array[
    'contact_name', 'company', 'email', 'phone', 'value', 'trade', 'crew_size',
    'lead_type', 'project_address', 'billing_address', 'first_name', 'last_name',
    'secondary_phone', 'remodel_or_new_construction', 'existing_roof_type',
    'roof_type_requested', 'service_address_street', 'service_address_city',
    'service_address_state', 'service_address_zip', 'referral_name', 'tags'
  ];
begin
  select org_id, owner_id into v_org_id, v_owner_id
  from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (
    public.is_org_manager(v_org_id)
    or coalesce(v_owner_id = auth.uid(), false)
    or public.has_capability(v_org_id, 'edit_leads')
  ) then
    raise exception 'not authorized: only the deal owner, an org manager, or a caller with edit_leads can edit this deal';
  end if;

  for v_key in select jsonb_object_keys(p_patch) loop
    if not (v_key = any(v_allowed)) then
      raise exception 'field not writable via patch: %', v_key;
    end if;
  end loop;

  if p_patch ? 'value' and not public.has_capability(v_org_id, 'view_financials') then
    raise exception 'not authorized: view_financials capability required to write deal value';
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals
  set
    contact_name = case
      when p_patch ? 'contact_name' and nullif(trim(p_patch->>'contact_name'), '') is not null
        then trim(p_patch->>'contact_name')
      when p_patch ? 'contact_name' or p_patch ? 'first_name' or p_patch ? 'last_name' then
        coalesce(
          nullif(trim(concat_ws(' ',
            case when p_patch ? 'first_name' then p_patch->>'first_name' else first_name end,
            case when p_patch ? 'last_name' then p_patch->>'last_name' else last_name end
          )), ''),
          contact_name
        )
      else contact_name
    end,
    company = case when p_patch ? 'company' then p_patch->>'company' else company end,
    email = case when p_patch ? 'email' then p_patch->>'email' else email end,
    phone = case when p_patch ? 'phone' then p_patch->>'phone' else phone end,
    value = case when p_patch ? 'value' then nullif(p_patch->>'value', '')::numeric else value end,
    trade = case when p_patch ? 'trade' then p_patch->>'trade' else trade end,
    crew_size = case when p_patch ? 'crew_size' then nullif(p_patch->>'crew_size', '')::integer else crew_size end,
    lead_type = case when p_patch ? 'lead_type' then p_patch->>'lead_type' else lead_type end,
    project_address = case when p_patch ? 'project_address' then p_patch->>'project_address' else project_address end,
    billing_address = case when p_patch ? 'billing_address' then p_patch->>'billing_address' else billing_address end,
    first_name = case when p_patch ? 'first_name' then p_patch->>'first_name' else first_name end,
    last_name = case when p_patch ? 'last_name' then p_patch->>'last_name' else last_name end,
    secondary_phone = case when p_patch ? 'secondary_phone' then p_patch->>'secondary_phone' else secondary_phone end,
    remodel_or_new_construction = case when p_patch ? 'remodel_or_new_construction' then p_patch->>'remodel_or_new_construction' else remodel_or_new_construction end,
    existing_roof_type = case
      when not (p_patch ? 'existing_roof_type') then existing_roof_type
      when jsonb_typeof(p_patch->'existing_roof_type') = 'null' then null
      else (select coalesce(array_agg(x), array[]::text[]) from jsonb_array_elements_text(p_patch->'existing_roof_type') x)
    end,
    roof_type_requested = case
      when not (p_patch ? 'roof_type_requested') then roof_type_requested
      when jsonb_typeof(p_patch->'roof_type_requested') = 'null' then null
      else (select coalesce(array_agg(x), array[]::text[]) from jsonb_array_elements_text(p_patch->'roof_type_requested') x)
    end,
    service_address_street = case when p_patch ? 'service_address_street' then p_patch->>'service_address_street' else service_address_street end,
    service_address_city = case when p_patch ? 'service_address_city' then p_patch->>'service_address_city' else service_address_city end,
    service_address_state = case when p_patch ? 'service_address_state' then p_patch->>'service_address_state' else service_address_state end,
    service_address_zip = case when p_patch ? 'service_address_zip' then p_patch->>'service_address_zip' else service_address_zip end,
    referral_name = case when p_patch ? 'referral_name' then p_patch->>'referral_name' else referral_name end,
    tags = case
      when not (p_patch ? 'tags') then tags
      when jsonb_typeof(p_patch->'tags') = 'null' then null
      else (select coalesce(array_agg(x), array[]::text[]) from jsonb_array_elements_text(p_patch->'tags') x)
    end,
    updated_at = now()
  where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, actor_id)
  values (p_deal_id, v_org_id, 'details_updated', v_actor_id);
end;
$$;

create or replace function public.update_deal_stage(p_deal_id uuid, p_new_stage text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_owner_id uuid;
  v_stage_valid boolean;
begin
  select org_id, owner_id into v_org_id, v_owner_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (
    public.is_org_manager(v_org_id)
    or coalesce(v_owner_id = auth.uid(), false)
    or public.has_capability(v_org_id, 'edit_leads')
  ) then
    raise exception 'not authorized: only the deal owner, an org manager, or a caller with edit_leads can change stage';
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

create or replace function public.update_intake_checklist_field(p_deal_id uuid, p_field_path text[], p_value jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_owner_id uuid;
  v_intake jsonb;
  v_value jsonb;
begin
  if array_length(p_field_path, 1) is null or array_length(p_field_path, 1) not between 1 and 2 then
    raise exception 'p_field_path must have 1 or 2 elements, got %', p_field_path;
  end if;

  select org_id, owner_id, coalesce(intake_checklist, '{}'::jsonb)
  into v_org_id, v_owner_id, v_intake
  from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (
    public.is_org_manager(v_org_id)
    or coalesce(v_owner_id = auth.uid(), false)
    or public.has_capability(v_org_id, 'edit_leads')
  ) then
    raise exception 'not authorized: only the deal owner, an org manager, or a caller with edit_leads can edit this checklist';
  end if;

  v_value := coalesce(p_value, 'null'::jsonb);

  if array_length(p_field_path, 1) = 2 then
    v_intake := jsonb_set(
      v_intake,
      p_field_path[1:1],
      coalesce(v_intake -> p_field_path[1], '{}'::jsonb),
      true
    );
  end if;

  v_intake := jsonb_set(v_intake, p_field_path, v_value, true);

  update public.deals
  set intake_checklist = v_intake,
      updated_at = now()
  where id = p_deal_id;
end;
$$;

create or replace function public.archive_deal(p_deal_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_owner_id uuid;
  v_actor_id uuid;
begin
  select org_id, owner_id into v_org_id, v_owner_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (
    public.is_org_manager(v_org_id)
    or coalesce(v_owner_id = auth.uid(), false)
    or public.has_capability(v_org_id, 'edit_leads')
  ) then
    raise exception 'not authorized: only the deal owner, an org manager, or a caller with edit_leads can archive this deal';
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals set archived_at = now() where id = p_deal_id;

  update public.follow_ups set status = 'cancelled'
  where deal_id = p_deal_id and status = 'pending';

  insert into public.deal_activity (deal_id, org_id, action, actor_id)
  values (p_deal_id, v_org_id, 'archived', v_actor_id);
end;
$$;

create or replace function public.restore_deal(p_deal_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_owner_id uuid;
  v_actor_id uuid;
begin
  select org_id, owner_id into v_org_id, v_owner_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (
    public.is_org_manager(v_org_id)
    or coalesce(v_owner_id = auth.uid(), false)
    or public.has_capability(v_org_id, 'edit_leads')
  ) then
    raise exception 'not authorized: only the deal owner, an org manager, or a caller with edit_leads can restore this deal';
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals set archived_at = null where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, actor_id)
  values (p_deal_id, v_org_id, 'restored', v_actor_id);
end;
$$;

-- ============================================================================
-- 6. add_deal_note — new gate. Previously had NO authorization check beyond
-- org membership at all (any org member could add a note to any deal,
-- deliberately, per the 7/19 decision that notes are collaboration/
-- visibility, not state — see the C3 migration's header comment). Adding
-- has_capability(org,'add_notes') does not change that default: add_notes
-- defaults TRUE for member tier and is always TRUE for manager tier, so
-- every real caller today keeps working exactly as before. What changes is
-- that add_notes becomes a REAL enforcement point instead of a capability
-- key that exists in the design but nothing actually checks — without this,
-- setting permissions->'add_notes' to false on a future restricted user
-- would silently do nothing.
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

  if not public.has_capability(v_org_id, 'add_notes') then
    raise exception 'not authorized: add_notes capability required to add a note';
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

-- manage_users is NOT wired to anything in this migration. There is no
-- live RPC today that lets a non-platform-admin manage org members —
-- add_org_member is is_platform_admin()-gated (StructTech provisions
-- tenants; a client org owner has no self-service "invite a teammate" path
-- yet, confirmed by grep before writing this file). Same situation as the
-- `schedule` capability and the thin appointments surface: the capability
-- key resolves correctly via has_capability() today, but there is nothing
-- for it to guard until a user-management feature exists. Not building
-- that here — out of scope for this migration.
