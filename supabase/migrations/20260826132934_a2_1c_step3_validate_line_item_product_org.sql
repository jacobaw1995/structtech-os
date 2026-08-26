-- A2.1c Step 3 — the estimate line's end of the catalog join.
--
-- add_estimate_line_item() has accepted p_product_id since the estimate builder
-- shipped, and it has NEVER checked whose product it is. That was inert while
-- no catalog table existed and every row carried NULL. It stopped being inert
-- yesterday: A2.1 created `products` and added the FK, so the column now
-- resolves to a real row — and, until this statement, it could resolve to
-- ANOTHER TENANT'S real row. The RLS gate on `products` protects reads of the
-- catalog; it does nothing about a uuid handed to a SECURITY DEFINER RPC that
-- writes it into a line item on your own estimate.
--
-- Nothing leaks today (product_id is written, never read back, and the money on
-- the line is the line's own), so this is a provenance-integrity fix rather
-- than a disclosure fix — but a cross-tenant foreign key planted in a live
-- table is the kind of thing that is cheap now and archaeology later.
--
-- Signature UNCHANGED — identical parameter list and defaults, taken from
-- pg_get_function_identity_arguments() — so this REPLACES and does not
-- overload. Overload count is verified against pg_proc after applying.
create or replace function public.add_estimate_line_item(
  p_estimate_id uuid,
  p_description text,
  p_quantity numeric default 1,
  p_unit_price numeric default 0,
  p_product_id uuid default null::uuid,
  p_sort_order integer default 0,
  p_unit text default null::text
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
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

revoke execute on function public.add_estimate_line_item(uuid,text,numeric,numeric,uuid,integer,text) from public, anon;