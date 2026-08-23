create or replace function public.update_estimate_build_mode(
  p_estimate_id uuid,
  p_build_mode text
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

  if p_build_mode not in ('manual', 'guided') then
    raise exception 'invalid build_mode: %', p_build_mode;
  end if;

  update public.estimates
  set build_mode = p_build_mode,
      updated_at = now()
  where id = p_estimate_id;
end;
$$;
