drop function if exists public.update_estimate_details(uuid, numeric, text, text);

create or replace function public.update_estimate_details(
  p_estimate_id uuid,
  p_squares numeric default null,
  p_pitch text default null,
  p_site_address text default null,
  p_estimate_date date default null,
  p_valid_until date default null,
  p_tax_rate numeric default null,
  p_notes_terms text default null,
  p_clear_valid_until boolean default false,
  p_clear_tax_rate boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_status text;
begin
  select org_id, status into v_org_id, v_status
  from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  if v_status in ('signed', 'void') then
    raise exception 'estimate % is locked (status: %)', p_estimate_id, v_status;
  end if;

  update public.estimates
  set squares = coalesce(p_squares, squares),
      pitch = coalesce(p_pitch, pitch),
      site_address = coalesce(p_site_address, site_address),
      estimate_date = coalesce(p_estimate_date, estimate_date),
      valid_until = case when p_clear_valid_until then null else coalesce(p_valid_until, valid_until) end,
      tax_rate = case when p_clear_tax_rate then null else coalesce(p_tax_rate, tax_rate) end,
      notes_terms = coalesce(p_notes_terms, notes_terms),
      updated_at = now()
  where id = p_estimate_id;
end;
$$;
