-- ROLLBACK for 20260923 stage_rail_derived: restores fetch_work_order_tree without job_signed /
-- job_live_trade_count. Any UI reading those two keys would then see them absent (undefined), so roll the
-- UI back with it.
CREATE OR REPLACE FUNCTION public.fetch_work_order_tree(p_work_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    'job_schedule_count', v_job_schedule
  );
end;
$function$
;
