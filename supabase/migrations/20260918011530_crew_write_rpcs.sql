-- A4.6 CREW MODEL — THE WRITE PATH. A person can be created, put on a crew and assigned to a work order from a
-- screen, not from SQL. Track S · 2026-09-17. Rollback: supabase/rollbacks/20260917_crew_write_rpcs_rollback.sql
--
-- BEFORE-MEASUREMENT (2026-09-17, excluding the synthetic tenant): crew_people 0 · crews 0 · crew_memberships 0 ·
-- work_order_crew_assignments 0 · unavailability 0 · work orders 3 (1 trade), **0 of 3 with a real assignee**
-- (assignee_type/assignee_ref NULL on all 3, 0 crew assignments) · schedule_blocks 1 (crew_name free text) ·
-- check_ins 0 · org_members 5, field 0.
--
-- WHO MAY WRITE: has_capability(org, 'schedule') — the SAME gate the table policies of 20260915221736 use, so
-- the RPC and the table cannot disagree. ** FLAGGED, NOT CHANGED: `field` AND `client_portal_viewer` hold
-- `schedule` by default (default_permissions_for_role), so a crew member — and a homeowner portal login — can
-- create people and crews, exactly as they can already write these tables directly. That is the existing
-- capability model, not a choice made here; it needs a ruling. **
-- HOUSE RULES APPLIED: every refusal is in words with a HINT code the UI can look up; an edit is a jsonb PATCH
-- where a key's PRESENCE means "set it" (so a value can be cleared — the defect of 2026-09-17's hours, not
-- repeated); a write that changes no value changes nothing (RULE 10; updated_at is maintained only on a real
-- change by crew_touch_updated_at); availability and vehicle are STATES returned to the caller, never a refusal
-- (A4.6 condition 3; §5 A4.6's "refuses" Done-when still awaits a ruling).

create function public.crew_assert_can_manage(p_org_id uuid)
returns void language plpgsql stable security definer set search_path to 'public'
as $function$
begin
  if p_org_id is null or p_org_id not in (select my_org_ids()) then
    raise exception 'not found or not accessible' using hint = 'not_found';
  end if;
  if not coalesce(public.has_capability(p_org_id, 'schedule'), false) then
    raise exception 'your role cannot manage crews in this workspace' using hint = 'no_schedule_capability';
  end if;
end;
$function$;
revoke execute on function public.crew_assert_can_manage(uuid) from public, anon, authenticated;

-- ---- people ----------------------------------------------------------------------------------------------
create function public.crew_check_login(p_org_id uuid, p_user_id uuid, p_person_id uuid)
returns void language plpgsql stable security definer set search_path to 'public'
as $function$
begin
  if p_user_id is null then return; end if;
  if not exists (select 1 from public.org_members where org_id = p_org_id and user_id = p_user_id) then
    raise exception 'that login is not a member of this workspace' using hint = 'login_not_member';
  end if;
  if exists (select 1 from public.crew_people where org_id = p_org_id and user_id = p_user_id
             and id is distinct from p_person_id) then
    raise exception 'that login already belongs to another person in this workspace' using hint = 'login_already_a_person';
  end if;
end;
$function$;
revoke execute on function public.crew_check_login(uuid, uuid, uuid) from public, anon, authenticated;

create function public.create_crew_person(p_org_id uuid, p_full_name text, p_phone text default null,
  p_preferred_language text default null, p_skills text[] default null, p_has_vehicle boolean default null,
  p_vehicle_note text default null, p_user_id uuid default null)
returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare v_id uuid;
begin
  perform public.crew_assert_can_manage(p_org_id);
  if nullif(btrim(p_full_name), '') is null then
    raise exception 'a person needs a name' using hint = 'name_required';
  end if;
  if p_preferred_language is not null and p_preferred_language !~ '^[a-z]{2,3}(-[A-Z]{2})?$' then
    raise exception 'language must be a code like "en" or "es-MX"' using hint = 'language_invalid';
  end if;
  perform public.crew_check_login(p_org_id, p_user_id, null);
  insert into public.crew_people (org_id, full_name, phone, preferred_language, skills, has_vehicle, vehicle_note,
                                  user_id, created_by)
  values (p_org_id, p_full_name, p_phone, p_preferred_language, p_skills, p_has_vehicle, p_vehicle_note,
          p_user_id, auth.uid())
  returning id into v_id;
  return v_id;
end;
$function$;

create function public.update_crew_person(p_person_id uuid, p_patch jsonb)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare v_cur public.crew_people; v_key text;
  v_allowed text[] := array['full_name','phone','preferred_language','skills','has_vehicle','vehicle_note','user_id'];
  v_skills text[]; v_user uuid;
begin
  select * into v_cur from public.crew_people where id = p_person_id;
  perform public.crew_assert_can_manage(v_cur.org_id);
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'nothing to change' using hint = 'patch_invalid';
  end if;
  for v_key in select jsonb_object_keys(p_patch) loop
    if not (v_key = any(v_allowed)) then
      raise exception 'field not writable: %', v_key using hint = 'patch_invalid';
    end if;
  end loop;
  if p_patch ? 'full_name' and nullif(btrim(p_patch ->> 'full_name'), '') is null then
    raise exception 'a person needs a name' using hint = 'name_required';
  end if;
  if p_patch ? 'preferred_language' and (p_patch ->> 'preferred_language') is not null
     and (p_patch ->> 'preferred_language') !~ '^[a-z]{2,3}(-[A-Z]{2})?$' then
    raise exception 'language must be a code like "en" or "es-MX"' using hint = 'language_invalid';
  end if;
  if p_patch ? 'skills' then
    if jsonb_typeof(p_patch -> 'skills') = 'array' then
      v_skills := array(select jsonb_array_elements_text(p_patch -> 'skills'));
    elsif jsonb_typeof(p_patch -> 'skills') = 'null' then
      v_skills := null;
    else
      raise exception 'skills must be a list' using hint = 'patch_invalid';
    end if;
  end if;
  if p_patch ? 'user_id' then
    v_user := (p_patch ->> 'user_id')::uuid;
    perform public.crew_check_login(v_cur.org_id, v_user, p_person_id);
  end if;

  -- Key PRESENT = set (JSON null clears); key ABSENT = leave. crew_touch_updated_at moves updated_at only on a change.
  update public.crew_people set
    full_name          = case when p_patch ? 'full_name' then p_patch ->> 'full_name' else full_name end,
    phone              = case when p_patch ? 'phone' then p_patch ->> 'phone' else phone end,
    preferred_language = case when p_patch ? 'preferred_language' then p_patch ->> 'preferred_language' else preferred_language end,
    skills             = case when p_patch ? 'skills' then v_skills else skills end,
    has_vehicle        = case when p_patch ? 'has_vehicle' then (p_patch ->> 'has_vehicle')::boolean else has_vehicle end,
    vehicle_note       = case when p_patch ? 'vehicle_note' then p_patch ->> 'vehicle_note' else vehicle_note end,
    user_id            = case when p_patch ? 'user_id' then v_user else user_id end
  where id = p_person_id;
end;
$function$;

create function public.set_crew_person_archived(p_person_id uuid, p_archived boolean)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare v_org uuid;
begin
  select org_id into v_org from public.crew_people where id = p_person_id;
  perform public.crew_assert_can_manage(v_org);
  -- RULE 10: archiving an archived person (or restoring a live one) writes nothing.
  update public.crew_people
  set archived_at = case when p_archived then now() else null end
  where id = p_person_id and (archived_at is null) = coalesce(p_archived, false);
end;
$function$;

create function public.delete_crew_person(p_person_id uuid)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare v_org uuid;
begin
  select org_id into v_org from public.crew_people where id = p_person_id;
  perform public.crew_assert_can_manage(v_org);
  -- Memberships and unavailability cascade. A person is not a record anything else points at.
  delete from public.crew_people where id = p_person_id;
end;
$function$;

-- ---- crews -----------------------------------------------------------------------------------------------
create function public.create_crew(p_org_id uuid, p_name text)
returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare v_id uuid;
begin
  perform public.crew_assert_can_manage(p_org_id);
  if nullif(btrim(p_name), '') is null then
    raise exception 'a crew needs a name' using hint = 'name_required';
  end if;
  if exists (select 1 from public.crews where org_id = p_org_id and archived_at is null
             and lower(btrim(name)) = lower(btrim(p_name))) then
    raise exception 'a crew called "%" already exists in this workspace', btrim(p_name) using hint = 'crew_name_taken';
  end if;
  insert into public.crews (org_id, name, created_by) values (p_org_id, p_name, auth.uid()) returning id into v_id;
  return v_id;
end;
$function$;

create function public.rename_crew(p_crew_id uuid, p_name text)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare v_cur public.crews;
begin
  select * into v_cur from public.crews where id = p_crew_id;
  perform public.crew_assert_can_manage(v_cur.org_id);
  if nullif(btrim(p_name), '') is null then
    raise exception 'a crew needs a name' using hint = 'name_required';
  end if;
  if btrim(p_name) = v_cur.name then return; end if;  -- RULE 10
  if v_cur.archived_at is null and exists (select 1 from public.crews where org_id = v_cur.org_id and archived_at is null
             and id <> p_crew_id and lower(btrim(name)) = lower(btrim(p_name))) then
    raise exception 'a crew called "%" already exists in this workspace', btrim(p_name) using hint = 'crew_name_taken';
  end if;
  update public.crews set name = p_name where id = p_crew_id;
end;
$function$;

create function public.set_crew_archived(p_crew_id uuid, p_archived boolean)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare v_cur public.crews;
begin
  select * into v_cur from public.crews where id = p_crew_id;
  perform public.crew_assert_can_manage(v_cur.org_id);
  if not coalesce(p_archived, false) and v_cur.archived_at is not null
     and exists (select 1 from public.crews where org_id = v_cur.org_id and archived_at is null and id <> p_crew_id
                 and lower(btrim(name)) = lower(btrim(v_cur.name))) then
    raise exception 'a live crew is already called "%" — rename one of them first', v_cur.name using hint = 'crew_name_taken';
  end if;
  update public.crews
  set archived_at = case when p_archived then now() else null end
  where id = p_crew_id and (archived_at is null) = coalesce(p_archived, false);  -- RULE 10
end;
$function$;

create function public.delete_crew(p_crew_id uuid)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare v_org uuid; v_n int;
begin
  select org_id into v_org from public.crews where id = p_crew_id;
  perform public.crew_assert_can_manage(v_org);
  select count(*) into v_n from public.work_order_crew_assignments where crew_id = p_crew_id;
  if v_n > 0 then
    raise exception 'this crew is assigned to % work order(s) — unassign it, or archive the crew instead', v_n
      using hint = 'crew_in_use';
  end if;
  delete from public.crews where id = p_crew_id;  -- memberships cascade
end;
$function$;

-- ---- membership ------------------------------------------------------------------------------------------
create function public.add_crew_member(p_crew_id uuid, p_person_id uuid, p_is_lead boolean default false)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare v_crew public.crews; v_person public.crew_people;
begin
  select * into v_crew from public.crews where id = p_crew_id;
  perform public.crew_assert_can_manage(v_crew.org_id);
  select * into v_person from public.crew_people where id = p_person_id and org_id = v_crew.org_id;
  if v_person.id is null then
    raise exception 'that person is not in this workspace' using hint = 'not_found';
  end if;
  if v_crew.archived_at is not null then
    raise exception 'crew "%" is archived — restore it first', v_crew.name using hint = 'crew_archived';
  end if;
  if v_person.archived_at is not null then
    raise exception '% is archived — restore them first', v_person.full_name using hint = 'person_archived';
  end if;
  insert into public.crew_memberships (crew_id, person_id, org_id, is_lead, created_by)
  values (p_crew_id, p_person_id, v_crew.org_id, coalesce(p_is_lead, false), auth.uid())
  on conflict (crew_id, person_id) do update set is_lead = excluded.is_lead
    where crew_memberships.is_lead is distinct from excluded.is_lead;  -- RULE 10
end;
$function$;

create function public.remove_crew_member(p_crew_id uuid, p_person_id uuid)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare v_org uuid;
begin
  select org_id into v_org from public.crews where id = p_crew_id;
  perform public.crew_assert_can_manage(v_org);
  delete from public.crew_memberships where crew_id = p_crew_id and person_id = p_person_id;
end;
$function$;

-- ---- availability ----------------------------------------------------------------------------------------
create function public.add_crew_person_unavailability(p_person_id uuid, p_starts_on date, p_ends_on date,
  p_reason text default null)
returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare v_org uuid; v_id uuid;
begin
  select org_id into v_org from public.crew_people where id = p_person_id;
  perform public.crew_assert_can_manage(v_org);
  if p_starts_on is null or p_ends_on is null or p_ends_on < p_starts_on then
    raise exception 'choose a first and last day, with the last on or after the first' using hint = 'dates_invalid';
  end if;
  insert into public.crew_person_unavailability (org_id, person_id, starts_on, ends_on, reason, created_by)
  values (v_org, p_person_id, p_starts_on, p_ends_on, p_reason, auth.uid())
  returning id into v_id;
  return v_id;
end;
$function$;

create function public.delete_crew_person_unavailability(p_unavailability_id uuid)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare v_org uuid;
begin
  select org_id into v_org from public.crew_person_unavailability where id = p_unavailability_id;
  perform public.crew_assert_can_manage(v_org);
  delete from public.crew_person_unavailability where id = p_unavailability_id;
end;
$function$;

-- ---- assignment to a work order --------------------------------------------------------------------------
create function public.assign_crew_to_work_order(p_work_order_id uuid, p_crew_id uuid, p_task text default null)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_crew public.crews; v_id uuid; v_state record;
begin
  select * into v_crew from public.crews where id = p_crew_id;
  perform public.crew_assert_can_manage(v_crew.org_id);
  if v_crew.archived_at is not null then
    raise exception 'crew "%" is archived — restore it first', v_crew.name using hint = 'crew_archived';
  end if;
  if not exists (select 1 from public.work_orders where id = p_work_order_id and org_id = v_crew.org_id) then
    raise exception 'work order not found or not accessible' using hint = 'not_found';
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
$function$;

create function public.unassign_crew_from_work_order(p_assignment_id uuid)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare v_org uuid;
begin
  select org_id into v_org from public.work_order_crew_assignments where id = p_assignment_id;
  perform public.crew_assert_can_manage(v_org);
  delete from public.work_order_crew_assignments where id = p_assignment_id;
end;
$function$;

-- ---- one read for the crew screen ------------------------------------------------------------------------
-- Every member may read crews (the table policies say so); the phone number is a crew member's own contact,
-- shown to the workspace that employs them.
create function public.fetch_crew_roster(p_org_id uuid)
returns jsonb language sql stable security definer set search_path to 'public'
as $function$
  select case when p_org_id in (select my_org_ids()) then jsonb_build_object(
    'people', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'full_name', p.full_name, 'phone', p.phone, 'preferred_language', p.preferred_language,
        'skills', p.skills, 'has_vehicle', p.has_vehicle, 'vehicle_note', p.vehicle_note,
        'has_login', p.user_id is not null, 'archived', p.archived_at is not null,
        'crew_ids', coalesce((select jsonb_agg(m.crew_id) from public.crew_memberships m where m.person_id = p.id), '[]'::jsonb),
        'unavailable', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'starts_on', u.starts_on,
                         'ends_on', u.ends_on, 'reason', u.reason) order by u.starts_on)
                         from public.crew_person_unavailability u
                         where u.person_id = p.id and u.ends_on >= (now() at time zone 'America/New_York')::date), '[]'::jsonb))
        order by p.archived_at nulls first, p.full_name)
      from public.crew_people p where p.org_id = p_org_id), '[]'::jsonb),
    'crews', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.name, 'archived', c.archived_at is not null,
        'members', coalesce((select jsonb_agg(jsonb_build_object('person_id', m.person_id, 'is_lead', m.is_lead)
                     order by m.is_lead desc) from public.crew_memberships m where m.crew_id = c.id), '[]'::jsonb),
        'assignments', coalesce((select jsonb_agg(jsonb_build_object('assignment_id', a.id, 'work_order_id', a.work_order_id,
                         'task', a.task)) from public.work_order_crew_assignments a where a.crew_id = c.id), '[]'::jsonb))
        order by c.archived_at nulls first, c.name)
      from public.crews c where c.org_id = p_org_id), '[]'::jsonb))
  end;
