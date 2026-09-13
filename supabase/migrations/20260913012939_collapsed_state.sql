-- COLLAPSED STATE. Track S · 2026-09-12.
-- Contents decided by supabase/sweeps/collapsed_state_sweep.sql, first run the same
-- evening: 50 owned tables, 545 columns, 203 defaults, 83 non-boilerplate.
-- Rollback: supabase/rollbacks/20260912_collapsed_state_rollback.sql
--
-- Four changes, each a finding PROVED BY BEHAVIOUR before it was changed.

-- ===========================================================================
-- PART A — PRICING: A RULE IS AN INPUT; A PRICE IS AN OUTPUT.
--
-- WHAT THE TASK SAID, AND WHAT WAS TRUE. The task said products.markup is
-- GENERATED. It is not — A2.1c (20260826132626) un-generated it on 2026-08-26,
-- and create_product has accepted p_markup ever since. "Enter a markup, get a
-- sell price" has worked for seventeen days.
--
-- WHAT WAS STILL BROKEN, PROVED: a product entered as cost 100 + MARKUP 50% and a
-- product entered as cost 100 + SELL 150 are stored BYTE-IDENTICALLY
-- (cost 100, sell 150, markup 50). On a cost-only edit, update_product keeps the
-- stored sell and re-derives markup — so after cost 100 -> 120 BOTH read sell 150,
-- markup 25%. The user who priced by margin lost half of it and was not told.
-- THE TABLE COULD NOT TELL THE TWO APART. That is an axis-1 collapse: the same
-- row meant "the user chose this price" AND "the user chose this margin".
--
-- THE FIX STORES WHICH ONE THE USER CHOSE. price_method + price_value, and sell
-- becomes an output:
--   percent -> round(cost x (1 + value/100), 2)   FOLLOWS COST
--   amount  -> round(cost + value, 2)             FOLLOWS COST
--   fixed   -> value, typed outright              DOES NOT MOVE
-- A fixed row whose cost changes keeps its price and RAISES A REVIEW REASON IN
-- WORDS, because its margin moved and nobody chose that.
--
-- THIS COMPLETES JACOB'S 2026-08-26 DECISION RATHER THAN OVERTURNING IT. Pricing
-- stays bidirectional: an existing caller that sends p_sell gets `fixed`, one
-- that sends p_markup gets `percent`. What changes is that the choice is kept.
-- sell and markup REMAIN STORED so every reader — the picker, the estimate
-- snapshot, the crew gate — is untouched; products_markup_matches_prices holds.
--
-- products held 0 rows when this ran, which is the whole reason it is cheap.
-- Design credited to Material Matrix.
-- ===========================================================================
alter table public.products
  add column price_method text null,
  add column price_value numeric null,
  add column price_review_reason text null;

alter table public.products
  add constraint products_price_method_valid
    check (price_method is null or price_method in ('percent', 'amount', 'fixed')),
  add constraint products_price_method_value_together
    check ((price_method is null) = (price_value is null));

comment on column public.products.price_method is
  'HOW the user priced this item: percent | amount | fixed | NULL (unpriced). An INPUT. sell is the OUTPUT.
   percent and amount follow cost; fixed does not. Without this column an item priced by margin and one priced
   by a typed sell price were stored identically, and a cost change silently converted the first into the second.';
comment on column public.products.price_review_reason is
  'Set IN WORDS when a fixed-price item''s cost changes, because its margin moved and nobody chose that.
   Cleared the next time a price is deliberately set. NULL means nothing to review.';

