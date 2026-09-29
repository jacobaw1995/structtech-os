-- A1 — CREW SCOPING FOR fetch_field_jobs. BUILT, AND DELIBERATELY NOT SWITCHED ON.
-- Track S · 2026-09-29. Rollback: supabase/rollbacks/20260929_crew_scoped_field_jobs_rollback.sql
--
-- WHAT IT DOES TODAY, measured rather than remembered: `fetch_field_jobs` reads `my_org_ids()`
-- and NOTHING else — not role, not `view_field`, not `crew_memberships`, not `has_capability`,
-- not even `auth.uid()`. Every member of an org sees every unfinished trade job in it, capped
-- at 20. At one job nobody notices; at five, every roofer sees all five.
--
-- THE CONTROLLER'S CLAIM, RE-MEASURED AND CONFIRMED — AND THEN MADE MORE PRECISE.
-- "If scoping were switched on today, every roofer would see ZERO jobs." Measured across all
-- 8 live memberships in all 4 orgs: **scoped count = 0 for every one of them.**
--   crew_memberships 0 · crews 0 · crew_people 0 · work_order_crew_assignments 0
--   schedule_blocks 3, of which crew_id is null on 3 · crew_people linked to a login: 0
-- **But only THREE of the eight would actually LOSE anything** (BMR's owner and agency_admin,
-- and the synthetic tenant's crew member, each of whom sees 1 today). The other five already
-- see 0 for an unrelated reason — their orgs have no current schedule block at all.
-- That distinction is load-bearing for the refusal below: **an empty result and an unassigned
-- caller are different conditions, and conflating them would refuse a genuinely free day.**
--
-- SO IT SHIPS OFF, AND IT CANNOT PRODUCE A SILENT ZERO.
--   · switch OFF (the default, and every org today) → byte-identical to current behaviour;
--   · switch ON + the caller is office/manager → unscoped. An office user is not a roofer;
--   · switch ON + the caller is on a crew → their own jobs, and an EMPTY LIST is a real answer
--     meaning "nothing today". That is the one case where empty is honest;
--   · switch ON + the caller is on NO crew in this org → **REFUSED BY NAME**, never an empty
--     set. "You have no work today" and "nobody has put you on a crew" are different sentences
--     and a roofer standing on a driveway needs to know which one they are in.
--
-- THE SWITCH IS `organizations.policy -> 'scope_field_jobs_to_crew'`, the same store and the
-- same shape as `enforce_stage_gating` (A2.3, 2026-09-03). One row per tenant, so the key
-- cannot come to disagree with itself. Measured 2026-09-29: policy = '{}' on all 4 orgs, so
-- this migration changes what NOBODY sees until somebody turns it on deliberately.
--
-- AND THE UTC DEFAULT IS CLOSED HERE, NOT AHEAD OF THIS. `p_today` was `DEFAULT CURRENT_DATE`
-- — the SESSION's date, which is UTC, so from 8 PM EDT it asks for tomorrow. It becomes
-- `DEFAULT NULL` and the null is REFUSED BY NAME, because a refusal written behind a REMOVED
-- default is unreachable: with no default at all the call never enters the function (42883,
-- proved on add_material_item on 2026-09-25). **Rule 5b is satisfied by measurement, not
-- assumption: both app callers pass p_today explicitly** — `field/page.tsx:69` and
-- `field/[workOrderId]/page.tsx:96`, each with `todayInNewYork()` — so no deployed caller
-- relies on the default. `p_today?: string` in the generated types is unchanged, because
-- DEFAULT NULL is still a default.
--
-- ORG-NOT-ACCESSIBLE STOPS BLANKING TOO. Today a foreign org_id returns `[]`, which renders as
-- "no jobs" on a crew screen — "cannot see" shown as "does not exist", the class closed across
-- 24 definer readers on 2026-09-20. It now refuses by name.
--
-- DROP + CREATE rather than REPLACE: the body changes language (sql → plpgsql) and the
-- parameter default changes, and a fresh CREATE resets proacl to the PUBLIC default, so the
-- revoke at the foot is mandatory (rule 7). `authenticated` is KEPT — the test is "does
-- anything outside the database call this?" and the answer is yes, two server components.

-- ---------------------------------------------------------------------------
-- The switch. Mirrors tenant_enforces_stage_gating exactly, including its closed
-- default expressed three times over. NOT granted to `authenticated`: nothing outside
-- the database calls it (rule 7's carve-out, answered per function).
-- ---------------------------------------------------------------------------
create or replace function public.tenant_scopes_field_jobs_to_crew(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  -- Closed default expressed three times over, deliberately: a missing org, a
  -- policy with no key, and a non-boolean value all mean OFF.
  select coalesce(
    (select (o.policy ->> 'scope_field_jobs_to_crew')::boolean
     from public.organizations o where o.id = p_org_id),
    false
  );
$function$;

revoke execute on function public.tenant_scopes_field_jobs_to_crew(uuid) from public, anon, authenticated;

drop function if exists public.fetch_field_jobs(p_org_id uuid, p_today date);

create function public.fetch_field_jobs(p_org_id uuid, p_today date default null::date)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_scoped boolean;
  v_unscoped_caller boolean;
  v_crew_count int;
begin
  if p_org_id is null or p_org_id not in (select my_org_ids()) then
    raise exception 'workspace not found or not accessible: %', p_org_id
      using hint = 'field_jobs_org_not_accessible';
  end if;

  -- THE DATE IS THE CALLER'S TO STATE. CURRENT_DATE here is UTC's calendar, and from
  -- 8 PM EDT that is tomorrow — a job ending today would drop off the crew's screen
  -- that evening. Refused rather than guessed.
  if p_today is null then
    raise exception 'a date is required — the crew screen asks for its own day, in its own timezone, and the database will not guess one'
      using hint = 'field_jobs_date_required';
  end if;

  v_scoped := coalesce(public.tenant_scopes_field_jobs_to_crew(p_org_id), false);

  -- Office and manager tier are never scoped: they are not roofers, and the surface
  -- they use is the coordination board. Same test the check_ins policies use.
  v_unscoped_caller := coalesce(public.can_view_master_work_order(p_org_id), false);

  if v_scoped and not v_unscoped_caller then
    select count(*) into v_crew_count
    from public.crew_memberships cm
    join public.crew_people cp on cp.id = cm.person_id
    where cm.org_id = p_org_id
      and cp.user_id = auth.uid()
      and cp.archived_at is null;

    -- THE WHOLE POINT OF THIS MIGRATION. Not an empty array: an empty array on a crew
    -- screen reads "nothing on today", and a roofer who has simply never been put on a
    -- crew would stand in a driveway believing they had the day off.
    if v_crew_count = 0 then
      raise exception 'you are not on a crew in this workspace yet, so there is nothing to show you — ask the office to add you to a crew'
        using hint = 'crew_not_assigned';
    end if;
  end if;

  return (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'schedule_block_id', j.id,
          'work_order_id', j.work_order_id,
          'crew_name', j.crew_name,
          'start_date', j.start_date,
          'end_date', j.end_date,
          'ready_by_conflict', j.ready_by_conflict,
          'ready_by_conflict_reason', j.ready_by_conflict_reason,
          'job_title', coalesce(nullif(j.company, ''), j.contact_name),
          'site_address', j.site_address,
          'squares', j.squares,
          'pitch', j.pitch
        ) order by j.start_date, j.created_at
      ), '[]'::jsonb)
    from (
      select sb.id, sb.work_order_id, sb.crew_name, sb.start_date, sb.end_date,
             sb.ready_by_conflict, sb.ready_by_conflict_reason, sb.created_at,
             e.company, e.contact_name, e.site_address, e.squares, e.pitch
      from public.schedule_blocks sb
      join public.work_orders w on w.id = sb.work_order_id
      join public.estimates e on e.id = w.estimate_id
      where sb.org_id = p_org_id
        and w.kind = 'trade'
        and w.voided_at is null
        and sb.end_date >= p_today
        -- OFF, or an office caller: this whole clause is `true` and the result is
        -- byte-identical to what shipped before this migration.
        and (
          not v_scoped
          or v_unscoped_caller
          -- TWO WAYS A JOB IS YOURS, because the build has two: the block names your
          -- crew, or the work order is assigned to your crew. Either is an assignment.
          or exists (
            select 1
            from public.crew_memberships cm
            join public.crew_people cp on cp.id = cm.person_id
            where cp.user_id = auth.uid()
              and cp.archived_at is null
              and cm.org_id = p_org_id
              and (
                cm.crew_id = sb.crew_id
                or exists (
                  select 1 from public.work_order_crew_assignments a
                  where a.work_order_id = w.id and a.crew_id = cm.crew_id
                )
              )
          )
        )
      order by sb.start_date, sb.created_at
      limit 20
    ) j
  );
end;
$function$;

-- Rule 7: a fresh CREATE is born with EXECUTE granted to PUBLIC — the leading `=X/postgres`
-- entry, which a revoke naming only `anon` would not touch. `authenticated` is kept: two
-- server components call this.
revoke execute on function public.fetch_field_jobs(uuid, date) from public, anon;
grant execute on function public.fetch_field_jobs(uuid, date) to authenticated;
