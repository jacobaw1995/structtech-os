-- A1.2 — RPC split: creation
-- docs/STRUCTTECH_OS_DIRECTIVE.md §5.1, decision D1, RPC level table §4.4 (REPLACE row).
--
-- Replaces the single create_work_order_from_estimate with the two functions the
-- job spine actually needs:
--
--   create_job_from_estimate(estimate)            -> job + master work order
--   create_trade_work_order(master, trade, …)     -> one trade under that master
--
-- Done when (§5.1): one signed estimate produces a job, a master, and three trade
-- work orders, at least one of them assigned to an external subcontractor.
--
-- This migration changes NO table and NO row. It is function DDL only; the two
-- existing work_orders rows and their jobs are untouched.
--
-- Decisions taken for this task (recorded in §10):
--
--  1. "External subcontractor must be a valid assignee" is enforced as
--     assignee_type ∈ (crew|department|subcontractor) paired with a non-empty
--     assignee_ref. §5 defines no subcontractors table — the person/crew model is
--     A4.6 — so nothing outside §5 is created here. When A4.6 lands, assignee_ref
--     becomes a resolvable reference; the pairing rule below is what makes that
--     upgrade safe.
--  2. `trade` is required but NOT constrained to a vocabulary. The engine is
--     config-driven and tenants do not share a trade list; a CHECK here would make
--     every new tenant trade a migration (and CLAUDE.md rule 4 makes changing a
--     CHECK value set expensive). §4.5's four trades are the pilot's, not the
--     engine's.
--  3. create_work_order_from_estimate is kept as a DEPRECATED one-line shim over
--     create_job_from_estimate, per CLAUDE.md rule 5b: this migration reaches prod
--     the moment it is applied, the matching UI deploy lags it. The shim keeps the
--     deployed "Create work order" button working across that window. It is
--     dropped in the A1.3 migration, once the re-pointed UI is confirmed live.
--     Signature is byte-identical to the existing one, so CREATE OR REPLACE is a
--     true replacement and creates no overload (CLAUDE.md rule 1).
--
-- Deliberately NOT added here, because §5 does not ask for it (§0: never fill a
-- gap silently in code):
--   · no master-sign-off gate on trade creation — A1.3 owns level enforcement
--   · no predecessor scheduling engine — §4.5 marks predecessor "field only in A1"
--   · no work_order_activity rows — the shipped create path does not log either;
--     changing that is its own concern
--   · grants left at the shipped default for the coordination RPC surface; anon is
--     already refused by the my_org_ids() check on the first statement.

-- ---------------------------------------------------------------------------
-- 1. create_job_from_estimate — the job container + its one master work order
-- ---------------------------------------------------------------------------
-- Returns jsonb, not uuid: this function creates two rows and both ids are
-- needed by callers (the UI redirects to the master, trade creation needs it too,
-- and the job is what A2+ hangs off). Naming them beats returning one and making
-- the caller re-query for the other.
--
-- Find-or-create on both rows, so a double submit is idempotent — the same
-- guarantee A1.1's fix established, now covering the job as well as the master.
-- Both are also protected in the schema: UNIQUE (jobs.estimate_id) and the partial
-- unique index work_orders_one_master_per_job.

drop function if exists public.create_job_from_estimate(uuid);

create function public.create_job_from_estimate(p_estimate_id uuid)
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

comment on function public.create_job_from_estimate(uuid) is
  'A1.2 · Creates (or returns) the job for a signed estimate and its one master work order. Returns {job_id, master_work_order_id}. Idempotent.';

-- ---------------------------------------------------------------------------
-- 2. create_trade_work_order — one trade issued under a master
-- ---------------------------------------------------------------------------
-- org_id, estimate_id and job_id are inherited from the master rather than passed
-- in, so a trade cannot be created into a different org or attached to the wrong
-- job even if a caller is confused.
--
-- The assignee is OPTIONAL (SCOPE §2.8 — never block the user; a trade can exist
-- before it is issued) but never HALF-specified. That pairing rule is what makes
-- "assigned to an external subcontractor" a checkable state rather than a
-- convention.

drop function if exists public.create_trade_work_order(uuid, text, text, text, uuid);

create function public.create_trade_work_order(
  p_master_work_order_id uuid,
  p_trade                text,
  p_assignee_type        text default null,
  p_assignee_ref         text default null,
  p_predecessor_id       uuid default null
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

comment on function public.create_trade_work_order(uuid, text, text, text, uuid) is
  'A1.2 · Creates one trade work order under a master. Inherits org/estimate/job from the master. Assignee is optional but never half-specified; subcontractor is a valid assignee per D1.';

-- ---------------------------------------------------------------------------
-- 3. create_work_order_from_estimate — DEPRECATED shim, dropped in A1.3
-- ---------------------------------------------------------------------------
-- Signature copied verbatim from pg_get_function_identity_arguments():
--   create_work_order_from_estimate(p_estimate_id uuid) returns uuid
-- Identical signature => replacement, not an overload (CLAUDE.md rules 1 and 3;
-- overload count is re-verified after apply).

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

comment on function public.create_work_order_from_estimate(uuid) is
  'DEPRECATED (A1.2) — shim over create_job_from_estimate for the pre-A1.2 deployed UI. Drop in A1.3.';
