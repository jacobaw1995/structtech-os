-- StructTech OS — CRM Depth Stage 5, Track C3: edit-by-ownership.
--
-- Context: docs/reference/STAGE5_GOLIVE_GATE.md, Track C3 (final Stage 5
-- go-live gate track). Authority = org_members.role (per-org, RLS-aligned),
-- not profiles.role (which stays the sales designation). Gate checked at
-- the top of every state-changing RPC; add_deal_note stays open to any org
-- member per the 7/19 decision (collaboration/visibility, not state).
--
-- All 10 functions below are CREATE OR REPLACE with UNCHANGED signatures —
-- confirmed live against pg_proc immediately before writing this migration.
-- No drop-first needed; the gate is purely internal to each function body.
--
-- Closed during review (7/21): update_deal_details still accepted p_owner_id
-- via its general coalesce update, which would have let a rep who owns a
-- deal give it away directly (bypassing assign_deal_owner's "no reassign/
-- give-away by reps" rule, since update_deal_details's own gate only checks
-- manager-or-current-owner, not which fields changed). owner_id is no longer
-- in that function's UPDATE SET at all; a non-null p_owner_id that differs
-- from the current owner now raises immediately, making assign_deal_owner
-- the sole ownership-change path. Normal edits pass p_owner_id null (the
-- app never sends it here — confirmed via grep) and are unaffected.
--
-- ============================================================================
-- 1. is_org_manager — same shape as is_platform_admin/is_staff (SQL, STABLE,
--    SECURITY DEFINER, search_path pinned from creation — never mutable).
-- ============================================================================
create or replace function public.is_org_manager(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.org_members
    where user_id = auth.uid()
      and org_id = p_org_id
      and role in ('owner', 'admin', 'agency_admin')
  );
$$;

-- ============================================================================
-- 2. update_deal_details — gate added; owner_id now fetched alongside org_id.
--    p_owner_id no longer writes owner_id at all — a differing value raises,
--    making assign_deal_owner the sole ownership-change path (see header).
-- ============================================================================
create or replace function public.update_deal_details(p_deal_id uuid, p_contact_name text DEFAULT NULL::text, p_company text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_value numeric DEFAULT NULL::numeric, p_trade text DEFAULT NULL::text, p_crew_size integer DEFAULT NULL::integer, p_lead_type text DEFAULT NULL::text, p_project_address text DEFAULT NULL::text, p_billing_address text DEFAULT NULL::text, p_first_name text DEFAULT NULL::text, p_last_name text DEFAULT NULL::text, p_secondary_phone text DEFAULT NULL::text, p_remodel_or_new_construction text DEFAULT NULL::text, p_existing_roof_type text[] DEFAULT NULL::text[], p_roof_type_requested text[] DEFAULT NULL::text[], p_service_address_street text DEFAULT NULL::text, p_service_address_city text DEFAULT NULL::text, p_service_address_state text DEFAULT NULL::text, p_service_address_zip text DEFAULT NULL::text, p_referral_name text DEFAULT NULL::text, p_owner_id uuid DEFAULT NULL::uuid, p_tags text[] DEFAULT NULL::text[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_owner_id uuid;
  v_derived_contact_name text;
  v_actor_id uuid;
begin
  select org_id, owner_id into v_org_id, v_owner_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (public.is_org_manager(v_org_id) or v_owner_id = auth.uid()) then
    raise exception 'not authorized: only the deal owner or an org manager can edit this deal';
  end if;

  if p_owner_id is not null and p_owner_id is distinct from v_owner_id then
    raise exception 'ownership changes must go through assign_deal_owner';
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
      tags = coalesce(p_tags, tags),
      updated_at = now()
  where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, actor_id)
  values (p_deal_id, v_org_id, 'details_updated', v_actor_id);
end;
$$;

-- ============================================================================
-- 3. update_deal_stage — gate added; owner_id now fetched.
-- ============================================================================
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

  if not (public.is_org_manager(v_org_id) or v_owner_id = auth.uid()) then
    raise exception 'not authorized: only the deal owner or an org manager can change stage';
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
-- 4. archive_deal — gate added; owner_id now fetched.
-- ============================================================================
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

  if not (public.is_org_manager(v_org_id) or v_owner_id = auth.uid()) then
    raise exception 'not authorized: only the deal owner or an org manager can archive this deal';
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
-- 5. restore_deal — gate added; owner_id now fetched.
-- ============================================================================
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

  if not (public.is_org_manager(v_org_id) or v_owner_id = auth.uid()) then
    raise exception 'not authorized: only the deal owner or an org manager can restore this deal';
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals set archived_at = null where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, actor_id)
  values (p_deal_id, v_org_id, 'restored', v_actor_id);
