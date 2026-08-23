-- A1.1 defect fixes — close the stage properly.
-- Directive §5.1 (Stage A1). Applied via MCP apply_migration.
-- Never `supabase db push` / `db reset` on this project (§4.7).
--
-- Two defects introduced or left open by 20260816172215:
--
--   1. REGRESSION. create_work_order_from_estimate inserts (org_id, estimate_id)
--      only, which now violates work_orders.job_id NOT NULL. Work-order creation
--      through the deployed UI has been failing since that migration.
--      CLAUDE.md migration rule 5b.
--
--   2. MISSING CONSTRAINT. D1 states one job per signed estimate, but A1.1 added
--      no uniqueness, so a double-click could create two jobs on one estimate.
--
-- Scope discipline: the function keeps its NAME, SIGNATURE and CALL SITES.
-- Splitting it into create_job_from_estimate + create_trade_work_order is A1.2.

-- 1 · One job per estimate (D1).
alter table public.jobs
  drop constraint if exists jobs_estimate_id_key;
alter table public.jobs
  add constraint jobs_estimate_id_key unique (estimate_id);

-- 2 · Patch the RPC.
--     Signature is UNCHANGED — (p_estimate_id uuid) returns uuid — so this is a
--     true replacement, not an overload (CLAUDE.md migration rule 1). Verified
--     against pg_get_function_identity_arguments before writing, and the overload
--     count is re-checked after applying (rule 3).
--
--     The access and status guards are carried over verbatim, deliberately
--     unchanged: hardening them is not this task's scope.
--
--     Service address is taken from the estimate's deal, which is where the
--     structured fields actually live (estimates.site_address is a single
--     unparsed text column). This matches how A1.1 backfilled the two existing
--     jobs, so backfilled and newly-created jobs stay consistent.
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

  -- Idempotent, as before. Scoped to the MASTER: after A1.1 an estimate may
  -- carry trade work orders too, and those must not satisfy this check.
  select id into v_work_order_id
  from public.work_orders
  where estimate_id = p_estimate_id
    and kind = 'master';

  if v_work_order_id is not null then
    return v_work_order_id;
  end if;

  -- Find-or-create the job. jobs_estimate_id_key makes this single-valued.
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
