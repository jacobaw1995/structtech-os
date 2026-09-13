-- ROLLBACK for 20260912 collapsed_state.
-- Every replaced body below was captured from pg_get_functiondef()/prosrc on the
-- LIVE database 2026-09-12 BEFORE the change (§7.1 Rule 1). Signatures copied
-- from pg_get_function_identity_arguments(), never retyped (rule 2).
--
-- RESTORING THIS RE-OPENS, in order: a product priced by margin loses that margin
-- silently when cost moves; an orphaned ready_by is indistinguishable from a typed
-- one, and a typed date keeps a purchase-order label; a direct INSERT into
-- schedule_blocks bypasses an opted-in stage gate and records "no conflict"; and an
-- omitted purchase-order quantity silently orders 1.
--
-- PRODUCTS: 0 rows existed when the forward migration ran, so dropping the three
-- pricing columns loses no data that predates it.

-- PART C1
drop trigger if exists schedule_blocks_ready_by_gate on public.schedule_blocks;
drop function if exists public.schedule_blocks_ready_by_gate();

-- PART C2
alter table public.purchase_order_lines alter column quantity_ordered set default 1;
drop function if exists public.add_purchase_order_line(uuid, uuid, numeric, date);
CREATE OR REPLACE FUNCTION public.add_purchase_order_line(p_po_id uuid, p_material_item_id uuid, p_quantity_ordered numeric DEFAULT 1, p_promised_date date DEFAULT NULL::date)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
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
  if p_quantity_ordered is null or p_quantity_ordered <= 0 then
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
revoke execute on function public.add_purchase_order_line(uuid, uuid, numeric, date) from public, anon;

