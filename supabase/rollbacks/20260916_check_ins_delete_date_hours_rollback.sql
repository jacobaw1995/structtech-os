-- ROLLBACK for 20260916214356_check_ins_delete_date_hours. Restores the pre-2026-09-16 state exactly
-- (including the holes it closed). Run only if the migration must be undone.
drop trigger if exists check_ins_created_by on public.check_ins;
drop function if exists public.check_ins_stamp_created_by();

drop policy if exists "member delete check_ins author or office" on public.check_ins;
create policy "member delete own check_ins" on public.check_ins for delete
  using (org_id in (select my_org_ids()));
alter policy "member insert own check_ins" on public.check_ins to public;
alter policy "member read own check_ins" on public.check_ins to public;
alter policy "member update own check_ins" on public.check_ins to public;

update public.check_ins set hours = 0 where hours is null;
alter table public.check_ins alter column hours set default 0;
alter table public.check_ins alter column hours set not null;
alter table public.check_ins alter column check_in_date set default current_date;
alter table public.check_ins drop column if exists created_by;

drop function if exists public.create_check_in(uuid, text, uuid, date, numeric, text, text);
create function public.create_check_in(p_work_order_id uuid, p_crew_name text, p_schedule_block_id uuid DEFAULT NULL::uuid, p_check_in_date date DEFAULT CURRENT_DATE, p_hours numeric DEFAULT 0, p_materials_used text DEFAULT NULL::text, p_blockers text DEFAULT NULL::text)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_check_in_id uuid;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');

  insert into public.check_ins
    (org_id, work_order_id, schedule_block_id, crew_name, check_in_date, hours, materials_used, blockers)
  values
    (v_org_id, p_work_order_id, p_schedule_block_id, p_crew_name, coalesce(p_check_in_date, current_date), coalesce(p_hours, 0), p_materials_used, p_blockers)
  returning id into v_check_in_id;

  return v_check_in_id;
end;
$function$;
revoke execute on function public.create_check_in(uuid, text, uuid, date, numeric, text, text) from public, anon;
grant execute on function public.create_check_in(uuid, text, uuid, date, numeric, text, text) to authenticated;

create or replace function public.delete_check_in(p_check_in_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.check_ins where id = p_check_in_id;

  if v_org_id is null then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  delete from public.check_ins where id = p_check_in_id;
end;
$function$;
