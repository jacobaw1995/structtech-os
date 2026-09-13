-- SECOND CORRECTIVE, 2026-09-12, to 20260913012939 collapsed_state. A REGRESSION
-- OURS, PROVED WITH A CONTROL BEFORE IT WAS FIXED.
--
-- The catalog edit form (src/components/catalog/PriceFields.tsx via
-- src/lib/catalog/actions.ts updateProduct) ALWAYS sends cost, sell and markup,
-- and sends a blank field as JSON null. collapsed_state read "the patch HAS a
-- sell key" as "the user set a fixed price" — so a patch carrying sell:null
-- resolved to method 'fixed' with value NULL and hit
-- products_price_method_value_together.
--   · renaming an UNPRICED item from the edit form   -> refused (raw CHECK text)
--   · clearing the price of an item from the edit form -> refused (raw CHECK text)
-- CONTROL: the pre-migration body, recreated in a rolled-back transaction and
-- called with the identical patches as the identical BMR owner, accepted both.
--
-- The rule is now "a sell VALUE is a fixed price; a markup VALUE is a
-- percentage; price keys present with no values CLEAR the price" — which is what
-- the old body did with the same patches. Signature unchanged.

create or replace function public.update_product(p_product_id uuid, p_patch jsonb)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_row public.products; v_key text;
  v_cost numeric; v_method text; v_value numeric; v_sell numeric; v_markup numeric;
  v_sell_in numeric; v_markup_in numeric;
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

  v_cost      := case when p_patch ? 'cost' then (p_patch->>'cost')::numeric else v_row.cost end;
  v_sell_in   := (p_patch->>'sell')::numeric;    -- NULL when absent OR sent blank
  v_markup_in := (p_patch->>'markup')::numeric;

  -- WHICH RULE governs after this edit? Decided by VALUES, not by key presence.
  if p_patch ? 'price_method' then
    v_method := p_patch->>'price_method';
    v_value  := case when p_patch ? 'price_value' then (p_patch->>'price_value')::numeric else v_row.price_value end;
  elsif v_sell_in is not null then
    -- sell and markup both supplied must agree (derive_catalog_price refuses if not);
    -- sell wins because sell is the money, so the item is FIXED.
    perform public.derive_catalog_price(v_cost, v_sell_in, v_markup_in);
    v_method := 'fixed'; v_value := v_sell_in;
  elsif v_markup_in is not null then
    v_method := 'percent'; v_value := v_markup_in;
  elsif p_patch ? 'sell' or p_patch ? 'markup' then
    -- price keys sent with no values: the user CLEARED the price.
    v_method := null; v_value := null;
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

revoke execute on function public.update_product(uuid, jsonb) from public, anon;