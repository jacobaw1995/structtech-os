-- ROLLBACK for 20260911 trim_at_write_and_po_delete_guard.
-- delete_purchase_order's body captured from pg_get_functiondef() on the LIVE
-- database BEFORE the change (§7.1 Rule 1). The trigger and its function are
-- NEW, so their rollback is a drop.
--
-- RESTORING THIS re-opens both: a purchase order becomes deletable at ANY
-- status (so a sent order's history can be erased instead of cancelled), and
-- copied estimate text is stored untrimmed again.
-- It does NOT un-trim the one row the forward migration fixed; that row's value
-- is now correct and reverting the code is not a reason to re-break the data.

drop trigger if exists material_items_trim_text on public.material_items;
drop function if exists public.material_items_trim_text();

CREATE OR REPLACE FUNCTION public.delete_purchase_order(p_po_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_org_id uuid; v_items uuid[];
begin
  select org_id into v_org_id from public.purchase_orders where id = p_po_id;
  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'purchase order not found or not accessible: %', p_po_id;
  end if;
  if not public.has_capability(v_org_id, 'manage_purchasing') then
    raise exception 'your role cannot delete purchase orders in this workspace';
  end if;
  select array_agg(distinct material_item_id) into v_items
    from public.purchase_order_lines where purchase_order_id = p_po_id;
  delete from public.purchase_orders where id = p_po_id;
  if v_items is not null then
    perform public.recompute_material_item_ready_by(i) from unnest(v_items) i;
  end if;
end;
$function$;

revoke execute on function public.delete_purchase_order(uuid) from public, anon;
