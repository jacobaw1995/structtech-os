-- CLASS B PROVENANCE: AN ACTIVITY ROW RECORDS A CHANGE, OR IT IS NOT WRITTEN.
-- Track S · 2026-09-27. §7.1 RULE 10. Owed since 2026-09-17, scheduled for the week of
-- 2026-09-21, not done until now.
-- Rollback: supabase/rollbacks/20260927_class_b_provenance_rollback.sql
-- Sweep: supabase/sweeps/provenance_stamp_sweep.sql (Class B, BREAKS 7 of 13).
--
-- THE RULE: A WRITE THAT CHANGES NO VALUE MUST NOT CHANGE WHO DECIDED IT, WHEN, OR HOW.
--
-- THE SEVEN, enumerated by property against LIVE pg_proc today rather than trusted from
-- the 2026-09-15 sweep file, and every one of them PROVED TO BREAK in a rolled-back
-- transaction as the synthetic tenant's real owner before this migration was written:
--   assign_deal_owner     re-assigning the SAME owner      owner_assigned  1 → 2   BREAKS
--   update_deal_fields    an EMPTY patch                   details_updated 0 → 1   BREAKS
--   complete_site_survey  same timestamp twice             activity        4 → 5   BREAKS
--   order_scope           same timestamp twice             activity        6 → 7   BREAKS
--   present_quote         same timestamp twice             activity        8 → 9   BREAKS
--   restore_deal          a deal that is NOT archived      restored        0 → 1   BREAKS
--   update_material_item  a re-submitted material row      — see below             BREAKS
--
-- AND THE SEVENTH FIRED IN GOLDEN PATH RUN 1, WHICH IS WHY THIS IS NO LONGER A CLASS
-- EXERCISE. Jacob's coordination screen showed five "changed a material after sign-off"
-- lines. THE FIRST OF THEM RECORDS NO CHANGE: from "Dumpster (qty 1)" to
-- "Dumpster (qty 1) [Tear-Off]" — same name, same quantity, no ready date either side,
-- the strings differing only because to_value appends the trade name. So the true count
-- of post-sign-off changes on that job is FOUR, not five, and the screen overstated the
-- dispute record by one. A change-after-sign-off log that records non-changes is not
-- evidence, for the same reason one that cannot name the actor is not evidence.
--
-- EVERY GUARD SITS AFTER THE AUTHORIZATION CHECKS, DELIBERATELY. If a no-op returned
-- early, before the permission test, the guard would become an ORACLE: a caller with no
-- right to assign an owner could learn whether a value would have changed by reading
-- which error came back. A no-op is still refused to someone who may not do it.
--
-- WHAT IS NOT IN THIS MIGRATION, and why, so the omission is a decision and not a gap:
--   · `updated_at`. Class C (31 functions) was RULED OUT OF SCOPE on 2026-09-17 except
--     for the two surfaces that render it to a person, both fixed in 20260918004138.
--     `deals.updated_at` is not one of them, so the UPDATEs below still stamp it and only
--     the ACTIVITY ROW is guarded — which is the definition of Class B.
--   · The 6 Class B functions graded SAFE (add_deal_note, add_material_item,
--     delete_material_item, auto_create_deal, create_deal, update_purchase_order_line):
--     each writes on a real insert, delete or distinct promise. Unchanged.
--   · `record_field_event`, which joined the population since the 2026-09-15 sweep
--     (17 activity-row writers today, 13 then). Graded by reading: a field event is an
--     event — every call records something that happened — so it is SAFE by construction,
--     the same grade as add_deal_note. Named here rather than left uncounted.
--
-- update_deal_fields COMPARES THE WHOLE ROW, NOT THE PATCH. An empty patch writes
-- nothing, and so does a patch that resends the values already stored — which is what a
-- prefilled form sends every time it is submitted (§7.1 rule 15's amendment: a
-- resubmitted value is not a deliberate write). Enumerating 22 column comparisons would
-- also have to reproduce this function's derived `contact_name` and its three text[]
-- branches, and would drift from them; a before/after snapshot cannot.
--
-- Every body below was machine-rewritten from its live pg_get_functiondef with a single
-- asserted substitution each, so signatures, grants, refusals and authorization logic are
-- byte-identical apart from the guards. No new function, no new table: nothing to revoke.

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

  -- CLASS B, 2026-09-27. RULE 10: re-assigning the owner who already owns this deal
  -- changes no value, so it must not record a new decision, a new actor or a new time.
  -- PLACED AFTER THE AUTHORIZATION CHECKS ON PURPOSE: a no-op must still be refused for
  -- a caller who may not assign, or the guard becomes an oracle — "did this change
  -- anything?" answerable by someone with no right to ask.
  if p_owner_id is not distinct from v_old_owner_id then
    return;
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
$function$;

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
  v_archived_at timestamptz;
