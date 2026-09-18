-- ROLLBACK for 20260917 crew_name_is_a_crew. Restores the three RPCs exactly as they were before and removes the
-- crew reference. crew_name keeps whatever name was last derived, so no row loses its label.
drop function if exists public.create_check_in(uuid, text, uuid, date, numeric, text, text, uuid);
CREATE FUNCTION public.create_check_in(p_work_order_id uuid, p_crew_name text, p_schedule_block_id uuid DEFAULT NULL::uuid, p_check_in_date date DEFAULT NULL::date, p_hours numeric DEFAULT NULL::numeric, p_materials_used text DEFAULT NULL::text, p_blockers text DEFAULT NULL::text)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_check_in_id uuid;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');

  -- The date is New York's, never the session's (2026-09-16). A blank hours field is "not recorded" (NULL),
  -- never 0.
  insert into public.check_ins
    (org_id, work_order_id, schedule_block_id, crew_name, check_in_date, hours, materials_used, blockers)
  values
    (v_org_id, p_work_order_id, p_schedule_block_id, p_crew_name,
     coalesce(p_check_in_date, (now() at time zone 'America/New_York')::date),
     p_hours, p_materials_used, p_blockers)
  returning id into v_check_in_id;

  return v_check_in_id;
end;
$function$;
revoke execute on function public.create_check_in(uuid, text, uuid, date, numeric, text, text) from public, anon;
grant execute on function public.create_check_in(uuid, text, uuid, date, numeric, text, text) to authenticated;

drop function if exists public.update_schedule_block(uuid, text, date, date, uuid, boolean);
CREATE FUNCTION public.update_schedule_block(p_schedule_block_id uuid, p_crew_name text DEFAULT NULL::text, p_start_date date DEFAULT NULL::date, p_end_date date DEFAULT NULL::date)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid; v_work_order_id uuid; v_start_date date; v_end_date date;
  v_old_start_date date;
  v_blocking_name text; v_blocking_ready_by date; v_conflict boolean; v_reason text;
begin
  select org_id, work_order_id, start_date, end_date
  into v_org_id, v_work_order_id, v_start_date, v_end_date
  from public.schedule_blocks where id = p_schedule_block_id;

  if v_org_id is null then
    raise exception 'schedule block not found or not accessible: %', p_schedule_block_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'schedule block not found or not accessible: %', p_schedule_block_id;
  end if;

  if not public.has_capability(v_org_id, 'schedule') then
    raise exception 'your role cannot schedule work in this workspace';
  end if;

  v_old_start_date := v_start_date;
  v_start_date := coalesce(p_start_date, v_start_date);
  v_end_date := coalesce(p_end_date, v_end_date);

  select name, ready_by into v_blocking_name, v_blocking_ready_by
  from public.material_items
  where work_order_id = v_work_order_id and ready_by is not null
  order by ready_by desc limit 1;

  v_conflict := v_blocking_ready_by is not null and v_start_date < v_blocking_ready_by;
  v_reason := case when v_conflict
    then format('materials not ready until %s (%s)', v_blocking_ready_by, v_blocking_name) else null end;

  -- Gate only a CHANGED start date. A re-sent stored date is not a scheduling decision.
  if v_conflict
     and v_start_date is distinct from v_old_start_date
     and public.tenant_enforces_stage_gating(v_org_id) then
    raise exception '%. This workspace enforces stage gating, so the change was not saved. Move the start date to % or later, or turn off enforce_stage_gating.',
      v_reason, v_blocking_ready_by;
  end if;

  update public.schedule_blocks
  set crew_name = coalesce(p_crew_name, crew_name),
      start_date = v_start_date,
      end_date = v_end_date,
      ready_by_conflict = v_conflict,
      ready_by_conflict_reason = v_reason,
      updated_at = now()
  where id = p_schedule_block_id;
end;
$function$;
revoke execute on function public.update_schedule_block(uuid, text, date, date) from public, anon;
grant execute on function public.update_schedule_block(uuid, text, date, date) to authenticated;

drop function if exists public.add_schedule_block(uuid, text, date, date, uuid);
CREATE FUNCTION public.add_schedule_block(p_work_order_id uuid, p_crew_name text, p_start_date date, p_end_date date)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid; v_block_id uuid; v_blocking_name text; v_blocking_ready_by date;
  v_conflict boolean; v_reason text;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');

  if not public.has_capability(v_org_id, 'schedule') then
    raise exception 'your role cannot schedule work in this workspace';
  end if;

  select name, ready_by into v_blocking_name, v_blocking_ready_by
  from public.material_items
  where work_order_id = p_work_order_id and ready_by is not null
  order by ready_by desc limit 1;

  v_conflict := v_blocking_ready_by is not null and p_start_date < v_blocking_ready_by;
  v_reason := case when v_conflict
    then format('materials not ready until %s (%s)', v_blocking_ready_by, v_blocking_name) else null end;

  if v_conflict and public.tenant_enforces_stage_gating(v_org_id) then
    raise exception '%. This workspace enforces stage gating, so the schedule block was not saved. Move the start date to % or later, or turn off enforce_stage_gating.',
      v_reason, v_blocking_ready_by;
  end if;

  insert into public.schedule_blocks
    (org_id, work_order_id, crew_name, start_date, end_date, ready_by_conflict, ready_by_conflict_reason)
  values
    (v_org_id, p_work_order_id, p_crew_name, p_start_date, p_end_date, v_conflict, v_reason)
  returning id into v_block_id;

  return v_block_id;
end;
$function$;
revoke execute on function public.add_schedule_block(uuid, text, date, date) from public, anon;
grant execute on function public.add_schedule_block(uuid, text, date, date) to authenticated;

drop trigger if exists crews_carry_name on public.crews;
drop function if exists public.crews_carry_name();
drop trigger if exists schedule_blocks_crew_name on public.schedule_blocks;
drop trigger if exists check_ins_crew_name on public.check_ins;
drop function if exists public.crew_name_from_crew();
alter table public.check_ins drop column if exists crew_id;
alter table public.schedule_blocks drop column if exists crew_id;
