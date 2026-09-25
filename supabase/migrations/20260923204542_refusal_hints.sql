-- A HINT IS A CONTRACT; A SENTENCE IS NOT. Track S · 2026-09-23. Controller ruling of this date.
-- Rollback: supabase/rollbacks/20260923_refusal_hints_rollback.sql
--
-- Track U measured it: across the paths classifyFieldError covers there are SEVEN distinct refusal messages
-- and exactly ONE carries a hint (crew_required) — so six refusals can only be told apart by their WORDING,
-- and two of the six had already been reworded since U wrote its patterns (`wrong_level`'s sentence lost the
-- words "trade work order" on 2026-09-22, and the hours sentence was rewritten when clearing became its own
-- action). src/lib/field/field-errors.ts still matches on prose: /requires a .* work order/i and
-- /not found or not accessible/i. A rewording is a silent reclassification.
--
-- BEFORE: 1 hint raised, of 7 refusals raised (field paths).  AFTER: 9 of 9 — the two QC refusals that the
-- same screen can produce are included, because the crew cannot tell which function refused them.
--
-- AND `not_found` WAS ONE CODE FOR FOUR DIFFERENT SENTENCES (crew paths), which is the same defect wearing
-- the opposite hat: four distinct facts collapsed into one word. Split, one code per fact.
--
-- WHAT IS DELIBERATELY *NOT* SPLIT: assert_work_order_level raises "work order not found or not accessible"
-- from TWO sites — the org test and the crew-cannot-see-a-master test — and both keep the SAME code
-- (work_order_not_found). Giving them different codes would rebuild the oracle 20260920005337 removed: a
-- crew member must not be able to tell "no such work order" from "a master you may not see".
--
-- NOTHING ELSE CHANGES. Every body below is the live definition read from the catalog by
-- pg_get_functiondef, with `using hint = '…'` added to a raise and nothing else touched; each replacement
-- was asserted to fire an exact number of times before this file was written.
--
-- THE CODES, each with the message it now carries:
--   check_in_not_found              "check-in not found or not accessible: %"
--   production_packet_not_found     "production packet not found or not accessible: %"
--   work_order_not_found            "work order not found or not accessible: %"        (both raise sites)
--   wrong_work_order_level          "work order % is kind=% — this action requires a % work order (%)"
--   delete_needs_author_or_office   "only the person who recorded this check-in, or the office, can delete it…"
--   change_needs_author_or_office   "only the person who recorded this check-in, or the office, can change it…"
--   not_signed_in                   "not signed in"                                    (both QC functions)
--   qc_work_order_not_recordable    "that work order is not one you can record against"
--   crew_required                   "choose a crew, or type who is doing the work"     (already carried it)
-- And the four that shared `not_found`:
--   workspace_not_accessible        crew_assert_can_manage's "not found or not accessible"
--   crew_person_not_found           "that person is not in this workspace"
--   work_order_not_found            assign_crew_to_work_order's "work order not found or not accessible"
--   crew_not_found                  "that crew is not in this workspace"
--
-- ROUTED TO TRACK U: classifyFieldError can now switch on error.hint and keep the prose match only as a
-- fallback for a database that answered without one. The codes above are the contract.

