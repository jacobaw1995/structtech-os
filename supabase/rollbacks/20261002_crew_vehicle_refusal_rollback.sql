-- ROLLBACK for 20261002_crew_vehicle_refusal. Written BEFORE the migration applied,
-- from the live pg_get_functiondef captured the same session.
--
-- READ THIS BEFORE RUNNING IT: it removes A4.6's refusal entirely. With it gone,
-- assign_crew_to_work_order returns vehicle_state as a STATE and refuses on nothing —
-- which is what it did before 2026-10-01, and which is correct behaviour for every tenant
-- with enforce_stage_gating OFF. Rolling back therefore changes NOTHING for any tenant
-- today (all four carry policy = '{}'), and changes the behaviour only for a tenant that
-- has deliberately turned enforcement on.
CREATE OR REPLACE FUNCTION public.assign_crew_to_work_order(p_work_order_id uuid, p_crew_id uuid, p_task text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_crew public.crews; v_id uuid; v_state record;
begin
  select * into v_crew from public.crews where id = p_crew_id;
  perform public.crew_assert_can_manage(v_crew.org_id);
  if v_crew.archived_at is not null then
    raise exception 'crew "%" is archived — restore it first', v_crew.name using hint = 'crew_archived';
  end if;
  if not exists (select 1 from public.work_orders where id = p_work_order_id and org_id = v_crew.org_id) then
    raise exception 'work order not found or not accessible' using hint = 'work_order_not_found';
  end if;
  -- work_order_crew_assignments_validate refuses a master or voided work order in words.
  insert into public.work_order_crew_assignments (org_id, work_order_id, crew_id, task, created_by)
  values (v_crew.org_id, p_work_order_id, p_crew_id, p_task, auth.uid())
  on conflict (work_order_id, crew_id) do update set task = excluded.task
    where work_order_crew_assignments.task is distinct from excluded.task  -- RULE 10
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.work_order_crew_assignments where work_order_id = p_work_order_id and crew_id = p_crew_id;
  end if;

  -- Availability and vehicle come back as STATES. Nothing here refuses a crew for either.
  select s.vehicle_state, s.availability_state, s.unavailable_members, s.members into v_state
  from public.crew_assignment_states s where s.assignment_id = v_id
  limit 1;
  return jsonb_build_object('assignment_id', v_id, 'members', v_state.members, 'vehicle_state', v_state.vehicle_state,
                            'availability_state', v_state.availability_state,
                            'unavailable_members', v_state.unavailable_members);
end;
$function$

;
