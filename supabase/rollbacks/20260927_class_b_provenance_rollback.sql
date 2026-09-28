-- ROLLBACK for 20260927153148_class_b_provenance.
-- Restores the seven functions to their unguarded bodies, captured from live
-- pg_get_functiondef BEFORE the migration applied.
--
-- READ THIS BEFORE RUNNING IT: it re-opens all seven. Re-assigning the same owner, an
-- empty patch, re-stamping a milestone with the value it already holds, restoring a deal
-- that is not archived, and re-submitting an unchanged material row will each write an
-- activity row again — and on the coordination screen that means a change-after-sign-off
-- log that records non-changes.
--
-- assign_deal_owner is restored to the shape that ALREADY INCLUDES the 2026-09-27 name
-- resolver, because that migration applied first. Rolling THIS back does not roll that
-- back.

CREATE OR REPLACE FUNCTION public.assign_deal_owner(p_deal_id uuid, p_owner_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    or coalesce(v_old_owner_id is null and p_owner_id = auth.uid(), false)
  ) then
    raise exception 'not authorized: only an org manager can reassign; a rep may only claim an unowned lead to themselves';
  end if;

  if p_owner_id is not null and p_owner_id not in (
    select om.user_id from public.org_members om where om.org_id = v_org_id
  ) then
    raise exception 'owner % is not a member of organization %', p_owner_id, v_org_id;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  v_old_owner_name := public.member_display_name(v_org_id, v_old_owner_id);
  v_new_owner_name := public.member_display_name(v_org_id, p_owner_id);

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
$function$

;

CREATE OR REPLACE FUNCTION public.restore_deal(p_deal_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$

;

CREATE OR REPLACE FUNCTION public.complete_site_survey(p_deal_id uuid, p_completed_at timestamp with time zone DEFAULT now())
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_owner_id uuid;
  v_actor_id uuid;
begin
  select org_id, owner_id into v_org_id, v_owner_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (public.is_org_manager(v_org_id) or coalesce(v_owner_id = auth.uid(), false)) then
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
$function$

;

CREATE OR REPLACE FUNCTION public.order_scope(p_deal_id uuid, p_ordered_at timestamp with time zone DEFAULT now())
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_owner_id uuid;
  v_actor_id uuid;
begin
  select org_id, owner_id into v_org_id, v_owner_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (public.is_org_manager(v_org_id) or coalesce(v_owner_id = auth.uid(), false)) then
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
$function$

;

CREATE OR REPLACE FUNCTION public.present_quote(p_deal_id uuid, p_presented_at timestamp with time zone DEFAULT now())
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_owner_id uuid;
  v_actor_id uuid;
begin
  select org_id, owner_id into v_org_id, v_owner_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (public.is_org_manager(v_org_id) or coalesce(v_owner_id = auth.uid(), false)) then
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
$function$

;

CREATE OR REPLACE FUNCTION public.update_deal_fields(p_deal_id uuid, p_patch jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$

;

CREATE OR REPLACE FUNCTION public.update_material_item(p_material_item_id uuid, p_name text DEFAULT NULL::text, p_quantity numeric DEFAULT NULL::numeric, p_ready_by date DEFAULT NULL::date, p_sort_order integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid; v_work_order_id uuid; v_trade text; v_master_id uuid; v_sign_off_at timestamptz;
  v_old_name text; v_old_quantity numeric; v_old_ready_by date; v_actor_id uuid;
  v_date_changed boolean;
begin
  select mi.org_id, mi.work_order_id, mi.name, mi.quantity, mi.ready_by
  into v_org_id, v_work_order_id, v_old_name, v_old_quantity, v_old_ready_by
  from public.material_items mi where mi.id = p_material_item_id;

  if v_org_id is null then
    raise exception 'material item not found or not accessible: %', p_material_item_id;
  end if;
  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'material item not found or not accessible: %', p_material_item_id;
  end if;

  select w.trade into v_trade from public.work_orders w where w.id = v_work_order_id;
  select s.master_id, s.sign_off_at into v_master_id, v_sign_off_at
  from public.job_master_sign_off(v_work_order_id) s;

  v_date_changed := p_ready_by is not null and p_ready_by is distinct from v_old_ready_by;

  update public.material_items
  set name = coalesce(p_name, name),
      quantity = coalesce(p_quantity, quantity),
      ready_by = coalesce(p_ready_by, ready_by),
      ready_by_source = case when v_date_changed then 'manual' else ready_by_source end,
      sort_order = coalesce(p_sort_order, sort_order),
      updated_at = now()
  where id = p_material_item_id;

  if v_date_changed then
    perform public.recompute_material_item_ready_by(p_material_item_id);
  end if;

  if v_sign_off_at is not null then
    select id into v_actor_id from public.profiles where id = auth.uid();
    insert into public.work_order_activity (work_order_id, org_id, action, from_value, to_value, actor_id)
    values (
      coalesce(v_master_id, v_work_order_id), v_org_id, 'material_updated_after_signoff',
      format('%s (qty %s%s)', v_old_name, v_old_quantity, case when v_old_ready_by is not null then ', ready ' || v_old_ready_by else '' end),
      format('%s (qty %s%s) [%s]', coalesce(p_name, v_old_name), coalesce(p_quantity, v_old_quantity), case when coalesce(p_ready_by, v_old_ready_by) is not null then ', ready ' || coalesce(p_ready_by, v_old_ready_by) else '' end, coalesce(v_trade, 'trade')),
      v_actor_id
    );
  end if;
end;
$function$

;
