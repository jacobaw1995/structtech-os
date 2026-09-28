-- ROLLBACK for 20260927152418_one_name_per_person.
-- Restores the three functions to the bodies that read org_members.full_name with no
-- fallback, and drops the resolver. Written from the live pg_get_functiondef captured
-- BEFORE the migration applied.
--
-- READ THIS BEFORE RUNNING IT: this puts "Unknown", "a person whose name is not
-- recorded" and "a member" back on six surfaces, and puts assign_deal_owner back to
-- recording a real assignment as "Unassigned → Unassigned" whenever the membership
-- override is NULL. It exists so the change is reversible, not because reversing it is
-- safe.
--
-- ⚠ ORDERING, AND IT IS NOT OPTIONAL. `assign_deal_owner` was changed TWICE on
-- 2026-09-27 — by this migration (the name resolver) and then by
-- 20260927153148_class_b_provenance (the no-op guard). The body restored below predates
-- BOTH, so running this file ALONE also removes that function's Class B guard, silently.
-- Run 20260927_class_b_provenance_rollback.sql FIRST if you mean to undo both. If you
-- mean to undo only the name resolver, hand-merge: take the body below and re-add the
-- `if p_owner_id is not distinct from v_old_owner_id then return; end if;` guard.

CREATE OR REPLACE FUNCTION public.list_org_members(p_org_id uuid)
 RETURNS TABLE(user_id uuid, full_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$

;

CREATE OR REPLACE FUNCTION public.fetch_work_order_brief(p_work_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_org uuid; v_version text; v_today date; v_mine public.work_order_acknowledgments; v_my jsonb;
begin
  v_org := public.assert_work_order_level(p_work_order_id, 'trade');
  v_version := public.work_order_version(p_work_order_id);
  v_today := (now() at time zone 'America/New_York')::date;

  select * into v_mine from public.work_order_acknowledgments a
  where a.work_order_id = p_work_order_id and a.acknowledged_by = auth.uid()
  order by a.acknowledged_at desc limit 1;

  v_my := case
    when v_mine.id is null then jsonb_build_object('state', 'not_acknowledged')
    when v_mine.work_order_version = v_version
      then jsonb_build_object('state', 'acknowledged', 'acknowledged_at', v_mine.acknowledged_at)
    else jsonb_build_object('state', 'scope_changed_since', 'acknowledged_at', v_mine.acknowledged_at)
  end;

  return jsonb_build_object(
    'work_order_id', p_work_order_id,
    'today', v_today,
    'work_order_version', v_version,
    'objective', (select jsonb_build_object('body', o.body, 'objective_date', o.objective_date,
                           'published_at', o.published_at,
                           'published_by_name', (select m.full_name from public.org_members m
                                                 where m.org_id = o.org_id and m.user_id = o.published_by))
                  from public.work_order_objectives o
                  where o.work_order_id = p_work_order_id and o.objective_date = v_today),
    'my_acknowledgment', v_my,
    'acknowledgments', coalesce((
      select jsonb_agg(jsonb_build_object(
               'person', coalesce((select m.full_name from public.org_members m
                                   where m.org_id = a.org_id and m.user_id = a.acknowledged_by), 'a member'),
               'acknowledged_at', a.acknowledged_at,
               'state', case when a.work_order_version = v_version then 'current' else 'scope_changed_since' end)
             order by a.acknowledged_at desc)
      from public.work_order_acknowledgments a where a.work_order_id = p_work_order_id), '[]'::jsonb));
end;
$function$

;

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
$function$

;

drop function if exists public.member_display_name(uuid, uuid);
