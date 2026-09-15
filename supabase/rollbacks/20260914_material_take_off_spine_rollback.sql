-- ROLLBACK for 2026-09-14 material_take_off_spine.
-- generate_take_off body and material_items_take_off_uniq captured from pg_get_functiondef()
-- and pg_indexes on the LIVE database 2026-09-14 BEFORE the change.
--
-- RESTORING THIS RE-OPENS, each proved on 2026-09-14 before the forward migration:
-- one estimate line taken off onto two trades becomes two materials; a material item a
-- human deleted is re-created by the next run; a direct INSERT can create a material
-- from a labor line on any trade; and neither a human edit of a material nor a change
-- to its estimate line is visible anywhere.
--
-- DATA LOSS ON ROLLBACK: take_off_decisions rows (human dispositions and trades) and the
-- material_items take_off_* snapshot columns are dropped. Export them first if any human
-- has made decisions.

drop view if exists public.take_off_lines;

drop function if exists public.materialize_take_off(uuid);
drop function if exists public.set_take_off_decision(uuid, text, uuid);

drop trigger if exists material_items_take_off_guard on public.material_items;
drop trigger if exists material_items_take_off_removed on public.material_items;
drop function if exists public.material_items_take_off_guard();
drop function if exists public.material_items_take_off_removed();

drop trigger if exists take_off_decisions_validate on public.take_off_decisions;
drop function if exists public.take_off_decisions_validate();
drop table if exists public.take_off_decisions;

drop index if exists public.material_items_one_per_estimate_line;
-- Fails if two material items now share an estimate line on the SAME trade, which the
-- forward migration's global uniqueness makes impossible; it cannot fail on its own data.
CREATE UNIQUE INDEX material_items_take_off_uniq ON public.material_items USING btree (work_order_id, estimate_line_item_id) WHERE (estimate_line_item_id IS NOT NULL);

alter table public.material_items
  drop column if exists take_off_description,
  drop column if exists take_off_quantity,
  drop column if exists take_off_unit;

