-- A4.6 — THE SCHEDULER REFUSES A CREW WITH NO VEHICLE, BEHIND `enforce_stage_gating`.
-- Track S · 2026-10-01. Rollback: supabase/rollbacks/20261002_crew_vehicle_refusal_rollback.sql
--
-- CLOSES AN ITEM OPEN SINCE 2026-09-15. A4.6's Done-when says the scheduler REFUSES; SCOPE §2.8
-- says never block the user. **Controller ruling, 2026-10-01: a "never" and a "must refuse" are
-- reconciled by a SWITCH, not by a winner.** The Done-when tests that the refusal EXISTS and
-- fires when a tenant turns enforcement on; the default tests the principle. Verified against
-- docs/SCOPE.md before recording: §2.8 names its own escape hatch, verbatim — *"Where a tenant
-- genuinely wants enforced process, that is per-tenant config, defaulted OFF
-- (`enforce_stage_gating`), never the shipped default."*
--
-- THE SHAPE IS THE ONE FROM THREE DAYS AGO, NOT A NEW ONE. 20260929153659_crew_scoped_field_jobs
-- established it: a switch in organizations.policy, default OFF, byte-identical when off, a named
-- refusal with a hint when on, and a mutation test reproducing the failure it prevents.
--
-- ⚠ ONE SWITCH, TWO BEHAVIOURS — a consequence, not a detail. `enforce_stage_gating` already
-- gates A2.3's "a schedule block before its ready_by is blocked". A tenant turning it on for the
-- vehicle check ALSO gets the ready_by block, and the reverse. That is the instruction (do not
-- invent a second shape) and it is defensible — both mean "this tenant wants enforced process" —
-- but it is coarse, and the day a tenant wants one without the other, this key splits.
--
-- MEASURED FIRST, AND THE ANSWER CHANGES WHAT THIS IS:
--   crews 0 · crew_people 0 · crew_memberships 0 · work_order_crew_assignments 0 — whole database.
-- **So this refusal has nothing to fire on in production today, and the proofs are against
-- FIXTURES inside a rolled-back transaction. WHAT IS BUILT IS A CAPABILITY, NOT A GUARANTEE** —
-- proved to work on data shaped like the real thing, never having met the real thing, because the
-- real thing does not exist yet. Said plainly so no one reads the passes as evidence about production.
--
-- AND HALF THE DONE-WHEN CANNOT BE BUILT, WHICH IS A FINDING RATHER THAN A CHOICE. It reads "a
-- crew with no vehicle to a job REQUIRING TRANSPORT". **No column anywhere records whether a job
-- requires transport** — every table searched for `transport|requires_vehicle|needs_vehicle`:
-- 0 hits. The reading taken here is that EVERY TRADE WORK ORDER REQUIRES TRANSPORT, because every
-- one is at a site address and a crew with no vehicle cannot reach any of them. If BMR ever has a
-- job somebody walks to, that qualifier becomes a real column and this refusal needs it.
--
-- `has_vehicle` IS NULLABLE AND THAT IS THE WHOLE DESIGN. Three states, not two: true, false, and
-- NULL = nobody said. The refusal fires on `no_vehicle` only.

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

  -- Availability and vehicle come back as STATES. By default nothing here refuses a crew for
  -- either — that is SCOPE §2.8 and it remains the shipped behaviour.
  select s.vehicle_state, s.availability_state, s.unavailable_members, s.members into v_state
  from public.crew_assignment_states s where s.assignment_id = v_id
  limit 1;

  -- A4.6's Done-when, BEHIND THE SWITCH (controller ruling 2026-10-01). A "never" and a
  -- "must refuse" are reconciled by a switch, not by a winner: the Done-when tests that the
  -- refusal EXISTS and fires when a tenant turns enforcement on; the default tests §2.8.
  --
  -- IT FIRES ON `no_vehicle` AND DELIBERATELY NOT ON `vehicle_not_recorded`. The view already
  -- separates them, and U's copy says why: "Nobody on this crew has a vehicle recorded — it
  -- may or may not be a problem." Refusing THAT would be the exact thing Isaac objected to —
  -- software demanding a field be filled before it will let him act. `crew_has_no_members` is
  -- also not refused: an empty crew is a different fact with its own state.
  --
  -- THE REFUSAL COMES AFTER THE INSERT ON PURPOSE. The vehicle state is computed by the view
  -- crew_assignment_states, which keys on assignment_id, so the row must exist to be graded.
  -- Re-implementing the view's CASE here would create a second source of truth that drifts the
  -- day somebody edits one of them. The RAISE aborts the statement and the insert goes with it
  -- — proved rather than assumed, by counting assignments after the refusal.
  if coalesce(public.tenant_enforces_stage_gating(v_crew.org_id), false)
     and v_state.vehicle_state = 'no_vehicle' then
    raise exception 'crew "%" has nobody with a vehicle, and this workspace enforces process — record a vehicle for someone on the crew, or assign a different crew', v_crew.name
      using hint = 'crew_has_no_vehicle';
  end if;
  return jsonb_build_object('assignment_id', v_id, 'members', v_state.members, 'vehicle_state', v_state.vehicle_state,
                            'availability_state', v_state.availability_state,
                            'unavailable_members', v_state.unavailable_members);
end;
$function$;
