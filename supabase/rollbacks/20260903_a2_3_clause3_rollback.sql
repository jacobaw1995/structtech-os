-- ROLLBACK for 20260903180000_a2_3_ready_by_conflict_rename_and_tenant_stage_gating.sql
-- GENERATED BEFORE APPLYING, from pg_get_functiondef() on the live database.
-- Order matters: restore the function bodies AFTER renaming the columns back,
-- or the SQL-language body fails validation on first call (the deferred-
-- validation class this migration itself discovered).

alter table public.schedule_blocks rename column ready_by_conflict to blocked;
alter table public.schedule_blocks rename column ready_by_conflict_reason to blocked_reason;
alter table public.organizations drop column if exists policy;
drop function if exists public.tenant_enforces_stage_gating(uuid);

CREATE OR REPLACE FUNCTION public.add_schedule_block(p_work_order_id uuid, p_crew_name text, p_start_date date, p_end_date date)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid; v_block_id uuid; v_blocking_name text; v_blocking_ready_by date; v_blocked boolean; v_reason text;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');
  select name, ready_by into v_blocking_name, v_blocking_ready_by
  from public.material_items where work_order_id = p_work_order_id and ready_by is not null
  order by ready_by desc limit 1;
  v_blocked := v_blocking_ready_by is not null and p_start_date < v_blocking_ready_by;
  v_reason := case when v_blocked then format('blocked on %s (ready %s)', v_blocking_name, v_blocking_ready_by) else null end;
  insert into public.schedule_blocks (org_id, work_order_id, crew_name, start_date, end_date, blocked, blocked_reason)
  values (v_org_id, p_work_order_id, p_crew_name, p_start_date, p_end_date, v_blocked, v_reason)
  returning id into v_block_id;
  return v_block_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.update_schedule_block(p_schedule_block_id uuid, p_crew_name text DEFAULT NULL::text, p_start_date date DEFAULT NULL::date, p_end_date date DEFAULT NULL::date)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid; v_work_order_id uuid; v_start_date date; v_end_date date;
  v_blocking_name text; v_blocking_ready_by date; v_blocked boolean; v_reason text;
begin
  select org_id, work_order_id, start_date, end_date
  into v_org_id, v_work_order_id, v_start_date, v_end_date
  from public.schedule_blocks where id = p_schedule_block_id;
  if v_org_id is null then raise exception 'schedule block not found or not accessible: %', p_schedule_block_id; end if;
  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'schedule block not found or not accessible: %', p_schedule_block_id; end if;
  v_start_date := coalesce(p_start_date, v_start_date);
  v_end_date := coalesce(p_end_date, v_end_date);
  select name, ready_by into v_blocking_name, v_blocking_ready_by
  from public.material_items where work_order_id = v_work_order_id and ready_by is not null
  order by ready_by desc limit 1;
  v_blocked := v_blocking_ready_by is not null and v_start_date < v_blocking_ready_by;
  v_reason := case when v_blocked then format('blocked on %s (ready %s)', v_blocking_name, v_blocking_ready_by) else null end;
  update public.schedule_blocks
  set crew_name = coalesce(p_crew_name, crew_name), start_date = v_start_date, end_date = v_end_date,
      blocked = v_blocked, blocked_reason = v_reason, updated_at = now()
  where id = p_schedule_block_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.fetch_field_jobs(p_org_id uuid, p_today date DEFAULT CURRENT_DATE)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'schedule_block_id', j.id, 'work_order_id', j.work_order_id, 'crew_name', j.crew_name,
    'start_date', j.start_date, 'end_date', j.end_date,
    'blocked', j.blocked, 'blocked_reason', j.blocked_reason,
    'job_title', coalesce(nullif(j.company, ''), j.contact_name), 'site_address', j.site_address,
    'squares', j.squares, 'pitch', j.pitch) order by j.start_date, j.created_at), '[]'::jsonb)
  from (select sb.id, sb.work_order_id, sb.crew_name, sb.start_date, sb.end_date,
               sb.blocked, sb.blocked_reason, sb.created_at,
               e.company, e.contact_name, e.site_address, e.squares, e.pitch
        from public.schedule_blocks sb
        join public.work_orders w on w.id = sb.work_order_id
        join public.estimates e on e.id = w.estimate_id
        where sb.org_id = p_org_id and p_org_id in (select my_org_ids())
          and w.kind = 'trade' and w.voided_at is null and sb.end_date >= p_today
        order by sb.start_date, sb.created_at limit 20) j;
$function$;

revoke execute on function public.add_schedule_block(uuid, text, date, date) from public, anon;
revoke execute on function public.update_schedule_block(uuid, text, date, date) from public, anon;
revoke execute on function public.fetch_field_jobs(uuid, date) from public, anon;
