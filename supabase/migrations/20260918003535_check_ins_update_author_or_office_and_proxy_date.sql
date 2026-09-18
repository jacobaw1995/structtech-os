-- CHECK-IN HOURS ARE PAYROLL: WHO MAY EDIT ONE, AND "NOT RECORDED" IS A STATE YOU CAN RETURN TO.
-- Plus the proxy's replacement date moves to 2026-11-01. Track S · 2026-09-17. Controller rulings 1a and 1d.
-- Rollback: supabase/rollbacks/20260917_check_ins_update_author_or_office_and_proxy_date_rollback.sql
--
-- (1d) NAMED 2026-09-16, NOT FIXED THEN; CLOSED NOW. "member update own check_ins" was org + trade only, and
-- update_check_in() (SECURITY DEFINER) had the same gate, so any member — crew included — could edit any
-- crew's hours. PROVED 2026-09-16 (rolled back): a synthetic crew member's UPDATE of another crew's check-in
-- touched 1 row. Live exposure: 0 check-ins, 0 field members in any client tenant.
-- THE RULE, the same as delete: the person who recorded the check-in (created_by), or a holder of
-- view_master_work_order — BOTH the table policy and update_check_in().
-- THE MISSING STATE: once hours were entered, nothing could set them back to "not recorded" (update_check_in
-- coalesces every argument, so NULL means "leave as is"). A zero would be a correction that claims nobody
-- worked. The fix is the state: clear_check_in_hours(check-in) sets hours to NULL, under the same gate.
-- update_check_in's signature and behaviour for everyone allowed are unchanged (rule 5b).
--
-- (1a) THE PROXY REPLACEMENT DATE IS 2026-11-01, NOT 2026-10-07. Controller: never change a permission model the
-- week a crew depends on it. 20260916214356 and 20260916214542 are left byte-identical to what ran (a
-- reconciled file records what ran); the date they carry is SUPERSEDED here, and the live objects carry the
-- new date as COMMENTs so a reader of the database sees it without the repo.

drop policy "member update own check_ins" on public.check_ins;
create policy "member update check_ins author or office" on public.check_ins for update
  to authenticated
  using (
    org_id in (select my_org_ids())
    and work_order_is_my_trade(work_order_id)
    and (coalesce(created_by = auth.uid(), false) or coalesce(can_view_master_work_order(org_id), false))
  )
  with check (
    org_id in (select my_org_ids())
    and work_order_is_my_trade(work_order_id)
    and (coalesce(created_by = auth.uid(), false) or coalesce(can_view_master_work_order(org_id), false))
  );

create or replace function public.update_check_in(p_check_in_id uuid, p_crew_name text DEFAULT NULL::text, p_check_in_date date DEFAULT NULL::date, p_hours numeric DEFAULT NULL::numeric, p_materials_used text DEFAULT NULL::text, p_blockers text DEFAULT NULL::text)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
  v_created_by uuid;
begin
  select org_id, work_order_id, created_by into v_org_id, v_work_order_id, v_created_by
  from public.check_ins where id = p_check_in_id;

  if v_org_id is null then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  -- 2026-09-17: hours are payroll. The author or the office tier (view_master_work_order — a PROXY, replace by 2026-11-01).
  if not (coalesce(v_created_by = auth.uid(), false) or coalesce(public.can_view_master_work_order(v_org_id), false)) then
    raise exception 'only the person who recorded this check-in, or the office, can change it — ask the office to correct it';
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

create function public.clear_check_in_hours(p_check_in_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
  v_created_by uuid;
begin
  select org_id, work_order_id, created_by into v_org_id, v_work_order_id, v_created_by
  from public.check_ins where id = p_check_in_id;

  if v_org_id is null then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;
  if not (coalesce(v_created_by = auth.uid(), false) or coalesce(public.can_view_master_work_order(v_org_id), false)) then
    raise exception 'only the person who recorded this check-in, or the office, can change it — ask the office to correct it';
  end if;

  -- "Not recorded" is NULL, a state — never 0. RULE 10: already not recorded changes nothing, so nothing is stamped.
  update public.check_ins set hours = null, updated_at = now()
  where id = p_check_in_id and hours is not null;
end;
$function$;
revoke execute on function public.clear_check_in_hours(uuid) from public, anon;
grant execute on function public.clear_check_in_hours(uuid) to authenticated;

comment on policy "member update check_ins author or office" on public.check_ins is
  'PROXY: view_master_work_order stands in for a check-in edit capability. REPLACE BY 2026-11-01 (controller, 2026-09-17).';
comment on policy "member delete check_ins author or office" on public.check_ins is
  'PROXY: view_master_work_order stands in for a check-in delete capability. REPLACE BY 2026-11-01 (controller, 2026-09-17; supersedes 2026-10-07 in 20260916214356).';
comment on policy "org-files work order files insert" on storage.objects is
  'PROXY: view_master_work_order stands in for a file-write capability. REPLACE BY 2026-11-01 (controller, 2026-09-17; supersedes 2026-10-07 in 20260916214542).';
comment on policy "org-files work order files delete" on storage.objects is
  'PROXY: view_master_work_order stands in for a file-delete capability. REPLACE BY 2026-11-01 (controller, 2026-09-17; supersedes 2026-10-07 in 20260916214542).';
comment on function public.delete_check_in(uuid) is
  'Author or view_master_work_order (PROXY). REPLACE BY 2026-11-01 (controller, 2026-09-17).';
