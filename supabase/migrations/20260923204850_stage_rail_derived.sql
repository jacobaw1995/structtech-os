-- A CHECKMARK THAT CAN NEVER BE FALSE IS NOT A STATUS, IT IS DECORATION. Track S · 2026-09-23.
-- Rollback: supabase/rollbacks/20260923_stage_rail_derived_rollback.sql
--
-- Track U measured it: in src/lib/coordination/stage.ts, `signed` and `work_order` are written
-- `complete: true` and can never be anything else, sitting beside `sign_off`, `materials` and `schedule`,
-- which are genuinely derived from rows. Nothing on the screen separates a fact from an ornament.
--
-- BEFORE-MEASUREMENT, across every live job (3 jobs, all of them):
--   `signed`      would be TRUE for 3 of 3 — every job's estimate carries exactly 1 signature.
--   `work_order`  would be TRUE for 2 of 3 — Devin Carter's job (a5f569ed…) has NO trade work order at all,
--                 live or voided, so the hardcoded checkmark is WRONG TODAY on a real BMR job.
-- So one of the two ornaments is currently telling the truth by accident and the other is simply wrong. That
-- is the honest version of the finding, and it is why `signed` still gets derived rather than deleted: a
-- chip that happens to be true for every row today is not a chip that cannot be false — the next unsigned
-- job makes it false, and nothing in the rail would have noticed.
--
-- THE TWO FACTS, both already in the database:
--   job_signed            a signature row exists for the job's estimate. Not `estimates.status`, which is a
--                         derived label the signing trigger maintains; the signature is the event itself.
--   job_live_trade_count  trade work orders on the job that are not voided. `work_order` is true when > 0.
-- Both are counts of work, not money, and neither is gated: a crew-tier caller already gets this function
-- for its own trade, and "this job is signed" / "this job has a live trade" are facts about the job in front
-- of them. No column of a money table is read (signatures is checked for EXISTENCE, never returned).
--
-- FOR TRACK U, the shape to render (S owns the derivation, U owns what it looks like):
--   coordinationStages({ signOffAt, materialCount, scheduleCount,
--                        signed: tree.job_signed, workOrder: tree.job_live_trade_count > 0 })
--   and both chips lose `complete: true`. A master page with no live trade then reads "Work order" as
--   incomplete, which is the true statement about Devin Carter's job.

create or replace function public.fetch_work_order_tree(p_work_order_id uuid)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_kind text;
  v_job_id uuid;
  v_voided_at timestamptz;
  v_cascade_source uuid;
  v_master_id uuid;
  v_master_sign_off timestamptz;
  v_trades jsonb;
  v_job_materials int;
  v_job_schedule int;
  v_can_see_master boolean;
  v_job_signed boolean;
  v_live_trades int;
begin
  select w.org_id, w.kind, w.job_id, w.voided_at, w.void_cascade_source_id
  into v_org_id, v_kind, v_job_id, v_voided_at, v_cascade_source
  from public.work_orders w
  where w.id = p_work_order_id;

  -- Null rather than a raise: this mirrors fetch_work_order, which returns zero
  -- rows for an inaccessible id. The page redirects on a falsy result.
  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    return null;
  end if;

  v_can_see_master := public.can_view_master_work_order(v_org_id);

  -- A1.5: a crew-tier caller gets nothing for a master, exactly as
  -- fetch_work_order does.
  if v_kind = 'master' and not v_can_see_master then
    return null;
  end if;

  select m.id, m.sign_off_at
  into v_master_id, v_master_sign_off
  from public.work_orders m
  where m.job_id = v_job_id and m.kind = 'master';

  -- On a trade, a crew-tier caller still gets the trade — but not a pointer up
  -- to a master they may not open, and not the master's sign-off state.
  if not v_can_see_master then
    v_master_id := null;
    v_master_sign_off := null;
  end if;

  with node as (
    select
      t.id, t.trade, t.assignee_type, t.assignee_ref, t.predecessor_id,
      t.voided_at, t.void_cascade_source_id, t.created_at,
      (select count(*) from public.material_items mi where mi.work_order_id = t.id)::int as material_count,
      (select count(*) from public.schedule_blocks sb where sb.work_order_id = t.id)::int as schedule_count
    from public.work_orders t
    where t.job_id = v_job_id and t.kind = 'trade'
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', node.id,
        'trade', node.trade,
        'assignee_type', node.assignee_type,
        'assignee_ref', node.assignee_ref,
        'predecessor_id', node.predecessor_id,
        'voided_at', node.voided_at,
        'voided_by_cascade', node.void_cascade_source_id is not null,
        'material_count', node.material_count,
        'schedule_count', node.schedule_count
      ) order by node.created_at
    ), '[]'::jsonb)
  into v_trades
  from node;

  -- Job-wide counts span every work order on the job, master included: a
  -- pre-A1.3b master can still hold rows, and the master's roll-up line must
  -- not under-report them.
  select
    (select count(*) from public.material_items mi
       join public.work_orders w2 on w2.id = mi.work_order_id
      where w2.job_id = v_job_id)::int,
    (select count(*) from public.schedule_blocks sb
       join public.work_orders w2 on w2.id = sb.work_order_id
      where w2.job_id = v_job_id)::int
  into v_job_materials, v_job_schedule;

  -- 2026-09-23: the two stage chips that were hardcoded `complete: true`, derived from the objects that
  -- already carry the facts. The signature is the event; `estimates.status` is its label.
  select exists (
    select 1 from public.signatures s
    join public.jobs j on j.estimate_id = s.estimate_id
    where j.id = v_job_id
  ) into v_job_signed;

  select count(*)::int into v_live_trades
  from public.work_orders t
  where t.job_id = v_job_id and t.kind = 'trade' and t.voided_at is null;

  return jsonb_build_object(
    'work_order_id', p_work_order_id,
    'level', v_kind,
    'job_id', v_job_id,
    'master_id', v_master_id,
    'master_sign_off_at', v_master_sign_off,
    'voided_at', v_voided_at,
    'voided_by_cascade', v_cascade_source is not null,
    'trades', v_trades,
    'job_material_count', v_job_materials,
    'job_schedule_count', v_job_schedule,
    'job_signed', v_job_signed,
    'job_live_trade_count', v_live_trades
  );
end;
$function$;
