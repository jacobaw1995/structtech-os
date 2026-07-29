-- StructTech OS — Phase A Week 1: assistant capability role, chunk 2 of 5.
--
-- NOT APPLIED. Author-only migration file — ask before applying.
--
-- Interaction 3 from the resolved design (roadmap "Assistant role —
-- capability flags (hide $)" / BACKLOG.md (c)): a caller without
-- view_financials must never see or write `deals.value`. This chunk is the
-- READ half + the write-side blind-write guard on the one RPC that could
-- otherwise write it (update_deal_fields). It does NOT touch the C3
-- ownership/edit gate — that's chunk 4.
--
-- Both functions below are CREATE OR REPLACE with UNCHANGED signatures
-- (fetch_deal(uuid) -> setof deals, update_deal_fields(uuid, jsonb) ->
-- void) — confirmed against pg_proc immediately before writing this file,
-- no drop-first needed.
--
-- ============================================================================
-- 1. fetch_deal — strips the `value` key before populating the row when the
-- caller lacks view_financials, instead of listing every other deals
-- column by hand (which would silently go stale the next time a column is
-- added to deals, e.g. Stage 2's lead-data-model additions). The caller
-- sees value = NULL, not the real number — same "omit" contract as if the
-- column weren't selected at all.
-- ============================================================================
create or replace function public.fetch_deal(p_deal_id uuid)
returns setof public.deals
language sql
security definer
stable
set search_path = public
as $$
  select (
    jsonb_populate_record(
      null::public.deals,
      case
        when public.has_capability(d.org_id, 'view_financials') then to_jsonb(d)
        else to_jsonb(d) - 'value'
      end
    )
  ).*
  from public.deals d
  where d.id = p_deal_id
    and d.org_id in (select my_org_ids());
$$;

-- ============================================================================
-- 2. update_deal_fields — blind-write guard. The existing allowlist loop
-- already rejects any key outside the 22-column patch surface; this adds a
-- SECOND, narrower rejection specific to `value`: present in the allowlist
-- (so a privileged caller can still patch it) but rejected for a caller
-- without view_financials, so she can't write a field she can't read.
-- Placed after the allowlist loop so an actually-unknown key still raises
-- its own more specific error first; v_org_id is already resolved by the
-- existing authorization block above this.
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

  if not (public.is_org_manager(v_org_id) or coalesce(v_owner_id = auth.uid(), false)) then
    raise exception 'not authorized: only the deal owner or an org manager can edit this deal';
  end if;

  -- Allowlist enforcement — reject the whole patch on any unlisted key.
  for v_key in select jsonb_object_keys(p_patch) loop
    if not (v_key = any(v_allowed)) then
      raise exception 'field not writable via patch: %', v_key;
    end if;
  end loop;

  -- Financials gate (Phase A capability model, Interaction 3): `value` is
  -- on the allowlist above (so managers/privileged editors keep writing
  -- it), but a caller without view_financials is rejected specifically on
  -- this key even though she may be authorized to edit everything else on
  -- the deal — read access and write access to value travel together.
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
