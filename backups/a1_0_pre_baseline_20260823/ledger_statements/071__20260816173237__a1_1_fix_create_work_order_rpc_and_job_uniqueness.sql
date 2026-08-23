-- A1.1 defect fixes: repair create_work_order_from_estimate + one job per estimate (D1)

alter table public.jobs
  drop constraint if exists jobs_estimate_id_key;
alter table public.jobs
  add constraint jobs_estimate_id_key unique (estimate_id);

create or replace function public.create_work_order_from_estimate(p_estimate_id uuid)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id        uuid;
  v_deal_id       uuid;
  v_status        text;
  v_job_id        uuid;
  v_work_order_id uuid;
begin
  select e.org_id, e.deal_id, e.status
    into v_org_id, v_deal_id, v_status
  from public.estimates e
  where e.id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  if v_status <> 'signed' then
    raise exception 'estimate % must be signed before a work order can be created (current status: %)', p_estimate_id, v_status;
  end if;

  select id into v_work_order_id
  from public.work_orders
  where estimate_id = p_estimate_id
    and kind = 'master';

  if v_work_order_id is not null then
    return v_work_order_id;
  end if;

  select id into v_job_id
  from public.jobs
  where estimate_id = p_estimate_id;

  if v_job_id is null then
    insert into public.jobs (
      org_id, deal_id, estimate_id,
      service_address_street, service_address_city,
      service_address_state, service_address_zip
    )
    select v_org_id, v_deal_id, p_estimate_id,
           d.service_address_street, d.service_address_city,
           d.service_address_state, d.service_address_zip
    from public.deals d
    where d.id = v_deal_id
    returning id into v_job_id;
  end if;

  insert into public.work_orders (org_id, estimate_id, job_id, kind)
  values (v_org_id, p_estimate_id, v_job_id, 'master')
  returning id into v_work_order_id;

  return v_work_order_id;
end;
$function$;

comment on constraint jobs_estimate_id_key on public.jobs is
  'D1: one job per signed estimate. Without this a double-click creates two jobs on one estimate.';