CREATE OR REPLACE FUNCTION public.generate_take_off(p_work_order_id uuid, p_estimate_line_item_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id        uuid;
  v_kind          text;
  v_job_id        uuid;
  v_estimate_id   uuid;
  v_trade         text;
  v_ids           uuid[];
  v_requested     int;
  v_valid         int;
  v_created       int;
  v_next_sort     int;
  v_live_trades   int;
  v_with_takeoff  int;
  v_master_id     uuid;
  v_sign_off_at   timestamptz;
  v_actor_id      uuid;
begin
  -- ---- existence + org, before anything is disclosed ----------------------
  select w.org_id, w.kind, w.job_id, w.estimate_id
    into v_org_id, v_kind, v_job_id, v_estimate_id
  from public.work_orders w
  where w.id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  -- ---- the crew gate, at the RPC layer ------------------------------------
  -- A take-off reads estimate_line_items, which carries a RESTRICTIVE
  -- can_view_financials() policy AND permissive policies requiring
  -- view_estimates. This function is SECURITY DEFINER and so bypasses both;
  -- restating them here is what stops the take-off path from being a way
  -- around the gates that guard the same rows everywhere else.
  --   coalesce is not decoration: §7.1 rule 5 — PL/pgSQL treats a NULL IF
  --   condition as FALSE, so `if not (null)` would silently ALLOW.
  if not coalesce(public.can_view_financials(v_org_id), false) then
    raise exception 'a take-off reads the estimate''s priced line items, and your role cannot view financials';
  end if;

  if not coalesce(public.has_capability(v_org_id, 'view_estimates'), false) then
    raise exception 'a take-off reads the estimate''s line items, and your role cannot view estimates';
  end if;

  -- ---- CLAUSE (b): the master is not a destination ------------------------
  -- The master is where a PM forms the intention, so it answers rather than
  -- 404s — and it answers by NAMING THE COUNT and the next action, which is
  -- A1.4's refuse-and-name-the-count precedent. On a job with zero trades this
  -- is clause (b)'s refusal verbatim; above zero it is a routing message.
  if v_kind = 'master' then
    select count(*) into v_live_trades
    from public.work_orders t
    where t.job_id = v_job_id and t.kind = 'trade' and t.voided_at is null;

    if v_live_trades = 0 then
      raise exception 'this job has 0 trade work orders, so a take-off has nowhere to land — materials attach to a trade. Create trades first, then open a trade and run the take-off there.';
    end if;

    raise exception 'a take-off runs from a trade, not from the master — this job has % live trade work order(s). Open the trade these materials belong to and run it there.', v_live_trades;
  end if;

  -- ---- A1.3b's level check, CALLED, not reimplemented ---------------------
  -- Same helper add_material_item uses. The only branch that does not reach it
  -- is the master branch above, which raises rather than inserting, so there is
  -- no path to an insert that skips it.
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');

  select w.trade into v_trade
  from public.work_orders w where w.id = p_work_order_id;

  -- ---- the selection ------------------------------------------------------
  -- Deduplicated first: the same id ticked twice must not read as a line that
  -- failed validation below, and must not try to insert twice in one statement
  -- (ON CONFLICT does not see rows inserted by its own command).
  select coalesce(array_agg(distinct x), '{}'::uuid[]) into v_ids
  from unnest(p_estimate_line_item_ids) as t(x)
  where x is not null;

  v_requested := coalesce(array_length(v_ids, 1), 0);

  if v_requested = 0 then
    raise exception 'no estimate line items were selected — tick the lines that belong to this trade, then run the take-off';
  end if;

  -- Every selected line must be on THIS job's estimate. A line from another
  -- estimate is refused with its count and NOTHING is taken off, rather than
  -- the valid ones landing and the rest vanishing silently.
  select count(*) into v_valid
  from public.estimate_line_items e
  where e.id = any(v_ids)
    and e.org_id = v_org_id
    and e.estimate_id = v_estimate_id;

  if v_valid <> v_requested then
    raise exception '% of % selected line items are not on this job''s estimate — nothing was taken off',
      v_requested - v_valid, v_requested;
  end if;

  -- ---- the insert ---------------------------------------------------------
  select coalesce(max(m.sort_order) + 1, 0) into v_next_sort
  from public.material_items m
  where m.work_order_id = p_work_order_id;

  -- NO MONEY CROSSES THIS BOUNDARY. description, quantity, unit and product_id
  -- come over; unit_price and line_total do not, and material_items has no
  -- column that could hold them. That is the structural half of the crew gate —
  -- there is no cost or sell figure on a material item to leak.
  with src as (
    select e.id, e.description, e.quantity, e.unit, e.product_id,
           row_number() over (order by e.sort_order, e.id) - 1 as rn
    from public.estimate_line_items e
    where e.id = any(v_ids)
  ),
  ins as (
    insert into public.material_items
      (org_id, work_order_id, name, quantity, unit, product_id,
       estimate_line_item_id, sort_order)
    select v_org_id, p_work_order_id, src.description, src.quantity, src.unit,
           src.product_id, src.id, v_next_sort + src.rn
    from src
    -- IDEMPOTENCE. Re-running the same lines onto the same trade creates
    -- nothing and raises nothing; the count comes back as skipped_existing.
    on conflict (work_order_id, estimate_line_item_id)
      where estimate_line_item_id is not null
    do nothing
    returning 1
  )
  select count(*) into v_created from ins;

  -- ---- audit parity with add_material_item --------------------------------
  -- A take-off after sign-off is the same event add_material_item logs one row
  -- for. Reaching material_items by a new path must not lose that trail; one
  -- row for the take-off, not one per material.
  select s.master_id, s.sign_off_at into v_master_id, v_sign_off_at
  from public.job_master_sign_off(p_work_order_id) s;

  if v_sign_off_at is not null and v_created > 0 then
    select id into v_actor_id from public.profiles where id = auth.uid();
    insert into public.work_order_activity (work_order_id, org_id, action, to_value, actor_id)
    values (v_master_id, v_org_id, 'material_added_after_signoff',
            format('take-off: %s material(s) (%s)', v_created, coalesce(v_trade, 'trade')),
            v_actor_id);
  end if;

  -- ---- CLAUSE (a)'s REPORTED FIGURE ---------------------------------------
  -- In the controller's amended wording (§5.2, 2026-08-28): TRADES THAT HAVE
  -- RECEIVED A TAKE-OFF, OUT OF THE JOB'S LIVE TRADE COUNT. It is computed off
  -- estimate_line_item_id, so a hand-added material does not make a trade look
  -- taken off.
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
    'work_order_id',        p_work_order_id,
    'job_id',               v_job_id,
    'trade',                v_trade,
    'lines_requested',      v_requested,
    'created',              v_created,
    'skipped_existing',     v_requested - v_created,
    'trades_with_take_off', v_with_takeoff,
    'live_trade_count',     v_live_trades
  );
end;
$function$;
revoke execute on function public.generate_take_off(uuid, uuid[]) from public, anon;
