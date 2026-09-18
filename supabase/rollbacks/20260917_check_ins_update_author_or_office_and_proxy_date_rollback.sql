-- ROLLBACK for 20260917 check_ins_update_author_or_office_and_proxy_date. Restores the any-member update gate and
-- removes clear_check_in_hours() and the comments. (The 2026-10-07 date in the 9/16 files is what remains.)
comment on policy "org-files work order files insert" on storage.objects is null;
comment on policy "org-files work order files delete" on storage.objects is null;
comment on policy "member delete check_ins author or office" on public.check_ins is null;
comment on function public.delete_check_in(uuid) is null;
drop function if exists public.clear_check_in_hours(uuid);
drop policy if exists "member update check_ins author or office" on public.check_ins;
create policy "member update own check_ins" on public.check_ins for update to authenticated
  using ((org_id in (select my_org_ids())) and work_order_is_my_trade(work_order_id))
  with check ((org_id in (select my_org_ids())) and work_order_is_my_trade(work_order_id));
CREATE OR REPLACE FUNCTION public.update_check_in(p_check_in_id uuid, p_crew_name text DEFAULT NULL::text, p_check_in_date date DEFAULT NULL::date, p_hours numeric DEFAULT NULL::numeric, p_materials_used text DEFAULT NULL::text, p_blockers text DEFAULT NULL::text)
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

  update public.check_ins
  set crew_name = coalesce(p_crew_name, crew_name),
      check_in_date = coalesce(p_check_in_date, check_in_date),
      hours = coalesce(p_hours, hours),
      materials_used = coalesce(p_materials_used, materials_used),
      blockers = coalesce(p_blockers, blockers),
      updated_at = now()
  where id = p_check_in_id;
end;
$function$;
