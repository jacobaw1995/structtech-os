-- A1.2 — RPC split: creation (§5.1)
--
-- APPLIED TO PRODUCTION 2026-08-17 via MCP `apply_migration`, recorded in
-- supabase_migrations.schema_migrations as version 20260817151709,
-- name `a1_2_creation_rpc_split_job_and_trade`. This file is the repo record of
-- what is already deployed — it is not re-applied. Reproduced from the live
-- database with pg_get_functiondef(); overload count verified at exactly 1 for
-- each of the three functions (CLAUDE.md rules 1–3).
--
-- SCOPE: FUNCTION DDL ONLY. No table was created, altered or dropped. No row was
-- inserted, updated or deleted. A1.1 already delivered every schema object these
-- functions touch (`jobs`, `work_orders.job_id/kind/trade/assignee_type/
-- assignee_ref/predecessor_id`, the one-master-per-job index, `UNIQUE
-- (jobs.estimate_id)`). A1.2 only changes the callable surface over them.
--
-- WHY create_job_from_estimate RETURNS jsonb, NOT uuid:
--   It creates two rows — a job and its master work order — and both ids are
--   load-bearing. The caller redirects to the master work order, while A2/A5
--   hang materials, purchasing and money off the job. Returning one id would
--   force every caller into a second round trip to recover the other, and there
--   is no honest single "the id this created". `{job_id, master_work_order_id}`
--   states both. This is the one signature change in the split, and it is why
--   the shim below exists rather than a plain rename.
--
-- WHY create_trade_work_order INHERITS org_id/estimate_id/job_id:
--   The trade takes all three from the master row it is created under; none is a
--   parameter. A caller therefore cannot land a trade in the wrong org or on the
--   wrong job, because it has no way to name either one. Authorization is checked
--   once, against the master, via `my_org_ids()`. The predecessor is confirmed to
--   be a trade on the same job for the same reason. Per D1 an external
--   subcontractor is a first-class assignee, not an exception.
--
-- WHY create_work_order_from_estimate SURVIVES AS A DEPRECATED SHIM:
--   CLAUDE.md rule 5b — migrations hit production immediately, UI deploys lag.
--   The deployed UI still calls `create_work_order_from_estimate` and reads a
--   bare uuid. Dropping it here would have broken work-order creation in
--   production for exactly as long as it took the matching UI to ship, which is
--   the failure A1.1 already recorded once. The shim keeps its original name and
--   `(p_estimate_id uuid) returns uuid` signature and delegates to
--   `create_job_from_estimate`, unwrapping `master_work_order_id`. It is dropped
--   as the first statement of A1.3, once the re-pointed call sites are deployed.
--
-- NO GRANT STATEMENTS: all three carry the project-wide default function ACL
-- (`anon`, `authenticated`, `service_role` = EXECUTE), applied automatically on
-- create. That default is itself the §6.9 finding — `anon` holds EXECUTE on all
-- 110 security-definer RPCs and is refused on the first statement of each by
-- `my_org_ids()`. It is revoked as one sweep in A1.5, not here, so this file
-- stays a faithful record of what was deployed.

