-- RULING 3(a), 2026-09-14, Jacob: ONE TAKE-OFF PATH, NOT TWO. Track S derives which survives.
-- Track S · 2026-09-14. Rollback: supabase/rollbacks/20260914_one_take_off_path_rollback.sql
--
-- THE TWO PATHS, AS OF 20260914230647: generate_take_off(trade, ticked lines) recorded a decision and
-- INSERTED material_items itself; materialize_take_off(job) inserted material_items for every decided,
-- not-yet-taken-off line. Two insert statements into material_items from estimate lines, with two
-- slightly different sort-order and audit rules. Track U cannot build one surface over two paths.
--
-- THE DECISION: materialize_take_off SURVIVES, fed by set_take_off_decision. THE REASON: it is the only
-- one of the two that can express the whole property. A per-trade tick can only say "material, on this
-- trade" — it cannot say NOT MATERIAL, cannot leave a line UNDECIDED on purpose, cannot resolve an
-- ambiguous configured trade, and cannot act on a line a human already decided elsewhere. The review
-- surface #26 needs a job-level list of every line with its state and one action that creates what is
-- decided. That is set_take_off_decision + materialize_take_off. generate_take_off is a special case of it.
--
-- WHAT HAPPENS TO THE OTHER: generate_take_off STOPS CREATING ANYTHING. Its body now (1) refuses the
-- same conflicts it refused yesterday, (2) records each tick as the human decision it is, and
-- (3) calls materialize_take_off(job). There is now exactly ONE statement in the database that creates a
-- material item from an estimate line. The function itself is NOT dropped today, because two live Track U
-- surfaces call it (src/components/coordination/TakeOffPanel.tsx and MasterTakeOffCard.tsx through
-- src/lib/coordination/actions.ts generateTakeOff), and §7.1 rule 5b forbids breaking the deployed UI.
-- REMOVAL CONDITION: drop generate_take_off in the migration that ships with #26's review surface.
--
-- BEHAVIOUR CHANGE, STATED BECAUSE IT WIDENS: a tick now runs the job's take-off, so any OTHER line
-- already decided material-on-a-trade and not yet taken off is created in the same call. Nothing is
-- invented — only decided lines — and the return keeps its keys; `created` counts only the ticked lines,
-- and `created_other_decided` reports the rest.

create or replace function public.generate_take_off(p_work_order_id uuid, p_estimate_line_item_ids uuid[])
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_org_id        uuid;
  v_kind          text;
  v_job_id        uuid;
  v_estimate_id   uuid;
  v_trade         text;
  v_ids           uuid[];
  v_requested     int;
  v_valid         int;
  v_conflicts     int;
  v_ticked_before int;
  v_ticked_after  int;
  v_all_before    int;
  v_all_after     int;
  v_live_trades   int;
  v_with_takeoff  int;
