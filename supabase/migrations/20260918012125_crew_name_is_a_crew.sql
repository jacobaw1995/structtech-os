-- A NAME IS NOT A PERSON: A SCHEDULE BLOCK AND A CHECK-IN CAN POINT AT A REAL CREW. Track S · 2026-09-17.
-- Rollback: supabase/rollbacks/20260917_crew_name_is_a_crew_rollback.sql
--
-- BEFORE: schedule_blocks.crew_name and check_ins.crew_name are free text, required, and the only record of who
-- does the work. Measured 2026-09-17: 2 schedule blocks ("TRACK S · acceptance crew" on Fake Lead; "SYNTHETIC
-- Crew" on the synthetic tenant), 0 check-ins, 0 crews.
-- THE SHAPE, ADDITIVE (rule 5b — the deployed UI sends crew_name and keeps working unchanged):
--   · crew_id on both tables, a composite reference to crews(id, org_id) — a crew from another tenant cannot be
--     named; ON DELETE SET NULL (crew_id) keeps the last name as text if a crew is ever deleted.
--   · When crew_id is set, crew_name is DERIVED from the crew by trigger (one fact, not two), and a crew rename
--     carries to every block and check-in that names it.
--   · add_schedule_block / update_schedule_block / create_check_in take an optional p_crew_id. crew_name is then
--     optional. Typing a DIFFERENT name onto a block linked to a crew is refused in words (hint 'crew_linked') —
--     unlink it (p_unlink_crew) or choose another crew; RE-SENDING the same name is not a change (RULE 8/10) and
--     passes.
-- NOT CHANGED: existing rows stay free text (no crew exists to point them at). A crew chosen on a block is not
-- also assigned to the work order automatically — work_order_crew_assignments stays its own decision.

alter table public.schedule_blocks add column crew_id uuid;
alter table public.schedule_blocks add constraint schedule_blocks_crew_fk
  foreign key (crew_id, org_id) references public.crews (id, org_id) on delete set null (crew_id);
create index schedule_blocks_crew_idx on public.schedule_blocks (crew_id) where crew_id is not null;

alter table public.check_ins add column crew_id uuid;
alter table public.check_ins add constraint check_ins_crew_fk
  foreign key (crew_id, org_id) references public.crews (id, org_id) on delete set null (crew_id);
create index check_ins_crew_idx on public.check_ins (crew_id) where crew_id is not null;

create function public.crew_name_from_crew()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
declare v_name text; v_archived timestamptz;
begin
  if new.crew_id is null then
    return new;
  end if;
  select name, archived_at into v_name, v_archived from public.crews where id = new.crew_id and org_id = new.org_id;
  if v_name is null then
    raise exception 'that crew is not in this workspace' using hint = 'not_found';
  end if;
  if v_archived is not null and (tg_op = 'INSERT' or new.crew_id is distinct from old.crew_id) then
    raise exception 'crew "%" is archived — restore it first', v_name using hint = 'crew_archived';
  end if;
  new.crew_name := v_name;
  return new;
end;
$function$;
revoke execute on function public.crew_name_from_crew() from public, anon, authenticated;

create trigger schedule_blocks_crew_name before insert or update on public.schedule_blocks
  for each row execute function public.crew_name_from_crew();
create trigger check_ins_crew_name before insert or update on public.check_ins
  for each row execute function public.crew_name_from_crew();

create function public.crews_carry_name()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
begin
  if new.name is distinct from old.name then
    update public.schedule_blocks set crew_name = new.name where crew_id = new.id and crew_name is distinct from new.name;
    update public.check_ins set crew_name = new.name where crew_id = new.id and crew_name is distinct from new.name;
  end if;
  return null;
end;
$function$;
revoke execute on function public.crews_carry_name() from public, anon, authenticated;

create trigger crews_carry_name after update of name on public.crews
  for each row execute function public.crews_carry_name();

-- ---- add_schedule_block: optional crew ----------------------------------------------------------------------
drop function public.add_schedule_block(p_work_order_id uuid, p_crew_name text, p_start_date date, p_end_date date);
create function public.add_schedule_block(p_work_order_id uuid, p_crew_name text, p_start_date date, p_end_date date,
  p_crew_id uuid default null)
 returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_org_id uuid; v_block_id uuid; v_blocking_name text; v_blocking_ready_by date;
  v_conflict boolean; v_reason text;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');

  if not public.has_capability(v_org_id, 'schedule') then
    raise exception 'your role cannot schedule work in this workspace';
  end if;

  if p_crew_id is null and nullif(btrim(p_crew_name), '') is null then
    raise exception 'choose a crew, or type who is doing the work' using hint = 'crew_required';
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

  -- With a crew, crew_name is derived by schedule_blocks_crew_name; the placeholder below is overwritten.
  insert into public.schedule_blocks
    (org_id, work_order_id, crew_id, crew_name, start_date, end_date, ready_by_conflict, ready_by_conflict_reason)
  values
    (v_org_id, p_work_order_id, p_crew_id, coalesce(nullif(btrim(p_crew_name), ''), '(crew)'), p_start_date, p_end_date,
     v_conflict, v_reason)
  returning id into v_block_id;

  return v_block_id;
end;
$function$;
revoke execute on function public.add_schedule_block(uuid, text, date, date, uuid) from public, anon;
grant execute on function public.add_schedule_block(uuid, text, date, date, uuid) to authenticated;

-- ---- update_schedule_block: set, keep or unlink the crew ----------------------------------------------------
drop function public.update_schedule_block(p_schedule_block_id uuid, p_crew_name text, p_start_date date, p_end_date date);
create function public.update_schedule_block(p_schedule_block_id uuid, p_crew_name text default null,
  p_start_date date default null, p_end_date date default null, p_crew_id uuid default null,
  p_unlink_crew boolean default false)
 returns void language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_org_id uuid; v_work_order_id uuid; v_start_date date; v_end_date date;
  v_old_start_date date; v_crew_id uuid; v_crew_name text;
  v_blocking_name text; v_blocking_ready_by date; v_conflict boolean; v_reason text;
begin
  select org_id, work_order_id, start_date, end_date, crew_id, crew_name
  into v_org_id, v_work_order_id, v_start_date, v_end_date, v_crew_id, v_crew_name
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

  -- The crew: a chosen crew wins; unlinking returns to free text; a DIFFERENT typed name on a linked block is
  -- refused (re-sending the derived name is not a change).
  if p_crew_id is not null then
    v_crew_id := p_crew_id;
  elsif coalesce(p_unlink_crew, false) then
    v_crew_id := null;
    v_crew_name := coalesce(nullif(btrim(p_crew_name), ''), v_crew_name);
  elsif p_crew_name is not null then
    if v_crew_id is not null and btrim(p_crew_name) is distinct from v_crew_name then
      raise exception 'this block is scheduled to crew "%" — choose another crew, or unlink it to type a name', v_crew_name
        using hint = 'crew_linked';
    end if;
    v_crew_name := p_crew_name;
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
  set crew_id = v_crew_id,
      crew_name = v_crew_name,
      start_date = v_start_date,
      end_date = v_end_date,
      ready_by_conflict = v_conflict,
      ready_by_conflict_reason = v_reason,
      updated_at = now()
  where id = p_schedule_block_id;
end;
$function$;
revoke execute on function public.update_schedule_block(uuid, text, date, date, uuid, boolean) from public, anon;
grant execute on function public.update_schedule_block(uuid, text, date, date, uuid, boolean) to authenticated;

-- ---- create_check_in: optional crew -------------------------------------------------------------------------
drop function public.create_check_in(p_work_order_id uuid, p_crew_name text, p_schedule_block_id uuid, p_check_in_date date, p_hours numeric, p_materials_used text, p_blockers text);
create function public.create_check_in(p_work_order_id uuid, p_crew_name text, p_schedule_block_id uuid DEFAULT NULL::uuid,
  p_check_in_date date DEFAULT NULL::date, p_hours numeric DEFAULT NULL::numeric, p_materials_used text DEFAULT NULL::text,
  p_blockers text DEFAULT NULL::text, p_crew_id uuid DEFAULT NULL::uuid)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_check_in_id uuid;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');

  if p_crew_id is null and nullif(btrim(p_crew_name), '') is null then
    raise exception 'choose a crew, or type who is doing the work' using hint = 'crew_required';
  end if;

  -- The date is New York's, never the session's (2026-09-16). A blank hours field is "not recorded" (NULL),
  -- never 0. With a crew, crew_name is derived by check_ins_crew_name.
  insert into public.check_ins
    (org_id, work_order_id, schedule_block_id, crew_id, crew_name, check_in_date, hours, materials_used, blockers)
  values
    (v_org_id, p_work_order_id, p_schedule_block_id, p_crew_id, coalesce(nullif(btrim(p_crew_name), ''), '(crew)'),
     coalesce(p_check_in_date, (now() at time zone 'America/New_York')::date),
     p_hours, p_materials_used, p_blockers)
  returning id into v_check_in_id;

  return v_check_in_id;
end;
$function$;
revoke execute on function public.create_check_in(uuid, text, uuid, date, numeric, text, text, uuid) from public, anon;
grant execute on function public.create_check_in(uuid, text, uuid, date, numeric, text, text, uuid) to authenticated;
