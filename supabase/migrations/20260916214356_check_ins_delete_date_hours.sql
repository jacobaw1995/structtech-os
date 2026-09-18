-- CHECK-INS: WHO MAY DELETE ONE, WHAT DAY IT IS, AND A BLANK HOURS FIELD. Track S · 2026-09-16.
-- Rollback: supabase/rollbacks/20260916_check_ins_delete_date_hours_rollback.sql
--
-- (2a) DELETE. Found by Track X. "member delete own check_ins" was `org_id in my_org_ids()`, scoped PUBLIC:
-- "own" meant own ORG. PROVED BEFORE (rolled back): a synthetic `field` member in BMR saw 2 of 2 synthetic
-- check-ins, DELETEd one directly (rows=1) and the other through delete_check_in() — 0 of 2 left. The RPC
-- is SECURITY DEFINER and had the same gate as the policy, so closing the policy alone closes nothing.
-- A trade gate alone is ALSO an empty fix: work_order_is_my_trade() is "a trade work order in my org",
-- not "my work", and every check-in is on a trade. Nothing recorded who made a check-in, so "own" could not
-- be expressed. THE RULE BUILT: a check-in may be deleted by the person who created it, or by a member
-- holding view_master_work_order in its org.
--   ** view_master_work_order IS A PROXY FOR "MAY DELETE", NOT THE RIGHT CAPABILITY. ** It is the same
--   proxy the controller ruled for org-files DELETE on 2026-09-16: today it coincides with owner/admin/
--   agency_admin/office/member and excludes field and client_portal_viewer, and it will drift the day
--   someone grants a crew lead the master view. REPLACE BY 2026-10-07 (pilot) with a delete capability.
-- `created_by` is stamped by trigger from auth.uid() on insert and cannot be changed by an update, so it
-- cannot be forged through the direct-insert policy. 0 check-ins exist, so there is nothing to backfill;
-- a row written without a JWT carries NULL and only the office tier can delete it.
--
-- (2b) DATE. MEASURED: TimeZone = UTC (postgresql.conf; no role or database override). `current_date` is
-- the SESSION's date. PROVED BEFORE: the same create_check_in() call stamped 2026-09-16 under the session
-- zone UTC and 2026-09-17 under Pacific/Kiritimati while New York's date was 2026-09-16 — the function took
-- whatever zone the session had, and every weekday from 20:00 to 23:59 EDT that is tomorrow. The date is now
-- New York's. No tenant timezone column exists; America/New_York is the project's zone (CLAUDE.md), recorded
-- here as that assumption, not as a tenant setting.
--
-- (2b) HOURS. A blank hours field was written as 0 (coalesce and a column default). Crew hours are payroll;
-- 0 is a claim that nobody worked. `hours` is now NULL when not given — "not recorded" — and 0 stays a
-- legal typed value. Existing rows: 0, nothing to reinterpret. The deployed form omits p_hours when blank
-- (optionalNumber → undefined), so it now stores the state instead of the zero (rule 5b: compatible).
-- NOT CHANGED, NAMED: update_check_in() coalesces every field, so an hours value once typed cannot be put
-- back to "not recorded"; and "member update own check_ins" has the same any-member-in-the-org reach this
-- migration closes for delete.

alter table public.check_ins add column created_by uuid references auth.users(id) on delete set null;

create function public.check_ins_stamp_created_by()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
begin
  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
  else
    new.created_by := old.created_by;
  end if;
  return new;
end;
$function$;
revoke execute on function public.check_ins_stamp_created_by() from public, anon, authenticated;

create trigger check_ins_created_by before insert or update on public.check_ins
  for each row execute function public.check_ins_stamp_created_by();

alter table public.check_ins alter column check_in_date set default ((now() at time zone 'America/New_York')::date);
alter table public.check_ins alter column hours drop default;
alter table public.check_ins alter column hours drop not null;

drop policy "member delete own check_ins" on public.check_ins;
create policy "member delete check_ins author or office" on public.check_ins for delete
  to authenticated
  using (
    org_id in (select my_org_ids())
    and work_order_is_my_trade(work_order_id)
    and (coalesce(created_by = auth.uid(), false) or coalesce(can_view_master_work_order(org_id), false))
  );
alter policy "member insert own check_ins" on public.check_ins to authenticated;
alter policy "member read own check_ins" on public.check_ins to authenticated;
alter policy "member update own check_ins" on public.check_ins to authenticated;

drop function public.create_check_in(p_work_order_id uuid, p_crew_name text, p_schedule_block_id uuid, p_check_in_date date, p_hours numeric, p_materials_used text, p_blockers text);
create function public.create_check_in(p_work_order_id uuid, p_crew_name text, p_schedule_block_id uuid DEFAULT NULL::uuid, p_check_in_date date DEFAULT NULL::date, p_hours numeric DEFAULT NULL::numeric, p_materials_used text DEFAULT NULL::text, p_blockers text DEFAULT NULL::text)
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

create or replace function public.delete_check_in(p_check_in_id uuid)
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

  -- 2026-09-16: the same rule as the table policy. view_master_work_order is a PROXY (see the migration).
  if not (coalesce(v_created_by = auth.uid(), false) or coalesce(public.can_view_master_work_order(v_org_id), false)) then
    raise exception 'only the person who recorded this check-in, or the office, can delete it — ask the office to remove it';
  end if;

  delete from public.check_ins where id = p_check_in_id;
end;
$function$;
