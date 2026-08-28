-- A2.2 — Take-off generation. Estimate line items -> material_items on a trade.
--
-- Carries TWO CONTROLLER DECISIONS, both taken 2026-08-28 in answer to the two
-- §5 gaps escalated 2026-08-27. They are recorded here because the shape of
-- this migration is unreadable without them.
--
-- CONTROLLER DECISION 1 (2026-08-28) — THE TAKE-OFF RUNS FROM A TRADE, NOT
-- FROM THE JOB. Nothing on estimate_line_items names a trade (the columns are
-- product_id, description, quantity, unit_price, unit, sort_order, scope_key),
-- and A2.2 forbids inferring one from line-item categories, so "the correct
-- trade" had no definition. It now has one: the PM opens a trade and picks the
-- lines that belong to it, so the RPC takes p_work_order_id PLUS a line-item id
-- array. Scope structure stays the PM's to declare (A2.2's own stated reason)
-- and no new column on estimate_line_items is needed.
--   scope_key was the nearest-looking proxy and is NOT the answer: it is NULL
--   on 21 of 21 live line items, so a sweep by it would have returned clean.
--   That is §6.9's new failure class appearing in our own data.
--
-- CONTROLLER DECISION 2 (2026-08-28) — material_items GETS PROVENANCE. Without
-- it a second take-off duplicates every row and there is nothing to be
-- idempotent on: a guard needs an identity to key on. estimate_line_item_id is
-- NULLABLE so hand-added materials stay legal; product_id and unit come across
-- so A2.3's PO path and A2.1's catalog line up rather than diverging.
--   Done now because material_items is at ZERO ROWS — the cheapest this
--   change will ever be.

-- ---------------------------------------------------------------------------
-- 1 · PROVENANCE COLUMNS  (Decision 2)
-- ---------------------------------------------------------------------------

alter table public.material_items
  add column if not exists estimate_line_item_id uuid
    references public.estimate_line_items(id) on delete set null,
  add column if not exists product_id uuid
    references public.products(id) on delete set null,
  add column if not exists unit text;

-- ON DELETE SET NULL on both FKs, deliberately, and it is the same choice
-- estimate_line_items.product_id already made. A material that has been taken
-- off is a real thing that will be ordered and delivered; deleting the estimate
-- line it came from must not delete it, it must only cost it its provenance —
-- which lands it back in the nullable, hand-added case the column already
-- allows for.

-- THE IDEMPOTENCY KEY. Partial, because NULL is the legal hand-added case and a
-- plain unique constraint would let exactly one hand-added material exist per
-- work order in some planners and none in others.
create unique index if not exists material_items_take_off_uniq
  on public.material_items (work_order_id, estimate_line_item_id)
  where estimate_line_item_id is not null;

-- §7.1 rule 8. material_items pre-dates that rule and still carries
-- anon=arwdDxtm; this migration widens the table, so it revokes the table it
-- widens rather than leaving new columns reachable under an old grant. The
-- other tables in that state are §6.9's, not this task's. Nothing outside the
-- database reads material_items as anon — every read in src/ is behind
-- getSession() — so this cannot break the deployed UI (rule 5b).
revoke all on table public.material_items from anon;

-- ---------------------------------------------------------------------------
-- 2 · THE TAKE-OFF  (Decision 1)
-- ---------------------------------------------------------------------------
-- New name, so there is no old signature to DROP and no overload to create
-- (§7.1 rule 1); pg_proc carried no %take_off% function before this ran.

create or replace function public.generate_take_off(
  p_work_order_id uuid,
  p_estimate_line_item_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
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

-- §7.1 rule 7. The grant being removed is on PUBLIC — it shows in proacl as the
-- leading `=X/postgres` with no grantee before the `=`, and a revoke naming
-- only anon would be a NO-OP. `authenticated` is KEPT, per the carve-out's
-- test answered for THIS function: src/lib/coordination/actions.ts calls
-- generate_take_off from a server action as `authenticated`, so that grant is
-- the call path, not an attacker's.
revoke execute on function public.generate_take_off(uuid, uuid[]) from public, anon;