-- PART B
CREATE OR REPLACE FUNCTION public.recompute_material_item_ready_by(p_material_item_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_max date;
  v_any boolean;
begin
  select max(l.promised_date), count(*) > 0
    into v_max, v_any
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
    update public.material_items
       set ready_by_source = 'manual', updated_at = now()
     where id = p_material_item_id;
  end if;
end;
$function$;
revoke execute on function public.recompute_material_item_ready_by(uuid) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.update_material_item(p_material_item_id uuid, p_name text DEFAULT NULL::text, p_quantity numeric DEFAULT NULL::numeric, p_ready_by date DEFAULT NULL::date, p_sort_order integer DEFAULT NULL::integer)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
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
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'material item not found or not accessible: %', p_material_item_id;
  end if;
  select w.trade into v_trade from public.work_orders w where w.id = v_work_order_id;
  select s.master_id, s.sign_off_at into v_master_id, v_sign_off_at
  from public.job_master_sign_off(v_work_order_id) s;
  update public.material_items
  set name = coalesce(p_name, name), quantity = coalesce(p_quantity, quantity),
      ready_by = coalesce(p_ready_by, ready_by), sort_order = coalesce(p_sort_order, sort_order),
      updated_at = now()
  where id = p_material_item_id;
  if v_sign_off_at is not null then
    select id into v_actor_id from public.profiles where id = auth.uid();
    insert into public.work_order_activity (work_order_id, org_id, action, from_value, to_value, actor_id)
    values (coalesce(v_master_id, v_work_order_id), v_org_id, 'material_updated_after_signoff',
      format('%s (qty %s%s)', v_old_name, v_old_quantity, case when v_old_ready_by is not null then ', ready ' || v_old_ready_by else '' end),
      format('%s (qty %s%s) [%s]', coalesce(p_name, v_old_name), coalesce(p_quantity, v_old_quantity), case when coalesce(p_ready_by, v_old_ready_by) is not null then ', ready ' || coalesce(p_ready_by, v_old_ready_by) else '' end, coalesce(v_trade, 'trade')),
      v_actor_id);
  end if;
end;
$function$;
revoke execute on function public.update_material_item(uuid, text, numeric, date, integer) from public, anon;

-- The 'orphaned' value can only be removed once no row carries it.
update public.material_items set ready_by_source = 'manual' where ready_by_source = 'orphaned';
alter table public.material_items drop constraint if exists material_items_ready_by_source_check;
alter table public.material_items add constraint material_items_ready_by_source_check
  check (ready_by_source = any (array['manual'::text, 'purchase_order'::text]));

-- PART A
drop function if exists public.create_product(uuid, text, text, text, numeric, numeric, numeric, text, numeric);
CREATE OR REPLACE FUNCTION public.create_product(p_org_id uuid, p_name text, p_category text DEFAULT NULL::text, p_unit text DEFAULT NULL::text, p_cost numeric DEFAULT NULL::numeric, p_sell numeric DEFAULT NULL::numeric, p_markup numeric DEFAULT NULL::numeric)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_id uuid; v_sell numeric; v_markup numeric;
begin
  if p_org_id is null or p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of that org';
  end if;
  if not coalesce(public.has_capability(p_org_id, 'manage_catalog'), false) then
    raise exception 'you do not have permission to change the catalog';
  end if;
  if (p_cost is not null or p_sell is not null or p_markup is not null)
     and not coalesce(public.can_view_financials(p_org_id), false) then
    raise exception 'not permitted to set catalog cost, sell or markup';
  end if;
  select out_sell, out_markup into v_sell, v_markup
  from public.derive_catalog_price(p_cost, p_sell, p_markup);
  insert into public.products (org_id, name, category, unit, cost, sell, markup, created_by)
  values (p_org_id, btrim(p_name),
          nullif(btrim(coalesce(p_category, '')), ''),
          nullif(btrim(coalesce(p_unit, '')), ''),
          p_cost, v_sell, v_markup, auth.uid())
  returning id into v_id;
  return v_id;
end;
$function$;
revoke execute on function public.create_product(uuid, text, text, text, numeric, numeric, numeric) from public, anon;
-- update_product: signature (uuid, jsonb) unchanged by the forward migration, so
-- CREATE OR REPLACE restores it. Body captured from prosrc 2026-09-12.
CREATE OR REPLACE FUNCTION public.update_product(p_product_id uuid, p_patch jsonb)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_row public.products;
  v_key text;
  v_cost numeric; v_sell_in numeric; v_markup_in numeric;
  v_sell numeric; v_markup numeric;
begin
  select * into v_row from public.products where id = p_product_id;
  if v_row.id is null then raise exception 'catalog item not found'; end if;
  if v_row.org_id not in (select my_org_ids()) then raise exception 'not a member of that org'; end if;
  if not coalesce(public.has_capability(v_row.org_id, 'manage_catalog'), false) then
    raise exception 'you do not have permission to change the catalog';
  end if;
  for v_key in select jsonb_object_keys(coalesce(p_patch, '{}'::jsonb)) loop
    if v_key not in ('name','category','unit','cost','sell','markup','active') then
      raise exception 'unknown catalog field: %', v_key;
    end if;
  end loop;
  if (p_patch ? 'cost' or p_patch ? 'sell' or p_patch ? 'markup')
     and not coalesce(public.can_view_financials(v_row.org_id), false) then
    raise exception 'not permitted to set catalog cost, sell or markup';
  end if;
  v_cost := case when p_patch ? 'cost' then (p_patch->>'cost')::numeric else v_row.cost end;
  if (p_patch ? 'markup') and not (p_patch ? 'sell') then
    v_sell_in := null;
    v_markup_in := (p_patch->>'markup')::numeric;
  else
    v_sell_in := case when p_patch ? 'sell' then (p_patch->>'sell')::numeric else v_row.sell end;
    v_markup_in := case when (p_patch ? 'sell') and (p_patch ? 'markup')
                        then (p_patch->>'markup')::numeric else null end;
  end if;
  select out_sell, out_markup into v_sell, v_markup
  from public.derive_catalog_price(v_cost, v_sell_in, v_markup_in);
  update public.products set
    name     = case when p_patch ? 'name'
                    then coalesce(nullif(btrim(p_patch->>'name'), ''), name) else name end,
    category = case when p_patch ? 'category' then nullif(btrim(coalesce(p_patch->>'category','')), '') else category end,
    unit     = case when p_patch ? 'unit'     then nullif(btrim(coalesce(p_patch->>'unit','')), '')     else unit end,
    cost     = v_cost,
    sell     = v_sell,
    markup   = v_markup,
    active   = case when p_patch ? 'active'   then (p_patch->>'active')::boolean else active end
  where id = p_product_id;
end;
$function$;
revoke execute on function public.update_product(uuid, jsonb) from public, anon;
drop function if exists public.price_from_method(numeric, text, numeric);
alter table public.products drop constraint if exists products_price_method_valid;
alter table public.products drop constraint if exists products_price_method_value_together;
alter table public.products drop column if exists price_review_reason;
alter table public.products drop column if exists price_value;
alter table public.products drop column if exists price_method;

-- CORRECTIVE 20260913013524 collapsed_state_catalog_readers. list_products and
-- fetch_product RETURN SETOF products and project by name, so once the three
-- columns are gone the 15-column bodies fail at first call (42804) exactly as the
-- 12-column bodies did when the columns arrived. Restore the 12-column bodies
-- AFTER the drop. Bodies captured from pg_get_functiondef() 2026-09-12 before the
-- corrective ran. THEN CALL BOTH AS A MEMBER — as postgres they return before the
-- RETURN QUERY and prove nothing (the forward corrective's in-migration check was
-- that empty instrument).
CREATE OR REPLACE FUNCTION public.list_products(p_org_id uuid, p_include_inactive boolean DEFAULT false)
 RETURNS SETOF products LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_fin boolean;
begin
  if p_org_id is null or p_org_id not in (select my_org_ids()) then
    return;
  end if;
  v_fin := coalesce(public.can_view_financials(p_org_id), false);
  return query
    select p.id, p.org_id, p.name, p.category, p.unit,
           (case when v_fin then p.cost   else null end)::numeric(12,2),
           (case when v_fin then p.sell   else null end)::numeric(12,2),
           (case when v_fin then p.markup else null end)::numeric(8,2),
           p.active, p.created_at, p.updated_at, p.created_by
    from public.products p
    where p.org_id = p_org_id
      and (p_include_inactive or p.active)
    order by p.active desc, lower(p.name);
end;
$function$;
CREATE OR REPLACE FUNCTION public.fetch_product(p_product_id uuid)
 RETURNS SETOF products LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_org uuid; v_fin boolean;
begin
  select org_id into v_org from public.products where id = p_product_id;
  if v_org is null or v_org not in (select my_org_ids()) then
    return;
  end if;
  v_fin := coalesce(public.can_view_financials(v_org), false);
  return query
    select p.id, p.org_id, p.name, p.category, p.unit,
           (case when v_fin then p.cost   else null end)::numeric(12,2),
           (case when v_fin then p.sell   else null end)::numeric(12,2),
           (case when v_fin then p.markup else null end)::numeric(8,2),
           p.active, p.created_at, p.updated_at, p.created_by
    from public.products p
    where p.id = p_product_id;
end;
$function$;
revoke execute on function public.list_products(uuid, boolean) from public, anon;
revoke execute on function public.fetch_product(uuid) from public, anon;