CREATE OR REPLACE FUNCTION public.assert_work_order_level(p_work_order_id uuid, p_expected_kind text)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_kind   text;
begin
  select w.org_id, w.kind into v_org_id, v_kind
  from public.work_orders w
  where w.id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id
      using hint = 'work_order_not_found';
  end if;

  -- 2026-09-19: the same test work_orders' restrictive guard applies. A caller who could not see this work
  -- order is told it is not there — never its kind, which is the fact the guard hides.
  if coalesce(v_kind, '') <> 'trade' and not coalesce(public.can_view_master_work_order(v_org_id), false) then
    raise exception 'work order not found or not accessible: %', p_work_order_id
      using hint = 'work_order_not_found';
  end if;

  if coalesce(v_kind, '') <> p_expected_kind then
    raise exception 'work order % is kind=% — this action requires a % work order (%)',
      p_work_order_id,
      coalesce(v_kind, '(null)'),
      p_expected_kind,
      case p_expected_kind
        when 'trade'  then 'materials, schedule blocks, check-ins and production packets attach to trades, not to the master'
        when 'master' then 'sign-off and agreements are recorded once on the master, not per trade'
        else 'unexpected level'
      end
      using hint = 'wrong_work_order_level';
  end if;

  return v_org_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.add_check_in_photo(p_check_in_id uuid, p_photo_data_url text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.check_ins where id = p_check_in_id;

  if v_org_id is null then
    raise exception 'check-in not found or not accessible: %', p_check_in_id
      using hint = 'check_in_not_found';
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'check-in not found or not accessible: %', p_check_in_id
      using hint = 'check_in_not_found';
  end if;

  update public.check_ins
  set photos = array_append(photos, p_photo_data_url),
      updated_at = now()
  where id = p_check_in_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.remove_check_in_photo(p_check_in_id uuid, p_photo_data_url text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.check_ins where id = p_check_in_id;

  if v_org_id is null then
    raise exception 'check-in not found or not accessible: %', p_check_in_id
      using hint = 'check_in_not_found';
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'check-in not found or not accessible: %', p_check_in_id
      using hint = 'check_in_not_found';
  end if;

  update public.check_ins
  set photos = array_remove(photos, p_photo_data_url),
      updated_at = now()
  where id = p_check_in_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.update_check_in(p_check_in_id uuid, p_crew_name text DEFAULT NULL::text, p_check_in_date date DEFAULT NULL::date, p_hours numeric DEFAULT NULL::numeric, p_materials_used text DEFAULT NULL::text, p_blockers text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
  v_created_by uuid;
begin
  select org_id, work_order_id, created_by into v_org_id, v_work_order_id, v_created_by
  from public.check_ins where id = p_check_in_id;

  if v_org_id is null then
    raise exception 'check-in not found or not accessible: %', p_check_in_id
      using hint = 'check_in_not_found';
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'check-in not found or not accessible: %', p_check_in_id
      using hint = 'check_in_not_found';
  end if;

  -- 2026-09-17: hours are payroll. The author or the office tier (view_master_work_order — a PROXY, replace by 2026-11-01).
  if not (coalesce(v_created_by = auth.uid(), false) or coalesce(public.can_view_master_work_order(v_org_id), false)) then
    raise exception 'only the person who recorded this check-in, or the office, can change it — ask the office to correct it'
      using hint = 'change_needs_author_or_office';
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

CREATE OR REPLACE FUNCTION public.delete_check_in(p_check_in_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
  v_created_by uuid;
begin
  select org_id, work_order_id, created_by into v_org_id, v_work_order_id, v_created_by
  from public.check_ins where id = p_check_in_id;

  if v_org_id is null then
    raise exception 'check-in not found or not accessible: %', p_check_in_id
      using hint = 'check_in_not_found';
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'check-in not found or not accessible: %', p_check_in_id
      using hint = 'check_in_not_found';
  end if;

  -- 2026-09-16: the same rule as the table policy. view_master_work_order is a PROXY (see the migration).
  if not (coalesce(v_created_by = auth.uid(), false) or coalesce(public.can_view_master_work_order(v_org_id), false)) then
    raise exception 'only the person who recorded this check-in, or the office, can delete it — ask the office to remove it'
      using hint = 'delete_needs_author_or_office';
  end if;

  delete from public.check_ins where id = p_check_in_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.clear_check_in_hours(p_check_in_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
  v_created_by uuid;
begin
  select org_id, work_order_id, created_by into v_org_id, v_work_order_id, v_created_by
  from public.check_ins where id = p_check_in_id;

  if v_org_id is null then
    raise exception 'check-in not found or not accessible: %', p_check_in_id
      using hint = 'check_in_not_found';
  end if;
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'check-in not found or not accessible: %', p_check_in_id
      using hint = 'check_in_not_found';
  end if;
  if not (coalesce(v_created_by = auth.uid(), false) or coalesce(public.can_view_master_work_order(v_org_id), false)) then
    raise exception 'only the person who recorded this check-in, or the office, can change it — ask the office to correct it'
      using hint = 'change_needs_author_or_office';
  end if;

  -- "Not recorded" is NULL, a state — never 0. RULE 10: already not recorded changes nothing, so nothing is stamped.
  update public.check_ins set hours = null, updated_at = now()
  where id = p_check_in_id and hours is not null;
end;
$function$;

CREATE OR REPLACE FUNCTION public.add_production_packet_callout(p_production_packet_id uuid, p_label text, p_detail text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
  v_callout_id uuid := gen_random_uuid();
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.production_packets where id = p_production_packet_id;

  if v_org_id is null then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id
      using hint = 'production_packet_not_found';
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id
      using hint = 'production_packet_not_found';
  end if;

  update public.production_packets
  set callouts = callouts || jsonb_build_array(
        jsonb_build_object('id', v_callout_id, 'label', p_label, 'detail', p_detail)
      ),
      updated_at = now()
  where id = p_production_packet_id;

  return v_callout_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.update_production_packet_callout(p_production_packet_id uuid, p_callout_id uuid, p_label text DEFAULT NULL::text, p_detail text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.production_packets where id = p_production_packet_id;

  if v_org_id is null then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id
      using hint = 'production_packet_not_found';
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id
      using hint = 'production_packet_not_found';
  end if;

  update public.production_packets
  set callouts = (
        select coalesce(jsonb_agg(
          case when (elem->>'id')::uuid = p_callout_id
            then jsonb_build_object(
              'id', elem->>'id',
              'label', coalesce(p_label, elem->>'label'),
              'detail', coalesce(p_detail, elem->>'detail')
            )
            else elem
          end
        ), '[]'::jsonb)
        from jsonb_array_elements(callouts) as elem
      ),
      updated_at = now()
  where id = p_production_packet_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.delete_production_packet_callout(p_production_packet_id uuid, p_callout_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.production_packets where id = p_production_packet_id;

  if v_org_id is null then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id
      using hint = 'production_packet_not_found';
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id
      using hint = 'production_packet_not_found';
  end if;

  update public.production_packets
  set callouts = (
        select coalesce(jsonb_agg(elem), '[]'::jsonb)
        from jsonb_array_elements(callouts) as elem
        where (elem->>'id')::uuid <> p_callout_id
      ),
      updated_at = now()
  where id = p_production_packet_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.update_production_packet_notes(p_production_packet_id uuid, p_notes text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.production_packets where id = p_production_packet_id;

  if v_org_id is null then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id
      using hint = 'production_packet_not_found';
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id
      using hint = 'production_packet_not_found';
  end if;

  update public.production_packets
  set notes = p_notes,
      updated_at = now()
  where id = p_production_packet_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.delete_production_packet(p_production_packet_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.production_packets where id = p_production_packet_id;

  if v_org_id is null then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id
      using hint = 'production_packet_not_found';
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id
      using hint = 'production_packet_not_found';
  end if;

  delete from public.production_packets where id = p_production_packet_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.record_qc_item(p_work_order_id uuid, p_requirement_key text, p_kind text, p_photo_ref text DEFAULT NULL::text, p_count_value integer DEFAULT NULL::integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_org uuid;
  v_kind text;
  v_id uuid;
begin
  if v_actor is null then
    raise exception 'not signed in' using hint = 'not_signed_in';
  end if;

  -- The work order must be one this caller can reach: their org, and either a
  -- trade work order or a master they are allowed to see.
  select w.org_id, w.kind into v_org, v_kind
  from public.work_orders w
  where w.id = p_work_order_id
    and w.org_id in (select public.my_org_ids())
    and (w.kind = 'trade' or public.can_view_master_work_order(w.org_id));
  if v_org is null then
    raise exception 'that work order is not one you can record against'
      using hint = 'qc_work_order_not_recordable';
  end if;

  -- Ruling 2 (2026-09-22), said here in words; the table refuses it either way.
  if not coalesce(public.is_qc_attester(v_org), false) then
    raise exception 'your role cannot record quality-control evidence in this workspace'
      using hint = 'not_an_attester';
  end if;

  -- Ruling 3 (2026-09-22): the reference is resolved against this work order's photos, not trusted.
  if p_photo_ref is not null and not coalesce(public.qc_photo_on_work_order(p_work_order_id, p_photo_ref), false) then
    raise exception 'that photo is not on this work order — take or pick a photo from this job'
      using hint = 'photo_not_on_work_order';
  end if;

  -- Re-recording a requirement replaces it: the previous row is cleared, not
  -- edited, so the history of what was recorded when survives. The LIVE row keeps the FIRST attestation
  -- alongside this latest one (ruling 1) — carried by qc_items_carry_first_attestation.
  update public.qc_items
     set cleared_at = now(), cleared_by = v_actor
   where work_order_id = p_work_order_id
     and requirement_key = p_requirement_key
     and cleared_at is null;

  insert into public.qc_items (org_id, work_order_id, requirement_key, kind, photo_ref, count_value, actor_id)
  values (v_org, p_work_order_id, p_requirement_key, p_kind, p_photo_ref, p_count_value, v_actor)
  returning id into v_id;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.clear_qc_item(p_work_order_id uuid, p_requirement_key text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_rows integer := 0;
  v_org uuid;
begin
  if v_actor is null then
    raise exception 'not signed in' using hint = 'not_signed_in';
  end if;

  select w.org_id into v_org from public.work_orders w
  where w.id = p_work_order_id
    and w.org_id in (select public.my_org_ids())
    and (w.kind = 'trade' or public.can_view_master_work_order(w.org_id));
  if v_org is not null and not coalesce(public.is_qc_attester(v_org), false) then
    raise exception 'your role cannot change quality-control evidence in this workspace'
      using hint = 'not_an_attester';
  end if;

  update public.qc_items q
     set cleared_at = now(), cleared_by = v_actor
   where q.work_order_id = p_work_order_id
     and q.requirement_key = p_requirement_key
     and q.cleared_at is null
     and q.org_id in (select public.my_org_ids())
     and exists (
       select 1 from public.work_orders w
       where w.id = q.work_order_id
         and (w.kind = 'trade' or public.can_view_master_work_order(w.org_id))
     );
  get diagnostics v_rows = row_count;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION public.crew_assert_can_manage(p_org_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_org_id is null or p_org_id not in (select my_org_ids()) then
    raise exception 'not found or not accessible' using hint = 'workspace_not_accessible';
  end if;
  if not coalesce(public.has_capability(p_org_id, 'schedule'), false) then
    raise exception 'your role cannot manage crews in this workspace' using hint = 'no_schedule_capability';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.add_crew_member(p_crew_id uuid, p_person_id uuid, p_is_lead boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_crew public.crews; v_person public.crew_people;
begin
  select * into v_crew from public.crews where id = p_crew_id;
  perform public.crew_assert_can_manage(v_crew.org_id);
  select * into v_person from public.crew_people where id = p_person_id and org_id = v_crew.org_id;
  if v_person.id is null then
    raise exception 'that person is not in this workspace' using hint = 'crew_person_not_found';
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
$function$;

CREATE OR REPLACE FUNCTION public.crew_name_from_crew()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_name text; v_archived timestamptz;
begin
  if new.crew_id is null then
    return new;
  end if;
  select name, archived_at into v_name, v_archived from public.crews where id = new.crew_id and org_id = new.org_id;
  if v_name is null then
    raise exception 'that crew is not in this workspace' using hint = 'crew_not_found';
  end if;
  if v_archived is not null and (tg_op = 'INSERT' or new.crew_id is distinct from old.crew_id) then
    raise exception 'crew "%" is archived — restore it first', v_name using hint = 'crew_archived';
  end if;
  new.crew_name := v_name;
  return new;
end;
$function$;