end;
$$;

-- ============================================================================
-- 6. update_intake_checklist_field — gate added; owner_id folded into the
--    existing org_id/intake_checklist select.
-- ============================================================================
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

  if not (public.is_org_manager(v_org_id) or v_owner_id = auth.uid()) then
    raise exception 'not authorized: only the deal owner or an org manager can edit this checklist';
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

-- ============================================================================
-- 7. complete_site_survey — gate added; owner_id now fetched.
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
  v_owner_id uuid;
  v_actor_id uuid;
begin
  select org_id, owner_id into v_org_id, v_owner_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (public.is_org_manager(v_org_id) or v_owner_id = auth.uid()) then
    raise exception 'not authorized: only the deal owner or an org manager can complete the site visit';
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
-- 8. order_scope — gate added; owner_id now fetched.
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
  v_owner_id uuid;
  v_actor_id uuid;
begin
  select org_id, owner_id into v_org_id, v_owner_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (public.is_org_manager(v_org_id) or v_owner_id = auth.uid()) then
    raise exception 'not authorized: only the deal owner or an org manager can order scope';
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
-- 9. present_quote — gate added; owner_id now fetched.
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
  v_owner_id uuid;
  v_actor_id uuid;
begin
  select org_id, owner_id into v_org_id, v_owner_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (public.is_org_manager(v_org_id) or v_owner_id = auth.uid()) then
    raise exception 'not authorized: only the deal owner or an org manager can present the quote';
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

-- ============================================================================
-- 10. assign_deal_owner — SPECIAL gate (not the general one): managers
--     reassign freely; a rep may only claim an unowned lead to themselves.
--     No reassign/give-away by reps, per the 7/19 decision.
-- ============================================================================
create or replace function public.assign_deal_owner(p_deal_id uuid, p_owner_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_old_owner_id uuid;
  v_old_owner_name text;
  v_new_owner_name text;
  v_actor_id uuid;
begin
  select org_id, owner_id into v_org_id, v_old_owner_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (
    public.is_org_manager(v_org_id)
    or (v_old_owner_id is null and p_owner_id = auth.uid())
  ) then
    raise exception 'not authorized: only an org manager can reassign; a rep may only claim an unowned lead to themselves';
  end if;

  if p_owner_id is not null and p_owner_id not in (
    select om.user_id from public.org_members om where om.org_id = v_org_id
  ) then
    raise exception 'owner % is not a member of organization %', p_owner_id, v_org_id;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  select full_name into v_old_owner_name from public.org_members
    where org_id = v_org_id and user_id = v_old_owner_id;
  select full_name into v_new_owner_name from public.org_members
    where org_id = v_org_id and user_id = p_owner_id;

  update public.deals
  set owner_id = p_owner_id,
      updated_at = now()
  where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, from_value, to_value, actor_id)
  values (
    p_deal_id, v_org_id, 'owner_assigned',
    coalesce(v_old_owner_name, 'Unassigned'),
    coalesce(v_new_owner_name, 'Unassigned'),
    v_actor_id
  );
end;
$$;