begin
  select org_id, owner_id, archived_at into v_org_id, v_owner_id, v_archived_at from public.deals where id = p_deal_id;

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

  -- CLASS B: restoring a deal that is not archived changes no value. The mirror of
  -- archive_deal's Class A guard (20260916214749). Authorization is already past.
  if v_archived_at is null then
    return;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals set archived_at = null where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, actor_id)
  values (p_deal_id, v_org_id, 'restored', v_actor_id);
end;
$function$;

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
  v_existing timestamptz;
begin
  select org_id, owner_id, site_survey_complete_at into v_org_id, v_owner_id, v_existing from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (public.is_org_manager(v_org_id) or coalesce(v_owner_id = auth.uid(), false)) then
    raise exception 'not authorized: only the deal owner or an org manager can complete the site visit';
  end if;

  -- CLASS B: stamping site_survey_complete_at with the value it already holds changes no
  -- value, so it records no new decision. NULL-safe, and after authorization.
  if v_existing is not distinct from p_completed_at then
    return;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals
  set site_survey_complete_at = p_completed_at,
      updated_at = now()
  where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, to_value, actor_id)
  values (p_deal_id, v_org_id, 'site_survey_completed', coalesce(p_completed_at::text, 'cleared'), v_actor_id);
end;
$function$;

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
  v_existing timestamptz;
begin
  select org_id, owner_id, roof_scope_ordered_at into v_org_id, v_owner_id, v_existing from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (public.is_org_manager(v_org_id) or coalesce(v_owner_id = auth.uid(), false)) then
    raise exception 'not authorized: only the deal owner or an org manager can order scope';
  end if;

  -- CLASS B: stamping roof_scope_ordered_at with the value it already holds changes no
  -- value, so it records no new decision. NULL-safe, and after authorization.
  if v_existing is not distinct from p_ordered_at then
    return;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals
  set roof_scope_ordered_at = p_ordered_at,
      updated_at = now()
  where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, to_value, actor_id)
  values (p_deal_id, v_org_id, 'scope_ordered', coalesce(p_ordered_at::text, 'cleared'), v_actor_id);
end;
$function$;

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
  v_existing timestamptz;
begin
  select org_id, owner_id, quote_presented_at into v_org_id, v_owner_id, v_existing from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (public.is_org_manager(v_org_id) or coalesce(v_owner_id = auth.uid(), false)) then
    raise exception 'not authorized: only the deal owner or an org manager can present the quote';
  end if;

  -- CLASS B: stamping quote_presented_at with the value it already holds changes no
  -- value, so it records no new decision. NULL-safe, and after authorization.
  if v_existing is not distinct from p_presented_at then
    return;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals
  set quote_presented_at = p_presented_at,
      updated_at = now()
  where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, to_value, actor_id)
  values (p_deal_id, v_org_id, 'quote_presented', coalesce(p_presented_at::text, 'cleared'), v_actor_id);
end;
$function$;

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
  v_before jsonb;
  v_after jsonb;
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

  -- CLASS B. THE WHOLE ROW IS COMPARED, NOT THE PATCH — and that is deliberate.
  -- An empty patch writes nothing, but so does a patch that RESENDS the values already
  -- stored, which is what a prefilled form does every time it is submitted (§7.1
  -- rule 15's amendment: a resubmitted value is not a deliberate write). Enumerating 22
  -- column comparisons would also have to reproduce this function's derived
  -- `contact_name` and its three text[] branches; a before/after snapshot cannot drift
  -- from them.
  select to_jsonb(d) into v_before from public.deals d where d.id = p_deal_id;

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

  select to_jsonb(d) into v_after from public.deals d where d.id = p_deal_id;

  -- `updated_at` is excluded: it moves on every call and is NOT provenance here.
  -- Class C was ruled out of scope on 2026-09-17 except for the two surfaces that
  -- render it to a person, and `deals.updated_at` is not one of them. So the UPDATE
  -- above still stamps it; only the ACTIVITY ROW is guarded, which is what Class B is.
  if (v_before - 'updated_at') = (v_after - 'updated_at') then
    return;
  end if;

  insert into public.deal_activity (deal_id, org_id, action, actor_id)
  values (p_deal_id, v_org_id, 'details_updated', v_actor_id);
end;
$function$;

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

  -- CLASS B, AND THIS ONE FIRED IN GOLDEN PATH RUN 1. Of the three
  -- `material_updated_after_signoff` rows on Jacob's screen, the FIRST recorded no
  -- change at all: from "Dumpster (qty 1)" to "Dumpster (qty 1) [Tear-Off]" — same
  -- name, same quantity, no ready date on either side; the two strings differ only
  -- because to_value appends the trade. The material row's form resends its prefilled
  -- values, so submitting it without editing anything wrote a change-after-sign-off
  -- entry. A change log that records non-changes is not evidence.
  if v_sign_off_at is not null
     and (coalesce(p_name, v_old_name)         is distinct from v_old_name
       or coalesce(p_quantity, v_old_quantity) is distinct from v_old_quantity
       or coalesce(p_ready_by, v_old_ready_by) is distinct from v_old_ready_by) then
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
$function$;