-- New: job + master. Idempotent per estimate (find-or-create), which is what
-- makes a double-submitted sign-off safe.
create or replace function public.create_job_from_estimate(p_estimate_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id    uuid;
  v_deal_id   uuid;
  v_status    text;
  v_job_id    uuid;
  v_master_id uuid;
begin
  select e.org_id, e.deal_id, e.status
    into v_org_id, v_deal_id, v_status
  from public.estimates e
  where e.id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  -- coalesce, not a bare <> : a null status makes the comparison null, and
  -- PL/pgSQL reads a null IF as false — which would let an unsigned estimate
  -- through (CLAUDE.md rule 5).
  if coalesce(v_status, '') <> 'signed' then
    raise exception 'estimate % must be signed before a job can be created (current status: %)',
      p_estimate_id, coalesce(v_status, '(null)');
  end if;

  if v_deal_id is null then
    raise exception 'estimate % has no deal — a job needs a service address', p_estimate_id;
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

    -- insert … select inserts zero rows if the deal is gone, which would leave
    -- v_job_id null and surface as a confusing NOT NULL failure two statements
    -- later. Say what actually happened.
    if v_job_id is null then
      raise exception 'deal % for estimate % not found', v_deal_id, p_estimate_id;
    end if;
  end if;

  select id into v_master_id
  from public.work_orders
  where job_id = v_job_id
    and kind = 'master';

  if v_master_id is null then
    insert into public.work_orders (org_id, estimate_id, job_id, kind)
    values (v_org_id, p_estimate_id, v_job_id, 'master')
    returning id into v_master_id;
  end if;

  return jsonb_build_object(
    'job_id', v_job_id,
    'master_work_order_id', v_master_id
  );
end;
$function$;

-- New: a trade under a master. org_id / estimate_id / job_id are read off the
-- master, never passed in.
create or replace function public.create_trade_work_order(
  p_master_work_order_id uuid,
  p_trade text,
  p_assignee_type text default null::text,
  p_assignee_ref text default null::text,
  p_predecessor_id uuid default null::uuid
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id        uuid;
  v_estimate_id   uuid;
  v_job_id        uuid;
  v_kind          text;
  v_voided_at     timestamptz;
  v_trade         text;
  v_assignee_type text;
  v_assignee_ref  text;
  v_existing_id   uuid;
  v_trade_id      uuid;
begin
  select w.org_id, w.estimate_id, w.job_id, w.kind, w.voided_at
    into v_org_id, v_estimate_id, v_job_id, v_kind, v_voided_at
  from public.work_orders w
  where w.id = p_master_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_master_work_order_id;
  end if;

  if coalesce(v_kind, '') <> 'master' then
    raise exception 'work order % is kind=% — a trade work order must be created under a master',
      p_master_work_order_id, coalesce(v_kind, '(null)');
  end if;

  if v_voided_at is not null then
    raise exception 'master work order % is voided — cannot add a trade work order to it',
      p_master_work_order_id;
  end if;

  v_trade := nullif(btrim(coalesce(p_trade, '')), '');
  if v_trade is null then
    raise exception 'trade is required on a trade work order';
  end if;

  v_assignee_type := nullif(btrim(coalesce(p_assignee_type, '')), '');
  v_assignee_ref  := nullif(btrim(coalesce(p_assignee_ref,  '')), '');

  if (v_assignee_type is null) <> (v_assignee_ref is null) then
    raise exception 'assignee_type and assignee_ref must be supplied together (type=%, ref=%)',
      coalesce(v_assignee_type, '(null)'), coalesce(v_assignee_ref, '(null)');
  end if;

  -- Mirrors work_orders_assignee_type_check so the caller gets a readable error
  -- instead of a constraint violation. D1: an external subcontractor is a
  -- first-class assignee, not an exception — the tenant is frequently somebody
  -- else's sub.
  if v_assignee_type is not null
     and v_assignee_type not in ('crew', 'department', 'subcontractor') then
    raise exception 'assignee_type % is not valid — expected crew, department or subcontractor',
      v_assignee_type;
  end if;

  if p_predecessor_id is not null then
    if p_predecessor_id = p_master_work_order_id then
      raise exception 'predecessor cannot be the master work order';
    end if;

    perform 1
    from public.work_orders w
    where w.id = p_predecessor_id
      and w.job_id = v_job_id
      and w.kind = 'trade';

    if not found then
      raise exception 'predecessor % is not a trade work order on job %', p_predecessor_id, v_job_id;
    end if;
  end if;

  -- Double-submit guard, the trade-level equivalent of A1.1's master idempotency.
  -- Two crews legitimately split one trade, so this keys on the assignee too: the
  -- same trade issued to a different assignee is allowed, the identical row is not.
  -- Refuse rather than silently return, because unlike the master a trade carries
  -- caller-supplied detail and a silent no-op would hide a real mistake.
  select w.id into v_existing_id
  from public.work_orders w
  where w.job_id = v_job_id
    and w.kind = 'trade'
    and w.voided_at is null
    and lower(w.trade) = lower(v_trade)
    and coalesce(w.assignee_type, '') = coalesce(v_assignee_type, '')
    and coalesce(w.assignee_ref,  '') = coalesce(v_assignee_ref,  '')
  limit 1;

  if v_existing_id is not null then
    raise exception 'an active % trade work order with the same assignee already exists on this job (%)',
      v_trade, v_existing_id;
  end if;

  insert into public.work_orders (
    org_id, estimate_id, job_id, kind,
    trade, assignee_type, assignee_ref, predecessor_id
  )
  values (
    v_org_id, v_estimate_id, v_job_id, 'trade',
    v_trade, v_assignee_type, v_assignee_ref, p_predecessor_id
  )
  returning id into v_trade_id;

  return v_trade_id;
end;
$function$;

-- DEPRECATED SHIM (rule 5b). Same name, same `(p_estimate_id uuid) returns uuid`
-- signature, same call sites — the body is now a delegation. Signature is
-- unchanged, so this replaces rather than overloads; the explicit drop is
-- belt-and-braces against rule 1, with the identity argument list copied verbatim
-- from pg_get_function_identity_arguments(). DROPPED AS THE FIRST STATEMENT OF A1.3.
drop function if exists public.create_work_order_from_estimate(p_estimate_id uuid);

create or replace function public.create_work_order_from_estimate(p_estimate_id uuid)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  -- DEPRECATED (A1.2). Delegates to create_job_from_estimate so the currently
  -- deployed UI keeps working until its re-point ships. Drop in A1.3.
  return (public.create_job_from_estimate(p_estimate_id) ->> 'master_work_order_id')::uuid;
end;
$function$;
