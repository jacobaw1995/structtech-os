-- StructTech OS — CRM Depth fix pass #2: canonical address for estimates
--
-- create_estimate_from_deal currently reads ONLY deals.project_address
-- into estimates.site_address. AddDealForm/EditLeadDetailsForm are being
-- reworked to collect the structured service_address_* columns (already
-- present since Stage 2) instead of free-text project_address, so this
-- RPC needs to prefer the structured address once it's populated.
--
-- Fallback, not backfill: project_address stays untouched on existing
-- rows (2 of BMR's 4 live deals only have project_address, not yet
-- service_address_*) — free text can't be reliably split into
-- street/city/state/zip, so no backfill migration. This RPC just prefers
-- the structured address when present and falls back to project_address
-- when it isn't, so old deals keep working and new deals get the
-- canonical source going forward. Same signature (p_deal_id uuid) — no
-- DROP needed.

create or replace function public.create_estimate_from_deal(p_deal_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_org_id uuid;
  v_contact_name text;
  v_company text;
  v_phone text;
  v_email text;
  v_project_address text;
  v_service_address_street text;
  v_service_address_city text;
  v_service_address_state text;
  v_service_address_zip text;
  v_site_address text;
  v_estimate_id uuid;
begin
  select org_id, contact_name, company, phone, email, project_address,
         service_address_street, service_address_city, service_address_state, service_address_zip
  into v_org_id, v_contact_name, v_company, v_phone, v_email, v_project_address,
       v_service_address_street, v_service_address_city, v_service_address_state, v_service_address_zip
  from public.deals
  where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  v_site_address := coalesce(
    nullif(trim(concat_ws(', ',
      nullif(v_service_address_street, ''),
      nullif(v_service_address_city, ''),
      nullif(v_service_address_state, ''),
      nullif(v_service_address_zip, '')
    )), ''),
    v_project_address
  );

  insert into public.estimates (org_id, deal_id, contact_name, company, phone, email, site_address)
  values (v_org_id, p_deal_id, v_contact_name, v_company, v_phone, v_email, v_site_address)
  returning id into v_estimate_id;

  return v_estimate_id;
end;
$function$;
