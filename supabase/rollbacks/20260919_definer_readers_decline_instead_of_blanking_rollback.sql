-- ROLLBACK for 20260919 definer_readers_decline_instead_of_blanking. Restores blanking (and the kind-revealing
-- refusal) exactly as they were. Signatures and grants are unchanged by the migration.
CREATE OR REPLACE FUNCTION public.fetch_estimate(p_estimate_id uuid)
 RETURNS SETOF estimates LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  r public.estimates%rowtype;
  v_money boolean;
begin
  for r in
    select e.*
    from public.estimates e
    where e.id = p_estimate_id
      and e.org_id in (select my_org_ids())
  loop
    v_money := public.can_view_financials(r.org_id);
    if not v_money then
      r.subtotal := null;
      r.presented_total := null;
      r.tax_rate := null;
      r.tax_amount := null;
    end if;
    return next r;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION public.fetch_deal(p_deal_id uuid)
 RETURNS SETOF deals LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  select (
    jsonb_populate_record(
      null::public.deals,
      case
        when public.has_capability(d.org_id, 'view_financials') then to_jsonb(d)
        else to_jsonb(d) - 'value'
      end
    )
  ).*
  from public.deals d
  where d.id = p_deal_id
    and d.org_id in (select my_org_ids());
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
           p.active, p.created_at, p.updated_at, p.created_by,
           (case when v_fin then p.price_method        else null end),
           (case when v_fin then p.price_value         else null end),
           (case when v_fin then p.price_review_reason else null end)
    from public.products p
    where p.id = p_product_id;
end;
$function$;

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

CREATE OR REPLACE FUNCTION public.fetch_work_order_agreement(p_work_order_id uuid)
 RETURNS SETOF work_order_agreements LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
begin
  perform public.assert_work_order_level(p_work_order_id, 'master');

  return query
  select a.*
  from public.work_order_agreements a
  where a.work_order_id = p_work_order_id
    and a.status <> 'voided'
    and a.org_id in (select my_org_ids())
  order by a.created_at desc
  limit 1;
end;
$function$;

CREATE OR REPLACE FUNCTION public.assert_work_order_level(p_work_order_id uuid, p_expected_kind text)
 RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_kind   text;
begin
  select w.org_id, w.kind into v_org_id, v_kind
  from public.work_orders w
  where w.id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  if coalesce(v_kind, '') <> p_expected_kind then
    raise exception 'work order % is kind=% — this action requires a % work order (%)',
      p_work_order_id,
      coalesce(v_kind, '(null)'),
      p_expected_kind,
      case p_expected_kind
        when 'trade'  then 'materials, schedule blocks, check-ins and production packets attach to trades, not to the master'
        when 'master' then 'sign-off and agreements are recorded once on the master, not per trade'
        else 'unexpected level'
      end;
  end if;

  return v_org_id;
end;
$function$;