$function$;

revoke execute on function public.create_crew_person(uuid, text, text, text, text[], boolean, text, uuid) from public, anon;
revoke execute on function public.update_crew_person(uuid, jsonb) from public, anon;
revoke execute on function public.set_crew_person_archived(uuid, boolean) from public, anon;
revoke execute on function public.delete_crew_person(uuid) from public, anon;
revoke execute on function public.create_crew(uuid, text) from public, anon;
revoke execute on function public.rename_crew(uuid, text) from public, anon;
revoke execute on function public.set_crew_archived(uuid, boolean) from public, anon;
revoke execute on function public.delete_crew(uuid) from public, anon;
revoke execute on function public.add_crew_member(uuid, uuid, boolean) from public, anon;
revoke execute on function public.remove_crew_member(uuid, uuid) from public, anon;
revoke execute on function public.add_crew_person_unavailability(uuid, date, date, text) from public, anon;
revoke execute on function public.delete_crew_person_unavailability(uuid) from public, anon;
revoke execute on function public.assign_crew_to_work_order(uuid, uuid, text) from public, anon;
revoke execute on function public.unassign_crew_from_work_order(uuid) from public, anon;
revoke execute on function public.fetch_crew_roster(uuid) from public, anon;
grant execute on function public.create_crew_person(uuid, text, text, text, text[], boolean, text, uuid) to authenticated;
grant execute on function public.update_crew_person(uuid, jsonb) to authenticated;
grant execute on function public.set_crew_person_archived(uuid, boolean) to authenticated;
grant execute on function public.delete_crew_person(uuid) to authenticated;
grant execute on function public.create_crew(uuid, text) to authenticated;
grant execute on function public.rename_crew(uuid, text) to authenticated;
grant execute on function public.set_crew_archived(uuid, boolean) to authenticated;
grant execute on function public.delete_crew(uuid) to authenticated;
grant execute on function public.add_crew_member(uuid, uuid, boolean) to authenticated;
grant execute on function public.remove_crew_member(uuid, uuid) to authenticated;
grant execute on function public.add_crew_person_unavailability(uuid, date, date, text) to authenticated;
grant execute on function public.delete_crew_person_unavailability(uuid) to authenticated;
grant execute on function public.assign_crew_to_work_order(uuid, uuid, text) to authenticated;
grant execute on function public.unassign_crew_from_work_order(uuid) to authenticated;
grant execute on function public.fetch_crew_roster(uuid) to authenticated;
