-- A MEMBER WHO CANNOT SEE A ROW THROUGH THE TABLE MUST NOT RECEIVE IT THROUGH A FUNCTION.
-- Track S · 2026-09-19. Controller ruling of this date.
-- Rollback: supabase/rollbacks/20260919_definer_readers_decline_instead_of_blanking_rollback.sql
--
-- Track U measured both live holes as the real crew login (`field` in the synthetic tenant): fetch_estimate
-- returned SYN-1's WHOLE row — customer email, deal_id, notes_terms, ids — with four money columns set to NULL;
-- fetch_deal returned the pipeline lead — stage, source, first/last name, contact_name — with `value` dropped.
-- The same member SELECTs ZERO rows from either table: both carry the restrictive guard can_view_financials().
-- BLANKING IS A PROXY FOR THE TEST, AND A PROXY CANNOT BE WIDENED. Each reader below now applies the table's
-- OWN test and returns NO ROW when it fails — permissive condition AND restrictive guard, mirrored exactly:
--   estimates  permissive: org ∈ my_org_ids AND has_capability('view_estimates')   restrictive: can_view_financials
--   deals      permissive: org ∈ my_org_ids  OR is_staff()                          restrictive: can_view_financials
--   products   permissive: org ∈ my_org_ids                                         restrictive: can_view_financials
--   work_order_agreements permissive: org ∈ my_org_ids                              restrictive: can_view_master_work_order
-- Because the row is now declined, no column needs masking: the money columns come back as stored for a caller
-- who is allowed the row, and no caller who is not gets the row at all.
--
-- ALSO CLOSED, same family — assert_work_order_level() told a crew member about a master they cannot see:
-- "work order <id> is kind=master — this action requires a trade work order". The id and the kind are exactly
-- what the guard hides. It now answers "not found or not accessible" to any caller who could not see that work
-- order through work_orders (kind='trade' OR can_view_master_work_order), and only explains the level mismatch
-- to a caller who can. Every caller of this helper (check-ins, materials, schedule blocks, agreements,
-- sign-off, take-off) inherits that.
--
-- CALLERS, NAMED (rule 5b): fetch_estimate — coordination work-order page, estimating page, the PDF route,
-- present page, estimating/actions.ts, signed-copy.ts; fetch_deal — the CRM page and estimating/actions.ts;
-- list_products — the estimating page and the catalog page; fetch_product and fetch_work_order_agreement have
-- no app caller today. All of those surfaces already require view_estimates / financials to be useful, so the
-- callers that break are the ones that should never have worked.

create or replace function public.fetch_estimate(p_estimate_id uuid)
 returns setof estimates language sql stable security definer set search_path to 'public'
as $function$
  select e.*
  from public.estimates e
  where e.id = p_estimate_id
    and e.org_id in (select my_org_ids())
    and coalesce(public.has_capability(e.org_id, 'view_estimates'), false)
    and coalesce(public.can_view_financials(e.org_id), false);
$function$;

create or replace function public.fetch_deal(p_deal_id uuid)
 returns setof deals language sql stable security definer set search_path to 'public'
as $function$
  select d.*
  from public.deals d
  where d.id = p_deal_id
    and (d.org_id in (select my_org_ids()) or public.is_staff())
    and coalesce(public.can_view_financials(d.org_id), false);
$function$;

create or replace function public.fetch_product(p_product_id uuid)
 returns setof products language sql stable security definer set search_path to 'public'
as $function$
  select p.*
  from public.products p
  where p.id = p_product_id
    and p.org_id in (select my_org_ids())
    and coalesce(public.can_view_financials(p.org_id), false);
$function$;

create or replace function public.list_products(p_org_id uuid, p_include_inactive boolean default false)
 returns setof products language sql stable security definer set search_path to 'public'
as $function$
  select p.*
  from public.products p
  where p.org_id = p_org_id
    and p_org_id in (select my_org_ids())
    and coalesce(public.can_view_financials(p_org_id), false)
    and (p_include_inactive or p.active)
  order by p.active desc, lower(p.name);
$function$;

create or replace function public.fetch_work_order_agreement(p_work_order_id uuid)
 returns setof work_order_agreements language plpgsql stable security definer set search_path to 'public'
as $function$
begin
  perform public.assert_work_order_level(p_work_order_id, 'master');

  return query
  select a.*
  from public.work_order_agreements a
  where a.work_order_id = p_work_order_id
    and a.status <> 'voided'
    and a.org_id in (select my_org_ids())
    and coalesce(public.can_view_master_work_order(a.org_id), false)
  order by a.created_at desc
  limit 1;
end;
$function$;

create or replace function public.assert_work_order_level(p_work_order_id uuid, p_expected_kind text)
 returns uuid language plpgsql stable security definer set search_path to 'public'
as $function$
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

  -- 2026-09-19: the same test work_orders' restrictive guard applies. A caller who could not see this work
  -- order is told it is not there — never its kind, which is the fact the guard hides.
  if coalesce(v_kind, '') <> 'trade' and not coalesce(public.can_view_master_work_order(v_org_id), false) then
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