-- The single place a price is derived from a method. Internal: nothing outside
-- the database calls it, so `authenticated` is revoked too (rule 7's carve-out).
create function public.price_from_method(p_cost numeric, p_method text, p_value numeric)
returns numeric language plpgsql immutable set search_path to 'public'
as $function$
begin
  if p_method is null then
    return null;
  elsif p_method = 'fixed' then
    return round(p_value, 2);
  elsif p_method = 'percent' then
    if p_cost is null or p_cost = 0 then
      raise exception 'a percentage markup needs a non-zero cost — enter a fixed price for this item instead';
    end if;
    return round(p_cost * (1 + p_value / 100), 2);
  elsif p_method = 'amount' then
    if p_cost is null then
      raise exception 'an amount markup needs a cost — enter a fixed price for this item instead';
    end if;
    return round(p_cost + p_value, 2);
  end if;
  raise exception '% is not a pricing method (percent, amount or fixed)', p_method;
end;
$function$;

-- create_product gains two TRAILING optional parameters. A changed signature is
-- an OVERLOAD (rule 1), so the exact old signature is dropped first.
drop function if exists public.create_product(uuid, text, text, text, numeric, numeric, numeric);

create function public.create_product(
  p_org_id uuid, p_name text,
  p_category text default null, p_unit text default null,
  p_cost numeric default null, p_sell numeric default null, p_markup numeric default null,
  p_price_method text default null, p_price_value numeric default null
)
returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare v_id uuid; v_method text; v_value numeric; v_sell numeric; v_markup numeric;
begin
  if p_org_id is null or p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of that org';
  end if;
  if not coalesce(public.has_capability(p_org_id, 'manage_catalog'), false) then
    raise exception 'you do not have permission to change the catalog';
  end if;
  if (p_cost is not null or p_sell is not null or p_markup is not null or p_price_method is not null)
     and not coalesce(public.can_view_financials(p_org_id), false) then
    raise exception 'not permitted to set catalog cost or pricing';
  end if;

  -- Resolve WHICH the user chose. An explicit method wins; the legacy inputs map
  -- to the method they always meant.
  if p_price_method is not null then
    v_method := p_price_method; v_value := p_price_value;
  elsif p_sell is not null then
    -- sell and markup both supplied must agree (derive_catalog_price refuses if not);
    -- sell wins because sell is the money, so the item is FIXED.
    perform public.derive_catalog_price(p_cost, p_sell, p_markup);
    v_method := 'fixed'; v_value := p_sell;
  elsif p_markup is not null then
    v_method := 'percent'; v_value := p_markup;
  end if;

  v_sell := public.price_from_method(p_cost, v_method, v_value);
  v_markup := case when p_cost is null or v_sell is null or p_cost = 0 then null
                   else round(((v_sell - p_cost) / p_cost) * 100, 2) end;

  insert into public.products (org_id, name, category, unit, cost, sell, markup,
                               price_method, price_value, created_by)
  values (p_org_id, btrim(p_name),
          nullif(btrim(coalesce(p_category, '')), ''),
          nullif(btrim(coalesce(p_unit, '')), ''),
          p_cost, v_sell, v_markup, v_method, v_value, auth.uid())
  returning id into v_id;
  return v_id;
end;
$function$;

-- update_product: signature (uuid, jsonb) UNCHANGED, so CREATE OR REPLACE replaces.
-- New patch keys price_method / price_value. The deciding case lives here.
create or replace function public.update_product(p_product_id uuid, p_patch jsonb)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_row public.products; v_key text;
  v_cost numeric; v_method text; v_value numeric; v_sell numeric; v_markup numeric;
  v_price_touched boolean; v_review text;
begin
  select * into v_row from public.products where id = p_product_id;
  if v_row.id is null then raise exception 'catalog item not found'; end if;
  if v_row.org_id not in (select my_org_ids()) then raise exception 'not a member of that org'; end if;
  if not coalesce(public.has_capability(v_row.org_id, 'manage_catalog'), false) then
    raise exception 'you do not have permission to change the catalog';
  end if;

  for v_key in select jsonb_object_keys(coalesce(p_patch, '{}'::jsonb)) loop
    if v_key not in ('name','category','unit','cost','sell','markup','active','price_method','price_value') then
      raise exception 'unknown catalog field: %', v_key;
    end if;
  end loop;

  v_price_touched := (p_patch ? 'sell' or p_patch ? 'markup' or p_patch ? 'price_method' or p_patch ? 'price_value');
  if (p_patch ? 'cost' or v_price_touched) and not coalesce(public.can_view_financials(v_row.org_id), false) then
    raise exception 'not permitted to set catalog cost or pricing';
  end if;

  v_cost := case when p_patch ? 'cost' then (p_patch->>'cost')::numeric else v_row.cost end;

  -- WHICH RULE governs after this edit?
  if p_patch ? 'price_method' then
    v_method := p_patch->>'price_method';
    v_value  := case when p_patch ? 'price_value' then (p_patch->>'price_value')::numeric else v_row.price_value end;
  elsif p_patch ? 'sell' then
    perform public.derive_catalog_price(v_cost, (p_patch->>'sell')::numeric,
              case when p_patch ? 'markup' then (p_patch->>'markup')::numeric else null end);
    v_method := 'fixed'; v_value := (p_patch->>'sell')::numeric;
  elsif p_patch ? 'markup' then
    v_method := 'percent'; v_value := (p_patch->>'markup')::numeric;
  elsif p_patch ? 'price_value' then
    v_method := v_row.price_method; v_value := (p_patch->>'price_value')::numeric;
  else
    -- NO PRICE FIELD IN THE PATCH: the stored rule governs. This is the branch a
    -- supplier cost change takes, and it is the whole point.
    v_method := v_row.price_method; v_value := v_row.price_value;
  end if;

  v_sell := public.price_from_method(v_cost, v_method, v_value);
  v_markup := case when v_cost is null or v_sell is null or v_cost = 0 then null
                   else round(((v_sell - v_cost) / v_cost) * 100, 2) end;

  -- THE REVIEW REASON. A deliberate price edit clears it. A cost change on a FIXED
  -- item sets it in words, because the margin moved and nobody chose that.
  if v_price_touched then
    v_review := null;
  elsif (p_patch ? 'cost') and v_method = 'fixed' and v_cost is distinct from v_row.cost then
    v_review := format('cost changed from %s to %s; the fixed price %s was held, so the markup is now %s%%. Confirm the price or switch this item to a percentage.',
                       coalesce(v_row.cost::text, 'none'), coalesce(v_cost::text, 'none'),
                       coalesce(v_sell::text, 'none'), coalesce(v_markup::text, 'undefined'));
  else
    v_review := v_row.price_review_reason;
  end if;

  update public.products set
    name     = case when p_patch ? 'name' then coalesce(nullif(btrim(p_patch->>'name'), ''), name) else name end,
    category = case when p_patch ? 'category' then nullif(btrim(coalesce(p_patch->>'category','')), '') else category end,
    unit     = case when p_patch ? 'unit' then nullif(btrim(coalesce(p_patch->>'unit','')), '') else unit end,
    cost     = v_cost,
    sell     = v_sell,
    markup   = v_markup,
    price_method = v_method,
    price_value  = v_value,
    price_review_reason = v_review,
    active   = case when p_patch ? 'active' then (p_patch->>'active')::boolean else active end
  where id = p_product_id;
end;
$function$;

-- ===========================================================================
-- PART B — ready_by_source GETS A THIRD VALUE. A MISSING STATE IS NOT A WRONG
-- VALUE; THE FIX IS A STATE, NOT A CORRECTION.
--
-- Keeping the date when every PO is cancelled was the RIGHT ruling — nulling it
-- would silently unblock a schedule. The error was having nowhere to put the
-- result: recompute wrote 'manual', so 'manual' meant both "a human typed this"
-- and "this came from purchase orders that no longer exist".
--
-- AND A SECOND LEAK ON THE SAME COLUMN, found by reading the writers:
-- update_material_item wrote ready_by and NEVER touched ready_by_source, so a date
-- a human typed onto a PO-derived item kept claiming it came from a purchase order.
-- Adding 'orphaned' alone would have left 'purchase_order' meaning two things.
--
-- 'orphaned' = the date was derived from purchase-order promises and no live
-- promise remains. The existing values are NOT rewritten.
-- ===========================================================================
alter table public.material_items drop constraint material_items_ready_by_source_check;
alter table public.material_items add constraint material_items_ready_by_source_check
  check (ready_by_source = any (array['manual'::text, 'purchase_order'::text, 'orphaned'::text]));

comment on column public.material_items.ready_by_source is
  'WHICH BRANCH FIRED. manual = a human set this date and no live purchase-order promise governs it.
   purchase_order = derived as max(promised_date) over non-cancelled PO lines. orphaned = it WAS derived from
   promises and none remain, so the date is kept (nulling would silently unblock a schedule) but nothing stands
   behind it. Documents a decision already made; never an input to making one.';

create or replace function public.recompute_material_item_ready_by(p_material_item_id uuid)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare v_max date; v_any boolean;
begin
  select max(l.promised_date), count(*) > 0 into v_max, v_any
  from public.purchase_order_lines l
  join public.purchase_orders po on po.id = l.purchase_order_id
  where l.material_item_id = p_material_item_id
    and po.status <> 'cancelled'
    and l.promised_date is not null;

  if coalesce(v_any, false) then
    update public.material_items
       set ready_by = v_max, ready_by_source = 'purchase_order', updated_at = now()
     where id = p_material_item_id;
  else
    -- Empty promise set. The date is KEPT. What changes is that the row now says
    -- where it came from: a PO-derived date becomes 'orphaned'; a typed one stays
    -- 'manual'. Before this, both became 'manual'.
    update public.material_items
       set ready_by_source = case when ready_by_source in ('purchase_order', 'orphaned')
                                  then 'orphaned' else 'manual' end,
           updated_at = now()
     where id = p_material_item_id;
  end if;
end;
$function$;

-- update_material_item: signature UNCHANGED. When a human supplies a date the row
-- is stamped 'manual', then the derivation runs, so ruling (a) still holds — while
-- live promises exist, max(promise) remains the single writer.
create or replace function public.update_material_item(
  p_material_item_id uuid, p_name text default null, p_quantity numeric default null,
  p_ready_by date default null, p_sort_order integer default null
)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_org_id uuid; v_work_order_id uuid; v_trade text; v_master_id uuid; v_sign_off_at timestamptz;
  v_old_name text; v_old_quantity numeric; v_old_ready_by date; v_actor_id uuid;
begin
  select mi.org_id, mi.work_order_id, mi.name, mi.quantity, mi.ready_by
  into v_org_id, v_work_order_id, v_old_name, v_old_quantity, v_old_ready_by
  from public.material_items mi where mi.id = p_material_item_id;

  if v_org_id is null then
    raise exception 'material item not found or not accessible: %', p_material_item_id;
  end if;
  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'material item not found or not accessible: %', p_material_item_id;
  end if;

  select w.trade into v_trade from public.work_orders w where w.id = v_work_order_id;
  select s.master_id, s.sign_off_at into v_master_id, v_sign_off_at
  from public.job_master_sign_off(v_work_order_id) s;

  update public.material_items
  set name = coalesce(p_name, name),
      quantity = coalesce(p_quantity, quantity),
      ready_by = coalesce(p_ready_by, ready_by),
      ready_by_source = case when p_ready_by is not null then 'manual' else ready_by_source end,
      sort_order = coalesce(p_sort_order, sort_order),
      updated_at = now()
  where id = p_material_item_id;

  if p_ready_by is not null then
    perform public.recompute_material_item_ready_by(p_material_item_id);
  end if;

  if v_sign_off_at is not null then
    select id into v_actor_id from public.profiles where id = auth.uid();
    insert into public.work_order_activity (work_order_id, org_id, action, from_value, to_value, actor_id)
    values (
      coalesce(v_master_id, v_work_order_id), v_org_id, 'material_updated_after_signoff',
      format('%s (qty %s%s)', v_old_name, v_old_quantity, case when v_old_ready_by is not null then ', ready ' || v_old_ready_by else '' end),
      format('%s (qty %s%s) [%s]', coalesce(p_name, v_old_name), coalesce(p_quantity, v_old_quantity), case when coalesce(p_ready_by, v_old_ready_by) is not null then ', ready ' || coalesce(p_ready_by, v_old_ready_by) else '' end, coalesce(v_trade, 'trade')),
      v_actor_id
    );
  end if;
end;
$function$;

-- ===========================================================================
-- PART C1 — THE READY-BY GATE MOVES TO THE TABLE.
--
-- PROVED 2026-09-12: with the tenant's enforce_stage_gating ON, add_schedule_block
-- REFUSED a block starting before its materials' ready_by — and a DIRECT INSERT of
-- the identical block, which RLS permits to any member holding `schedule`, SAVED,
-- storing ready_by_conflict = false: the column DEFAULT, asserting "no conflict"
-- where there was one. A guard proved correct at the FUNCTION was never proved
-- reachable from the TABLE. It was the dangerous kind: a default substituted.
--
-- The fact is now computed at the write for every writer. The RPCs still compute
-- and refuse first on their own path; the trigger makes the same answer hold for
-- a direct write, and overwrites whatever a writer supplied.
--
-- SECURITY DEFINER IS LOAD-BEARING. tenant_enforces_stage_gating has
-- `authenticated` revoked, so an invoker-rights trigger would fail every direct
-- write with 42501 — A2.0b's lesson, the same shape.
-- ===========================================================================
create function public.schedule_blocks_ready_by_gate()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
declare v_name text; v_ready date;
begin
  select name, ready_by into v_name, v_ready
  from public.material_items
  where work_order_id = new.work_order_id and ready_by is not null
  order by ready_by desc limit 1;

  new.ready_by_conflict := v_ready is not null and new.start_date < v_ready;
  new.ready_by_conflict_reason := case when new.ready_by_conflict
    then format('materials not ready until %s (%s)', v_ready, v_name) else null end;

  if new.ready_by_conflict and public.tenant_enforces_stage_gating(new.org_id) then
    raise exception '%. This workspace enforces stage gating, so the schedule block was not saved. Move the start date to % or later, or turn off enforce_stage_gating.',
      new.ready_by_conflict_reason, v_ready;
  end if;
  return new;
end;
$function$;

create trigger schedule_blocks_ready_by_gate
  before insert or update of start_date, work_order_id on public.schedule_blocks
  for each row execute function public.schedule_blocks_ready_by_gate();

-- ===========================================================================
-- PART C2 — AN OMITTED PURCHASE-ORDER QUANTITY NO LONGER ORDERS ONE.
--
-- PROVED 2026-09-12: add_purchase_order_line(... p_quantity_ordered DEFAULT 1)
-- guarded `is null or <= 0`. Passing NULL was refused. OMITTING the argument
-- ordered 1 — the refusal was unreachable by omission, and a supplier would be
-- told a quantity nobody chose. Material Matrix's `unit_type DEFAULT
-- 'linear_foot'`, in our code.
-- REACHABLE FROM THE LIVE UI, not only in theory: src/lib/purchasing/actions.ts
-- sends `p_quantity_ordered: Number.isFinite(qty) ? qty : undefined`, so a blank
-- quantity field omits the argument.
--
-- The parameter default becomes NULL, so an omission reaches the existing guard.
-- A default cannot be removed by CREATE OR REPLACE, so the exact signature is
-- dropped first. The COLUMN default goes too, so a direct INSERT that omits the
-- quantity hits NOT NULL — a CONSTRAINT preventing the value, the safe kind.
-- ===========================================================================
drop function if exists public.add_purchase_order_line(uuid, uuid, numeric, date);

create function public.add_purchase_order_line(
  p_po_id uuid, p_material_item_id uuid,
  p_quantity_ordered numeric default null, p_promised_date date default null
)
returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare v_org_id uuid; v_item_org uuid; v_id uuid;
begin
  select org_id into v_org_id from public.purchase_orders where id = p_po_id;
  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'purchase order not found or not accessible: %', p_po_id;
  end if;
  if not public.has_capability(v_org_id, 'manage_purchasing') then
    raise exception 'your role cannot edit purchase orders in this workspace';
  end if;
  select org_id into v_item_org from public.material_items where id = p_material_item_id;
  if v_item_org is null then raise exception 'material item not found: %', p_material_item_id; end if;
  if v_item_org <> v_org_id then
    raise exception 'material item % belongs to a different organization than purchase order %', p_material_item_id, p_po_id;
  end if;
  if p_quantity_ordered is null then
    raise exception 'enter a quantity to order — a supplier cannot be sent an order with no quantity';
  end if;
  if p_quantity_ordered <= 0 then
    raise exception 'quantity ordered must be greater than zero';
  end if;

  insert into public.purchase_order_lines (org_id, purchase_order_id, material_item_id, quantity_ordered, promised_date)
  values (v_org_id, p_po_id, p_material_item_id, p_quantity_ordered, p_promised_date)
  returning id into v_id;

  insert into public.purchase_order_line_promises (org_id, purchase_order_line_id, promised_date, recorded_by)
  values (v_org_id, v_id, p_promised_date, auth.uid());

  perform public.recompute_material_item_ready_by(p_material_item_id);
  return v_id;
end;
$function$;

alter table public.purchase_order_lines alter column quantity_ordered drop default;

-- ===========================================================================
-- GRANTS — rule 7, per function.
-- ===========================================================================
revoke execute on function public.price_from_method(numeric, text, numeric) from public, anon, authenticated;
revoke execute on function public.create_product(uuid, text, text, text, numeric, numeric, numeric, text, numeric) from public, anon;
revoke execute on function public.update_product(uuid, jsonb) from public, anon;
revoke execute on function public.recompute_material_item_ready_by(uuid) from public, anon, authenticated;
revoke execute on function public.update_material_item(uuid, text, numeric, date, integer) from public, anon;
revoke execute on function public.schedule_blocks_ready_by_gate() from public, anon, authenticated;
revoke execute on function public.add_purchase_order_line(uuid, uuid, numeric, date) from public, anon;

-- Rule 3: never trust the success response.
do $$
begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='create_product') <> 1
    then raise exception 'create_product has more than one overload'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='add_purchase_order_line') <> 1
    then raise exception 'add_purchase_order_line has more than one overload'; end if;
  if (select column_default from information_schema.columns
      where table_schema='public' and table_name='purchase_order_lines' and column_name='quantity_ordered') is not null
    then raise exception 'quantity_ordered still has a default'; end if;
  if not exists (select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid
                 where c.relname='schedule_blocks' and t.tgname='schedule_blocks_ready_by_gate')
    then raise exception 'schedule gate trigger not attached'; end if;
end $$;