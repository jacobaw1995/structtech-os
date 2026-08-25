-- A2.1a — follow-up to 20260825125737, caught by CALLING the functions in a
-- probe rather than by reasoning about the migration or trusting that the DDL
-- parsed.
--
-- THE DEFECT: `case when v_fin then p.cost else null end` has type `numeric`
-- with NO typmod, but `returns setof public.products` expects `numeric(12,2)`
-- for cost/sell and `numeric(8,2)` for markup. Postgres resolves a CASE result
-- type once for the whole expression, so this raised
--   42804 structure of query does not match function result type
--   DETAIL: Returned type numeric does not match expected type numeric(12,2)
-- for EVERY caller, not only a crew one — the owner's catalog page was broken
-- too. The A2.1 dry run created these functions successfully and never invoked
-- them, so it proved they COMPILED and nothing else.
--
-- This is the same shape the directive has now recorded five times: the
-- instrument was narrower than the assertion resting on it. `tsc` passing is
-- not evidence a query runs, and neither is `create function` succeeding.
--
-- FIX: cast each branch back to the column's own typmod. The gate itself is
-- unchanged — money is still nulled for a caller without can_view_financials().

create or replace function public.list_products(p_org_id uuid, p_include_inactive boolean default false)
returns setof public.products
language plpgsql
stable
security definer
set search_path to 'public'
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
           p.active, p.created_at, p.updated_at, p.created_by
    from public.products p
    where p.org_id = p_org_id
      and (p_include_inactive or p.active)
    order by p.active desc, lower(p.name);
end;
$function$;
revoke execute on function public.list_products(uuid,boolean) from public, anon;

create or replace function public.fetch_product(p_product_id uuid)
returns setof public.products
language plpgsql
stable
security definer
set search_path to 'public'
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
           p.active, p.created_at, p.updated_at, p.created_by
    from public.products p
    where p.id = p_product_id;
end;
$function$;
revoke execute on function public.fetch_product(uuid) from public, anon;