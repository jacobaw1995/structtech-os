-- CORRECTIVE, 2026-09-12, minutes after 20260913012939 collapsed_state.
-- RULE 15, EXACTLY AS WRITTEN, AND IT FIRED ON OUR OWN MIGRATION.
--
-- list_products and fetch_product are declared RETURNS SETOF products and project
-- the columns BY NAME (so cost/sell/markup can be masked for members without
-- view_financials). collapsed_state added three columns to products. The apply
-- returned success, every structural check passed, and the first call failed:
--   42804 structure of query does not match function result type
--   Number of returned columns (12) does not match expected column count (15).
-- Nothing binds a function's projection to its table's row type until the
-- function runs. The catalog page and the estimate picker's product list were
-- dead from the moment collapsed_state applied until this one did.
--
-- The fix appends the three columns in table order, MASKED under the same
-- view_financials rule as the money they describe: price_value is a price or a
-- margin, and price_review_reason quotes both. price_method is masked with them
-- so a member who cannot see money cannot infer how an item is priced either.
-- Signatures unchanged, so CREATE OR REPLACE replaces; grants are carried.

create or replace function public.list_products(p_org_id uuid, p_include_inactive boolean default false)
returns setof public.products language plpgsql stable security definer set search_path to 'public'
as $function$
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
           p.active, p.created_at, p.updated_at, p.created_by,
           (case when v_fin then p.price_method        else null end),
           (case when v_fin then p.price_value         else null end),
           (case when v_fin then p.price_review_reason else null end)
    from public.products p
    where p.org_id = p_org_id
      and (p_include_inactive or p.active)
    order by p.active desc, lower(p.name);
end;
$function$;

create or replace function public.fetch_product(p_product_id uuid)
returns setof public.products language plpgsql stable security definer set search_path to 'public'
as $function$
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
           p.active, p.created_at, p.updated_at, p.created_by,
           (case when v_fin then p.price_method        else null end),
           (case when v_fin then p.price_value         else null end),
           (case when v_fin then p.price_review_reason else null end)
    from public.products p
    where p.id = p_product_id;
end;
$function$;

revoke execute on function public.list_products(uuid, boolean) from public, anon;
revoke execute on function public.fetch_product(uuid) from public, anon;

-- Rule 3 AND rule 15 in one: do not trust the success response — CALL them.
-- As postgres, my_org_ids() is empty, so both return zero rows; the RETURN QUERY
-- still has to be planned against the row type, which is the statement that broke.
do $$
declare v_org uuid;
begin
  select id into v_org from public.organizations limit 1;
  perform count(*) from public.list_products(v_org, true);
  perform count(*) from public.fetch_product(gen_random_uuid());
end $$;