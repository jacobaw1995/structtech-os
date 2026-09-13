-- ROLLBACK for 2026-09-13 add_estimate_line_item_price_no_default (ruling c).
-- Body captured from pg_get_functiondef() on the LIVE database 2026-09-13 BEFORE the change.
-- Signature copied from pg_get_function_identity_arguments(), never retyped (rule 2).
-- Column default captured from information_schema.columns: estimate_line_items.unit_price DEFAULT 0.
--
-- RESTORING THIS RE-OPENS: an omitted unit price becomes a $0 line — through the RPC by
-- omission, and through a direct INSERT (RLS "member insert own estimate_line_items") by
-- the column default — indistinguishable afterwards from a line a user priced at zero.

alter table public.estimate_line_items alter column unit_price set default 0;

drop function if exists public.add_estimate_line_item(uuid, text, numeric, numeric, uuid, integer, text);
CREATE OR REPLACE FUNCTION public.add_estimate_line_item(p_estimate_id uuid, p_description text, p_quantity numeric DEFAULT 1, p_unit_price numeric DEFAULT 0, p_product_id uuid DEFAULT NULL::uuid, p_sort_order integer DEFAULT 0, p_unit text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_status text;
  v_line_id uuid;
  v_product_org uuid;
begin
  select org_id, status into v_org_id, v_status
  from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  if v_status in ('signed', 'void') then
    raise exception 'estimate % is locked (status: %) — line items can only change before signing', p_estimate_id, v_status;
  end if;

  -- The catalog item must belong to the SAME org as the estimate. Not merely
  -- "an org I am a member of": an agency_admin belongs to several, and pricing
  -- one tenant's roof from another tenant's catalog is wrong even when the
  -- caller can legitimately see both.
  if p_product_id is not null then
    select org_id into v_product_org from public.products where id = p_product_id;
    if v_product_org is null then
      raise exception 'catalog item not found: %', p_product_id;
    end if;
    if v_product_org <> v_org_id then
      raise exception 'that catalog item belongs to a different tenant and cannot price this estimate';
    end if;
  end if;

  insert into public.estimate_line_items
    (org_id, estimate_id, product_id, description, quantity, unit_price, sort_order, unit)
  values
    (v_org_id, p_estimate_id, p_product_id, p_description, p_quantity, p_unit_price, p_sort_order, p_unit)
  returning id into v_line_id;

  return v_line_id;
end;
$function$;
revoke execute on function public.add_estimate_line_item(uuid, text, numeric, numeric, uuid, integer, text) from public, anon;
