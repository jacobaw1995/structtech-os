-- CONTROLLER RULING, 2026-09-14: A WRITE THAT DOES NOT CHANGE THE GATED FACT MUST NOT BE
-- GATED. Compare OLD to NEW. Presence in the payload is not a change.
-- Track S · 2026-09-14. Rollback: supabase/rollbacks/20260914_gate_only_a_changed_fact_rollback.sql
--
-- THE REPORT (Track U): ScheduleBlockRow re-sends the stored start and end dates on every
-- edit, so under enforce_stage_gating a crew-name-only edit on a block already in conflict
-- is refused.
--
-- ATTRIBUTION, MEASURED BEFORE THIS RAN — and it corrects the report's cause, not its
-- symptom. As `authenticated` with the BMR owner's JWT, gating ON, rolled back, the UI's
-- exact payload (crew changed, dates re-sent) was refused with THE RPC'S OWN MESSAGE
-- ("…so the change was not saved") — with the live trigger AND with the pre-2026-09-13
-- trigger restored in the same transaction. update_schedule_block has refused every edit
-- to a conflicting block since A2.3 (2026-09-03): it recomputes the conflict from the
-- coalesced start date and gates on the RESULT. 20260913140204 did not create the UI's
-- refusal; it added the same refusal to a DIRECT crew-only update (pre-0913 trigger: saved;
-- live trigger: refused). Both gates tested the resulting row instead of the change.
-- The same shape as 20260913014616 (a resubmitted ready_by read as a typed one): the third
-- time a re-sent unchanged value has been read as intent.
--
-- THE GATED FACT is a block's START DATE against its trade's materials (the work order it
-- belongs to decides which materials). A write gates only when it CHANGES start_date or
-- work_order_id. The CONFLICT FLAG is still recomputed on every write — the fact stays
-- true; only the refusal is conditional. So a crew rename on a conflicting block saves and
-- the block still reads in conflict. An end-date-only change is not a gated change.
-- A move WITHIN conflict (10-05 -> 10-06, both before ready-by) changes the start date and
-- is refused: it is a new scheduling decision made against unready materials.

create or replace function public.schedule_blocks_ready_by_gate()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
declare v_name text; v_ready date;
begin
  select name, ready_by into v_name, v_ready
  from public.material_items
  where work_order_id = new.work_order_id and ready_by is not null
  order by ready_by desc limit 1;

  -- The fact is recomputed on EVERY write, and a writer can never set it.
  new.ready_by_conflict := v_ready is not null and new.start_date < v_ready;
  new.ready_by_conflict_reason := case when new.ready_by_conflict
    then format('materials not ready until %s (%s)', v_ready, v_name) else null end;

  -- The refusal fires only when the write CHANGES the gated fact. OLD vs NEW, never
  -- presence in the payload.
  if new.ready_by_conflict
     and (tg_op = 'INSERT'
          or new.start_date is distinct from old.start_date
          or new.work_order_id is distinct from old.work_order_id)
     and public.tenant_enforces_stage_gating(new.org_id) then
    raise exception '%. This workspace enforces stage gating, so the schedule block was not saved. Move the start date to % or later, or turn off enforce_stage_gating.',
      new.ready_by_conflict_reason, v_ready;
  end if;
  return new;
end;
$function$;

create or replace function public.update_schedule_block(
  p_schedule_block_id uuid, p_crew_name text default null,
  p_start_date date default null, p_end_date date default null
)
returns void language plpgsql security definer set search_path to 'public'
as $function$
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

revoke execute on function public.schedule_blocks_ready_by_gate() from public, anon, authenticated;
revoke execute on function public.update_schedule_block(uuid, text, date, date) from public, anon;