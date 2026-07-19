-- StructTech OS — CRM Depth Stage 5, Track C1: finish owner assignment.
--
-- Context: docs/reference/STAGE5_GOLIVE_GATE.md, Track C1. deals.owner_id and
-- create_deal/update_deal_details's p_owner_id already existed; OwnerSelect
-- already rendered real org members (page.tsx already fetched org_members
-- directly). What was missing: a dedicated assignment path that logs a clear
-- activity row instead of routing through update_deal_details's generic
-- 'details_updated'.
--
-- Bug found while building this (in scope to fix, not a separate track):
-- updateDealOwner's "Unassigned" option submitted owner_id='', which the
-- action layer's optionalString() coerces to undefined, which
-- update_deal_details's `owner_id = coalesce(p_owner_id, owner_id)` then
-- leaves UNCHANGED — choosing "Unassigned" was a silent no-op. assign_deal_owner
-- takes p_owner_id as a plain (nullable) param and assigns it directly, no
-- coalesce, so explicit NULL actually clears it; the action layer is updated
-- alongside to pass real NULL instead of filtering '' to undefined.
--
-- ============================================================================
-- 1. list_org_members — org_members-backed (not profiles), matching the
--    resolution authorName()/RevisionHistory already use for actor names.
--    Explicit org-membership check (unlike crm_stage_config's unguarded
--    config lookup) since member names are the sensitive part here.
-- ============================================================================
create or replace function public.list_org_members(p_org_id uuid)
returns table(user_id uuid, full_name text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of organization %', p_org_id;
  end if;

  return query
    select om.user_id, om.full_name
    from public.org_members om
    where om.org_id = p_org_id
    order by om.full_name;
end;
$$;

-- ============================================================================
-- 2. assign_deal_owner — dedicated claim/reassign path. Logs 'owner_assigned'
--    with from_value/to_value as owner NAMES (not raw ids), actor_id stamped
--    per the C2 pattern. p_owner_id is nullable and assigned directly (no
--    coalesce) so passing NULL genuinely unassigns.
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
