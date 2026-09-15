-- ROLLBACK for 2026-09-14 schedule_gate_only_a_changed_fact.
-- Bodies captured from pg_get_functiondef() on the LIVE database 2026-09-14 BEFORE the change.
-- Signatures unchanged by the forward migration, so CREATE OR REPLACE restores both.
--
-- RESTORING THIS RE-OPENS: under enforce_stage_gating, any edit to a block already in
-- conflict — a crew rename, an end-date change — is refused, through the RPC (since A2.3,
-- 2026-09-03) and through a direct update (since 20260913140204), because the gate tested
-- the resulting row instead of whether the gated fact changed.

CREATE OR REPLACE FUNCTION public.schedule_blocks_ready_by_gate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_name text; v_ready date;
begin
  select name, ready_by into v_name, v_ready
  from public.material_items
  where work_order_id = new.work_order_id and ready_by is not null
  order by ready_by desc limit 1;

  new.ready_by_conflict := v_ready is not null and new.start_date < v_ready;
  new.ready_by_conflict_reason := case when new.ready_by_conflict
    then format('materials not ready until %s (%s)', v_ready, v_name) else null end;

  if new.ready_by_conflict and public.tenant_enforces_stage_gating(new.org_id) then
    raise exception '%. This workspace enforces stage gating, so the schedule block was not saved. Move the start date to % or later, or turn off enforce_stage_gating.',
      new.ready_by_conflict_reason, v_ready;
  end if;
  return new;
end;
$function$;
revoke execute on function public.schedule_blocks_ready_by_gate() from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.update_schedule_block(p_schedule_block_id uuid, p_crew_name text DEFAULT NULL::text, p_start_date date DEFAULT NULL::date, p_end_date date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid; v_work_order_id uuid; v_start_date date; v_end_date date;
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

  v_start_date := coalesce(p_start_date, v_start_date);
  v_end_date := coalesce(p_end_date, v_end_date);

  select name, ready_by into v_blocking_name, v_blocking_ready_by
  from public.material_items
  where work_order_id = v_work_order_id and ready_by is not null
  order by ready_by desc limit 1;

  v_conflict := v_blocking_ready_by is not null and v_start_date < v_blocking_ready_by;
  v_reason := case when v_conflict
    then format('materials not ready until %s (%s)', v_blocking_ready_by, v_blocking_name) else null end;

  if v_conflict and public.tenant_enforces_stage_gating(v_org_id) then
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