begin
  -- ---- existence + org, before anything is disclosed ----------------------
  select w.org_id, w.kind, w.job_id, w.estimate_id
    into v_org_id, v_kind, v_job_id, v_estimate_id
  from public.work_orders w
  where w.id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  if not coalesce(public.can_view_financials(v_org_id), false) then
    raise exception 'a take-off reads the estimate''s priced line items, and your role cannot view financials';
  end if;

  if not coalesce(public.has_capability(v_org_id, 'view_estimates'), false) then
    raise exception 'a take-off reads the estimate''s line items, and your role cannot view estimates';
  end if;

  -- ---- the master is not a destination (unchanged) -------------------------
  if v_kind = 'master' then
    select count(*) into v_live_trades
    from public.work_orders t
    where t.job_id = v_job_id and t.kind = 'trade' and t.voided_at is null;

    if v_live_trades = 0 then
      raise exception 'this job has 0 trade work orders, so a take-off has nowhere to land — materials attach to a trade. Create trades first, then open a trade and run the take-off there.';
    end if;

    raise exception 'a take-off runs from a trade, not from the master — this job has % live trade work order(s). Open the trade these materials belong to and run it there.', v_live_trades;
  end if;

  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');

  select w.trade into v_trade
  from public.work_orders w where w.id = p_work_order_id;

  -- ---- the selection (unchanged) -------------------------------------------
  select coalesce(array_agg(distinct x), '{}'::uuid[]) into v_ids
  from unnest(p_estimate_line_item_ids) as t(x)
  where x is not null;

  v_requested := coalesce(array_length(v_ids, 1), 0);

  if v_requested = 0 then
    raise exception 'no estimate line items were selected — tick the lines that belong to this trade, then run the take-off';
  end if;

  select count(*) into v_valid
  from public.estimate_line_items e
  where e.id = any(v_ids)
    and e.org_id = v_org_id
    and e.estimate_id = v_estimate_id;

  if v_valid <> v_requested then
    raise exception '% of % selected line items are not on this job''s estimate — nothing was taken off',
      v_requested - v_valid, v_requested;
  end if;

  -- ---- a tick does not silently overrule another human's decision (unchanged) ----
  select count(*) into v_conflicts
  from public.take_off_lines t
  where t.estimate_line_item_id = any(v_ids) and t.estimate_status is not null
    and ( (t.disposition_source in ('human', 'generate_take_off', 'backfill') and t.disposition = 'not_material')
       or (t.disposition_source in ('human', 'generate_take_off', 'backfill') and t.disposition = 'material'
           and t.trade_work_order_id is not null and t.trade_work_order_id <> p_work_order_id)
       or (t.material_item_id is not null and t.material_work_order_id <> p_work_order_id) );

  if v_conflicts > 0 then
    raise exception '% of % selected line items are already decided for take-off elsewhere (not material, or on another trade) — change their decision first; nothing was taken off',
      v_conflicts, v_requested;
  end if;

  -- ---- the tick IS the human decision (unchanged) ---------------------------
  insert into public.take_off_decisions
    (estimate_line_item_id, org_id, disposition, work_order_id, source, decided_by, decided_at)
  select x, v_org_id, 'material', p_work_order_id, 'generate_take_off', auth.uid(), now()
  from unnest(v_ids) as x
  on conflict (estimate_line_item_id) do update
    set disposition = 'material',
        work_order_id = excluded.work_order_id,
        source = 'generate_take_off',
        decided_by = excluded.decided_by,
        decided_at = now(),
        item_removed_at = null,
        item_removed_by = null;

  -- ---- THE ONE PATH ----------------------------------------------------------
  select count(*) into v_ticked_before from public.material_items where estimate_line_item_id = any(v_ids);
  select count(*) into v_all_before from public.material_items m join public.work_orders w on w.id = m.work_order_id
   where w.job_id = v_job_id and m.estimate_line_item_id is not null;

  perform public.materialize_take_off(v_job_id);

  select count(*) into v_ticked_after from public.material_items where estimate_line_item_id = any(v_ids);
  select count(*) into v_all_after from public.material_items m join public.work_orders w on w.id = m.work_order_id
   where w.job_id = v_job_id and m.estimate_line_item_id is not null;

  -- ---- CLAUSE (a)'s REPORTED FIGURE (unchanged) -----------------------------
  select count(*) into v_live_trades
  from public.work_orders t
  where t.job_id = v_job_id and t.kind = 'trade' and t.voided_at is null;

  select count(distinct m.work_order_id) into v_with_takeoff
  from public.material_items m
  join public.work_orders t on t.id = m.work_order_id
  where t.job_id = v_job_id
    and t.kind = 'trade'
    and t.voided_at is null
    and m.estimate_line_item_id is not null;

  return jsonb_build_object(
    'work_order_id',         p_work_order_id,
    'job_id',                v_job_id,
    'trade',                 v_trade,
    'lines_requested',       v_requested,
    'created',               v_ticked_after - v_ticked_before,
    'skipped_existing',      v_requested - (v_ticked_after - v_ticked_before),
    'created_other_decided', (v_all_after - v_all_before) - (v_ticked_after - v_ticked_before),
    'trades_with_take_off',  v_with_takeoff,
    'live_trade_count',      v_live_trades
  );
end;
$function$;

revoke execute on function public.generate_take_off(uuid, uuid[]) from public, anon;

-- Rule 3: exactly one function body in public inserts into material_items from an estimate line.
do $$
begin
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
       and prosrc ~* 'insert\s+into\s+public\.material_items' and prosrc ~ 'estimate_line_item_id') <> 1 then
    raise exception 'more than one function creates material items from estimate lines';
  end if;
end $$;