-- A2.3 clause (3) — the ready-by gate becomes a POLICY LAYER OVER A FACT.
-- StructTech OS · 2026-09-03 · authored on Track S, NOT YET APPLIED.
--
-- WHAT THIS IS NOT: it is not the purchase-order work. A2.3 clause (1) is
-- blocked on a §5 gap (no PO object model) and is being designed separately as
-- a proposal. Clause (2) — "a schedule block scheduled before its ready_by
-- raises a WARNING and still saves" — was ALREADY SHIPPED before this file and
-- was proved by behaviour on 2026-09-03 (three scenarios, real BMR owner
-- identity, rolled back, zero residue): start-before -> flag set + row SAVED,
-- start-on-the-date -> clean, start-after -> clean.
--
-- ------------------------------------------------------------------------
-- PART 1 — THE RENAME. `blocked` IS A NAME THAT WILL BECOME A LIE.
-- ------------------------------------------------------------------------
-- The column asserted REFUSAL and the behaviour was ADVISORY. Today that name
-- is merely wrong; after Part 3 it is wrong in BOTH directions, because the
-- same column would mean "warned" for one tenant and "refused" for another.
--
-- Neither "blocked" nor "warned" is honest across both settings, so the column
-- is named for the FACT instead: the materials for this trade are not ready by
-- that start date. That is true regardless of what any tenant has configured.
-- Warn-versus-block is then a POLICY LAYER READING A FACT, and the column
-- cannot lie under either setting.
--
-- Same shape as A2.0 (a role default evaluated on the READ path is how two
-- functions came to answer one question differently) and A2.1c (a
-- directionality problem was an INPUT problem, not a storage problem).
-- Encode the fact; let policy read it.
--
-- FREE TODAY, EXPENSIVE LATER, AND THAT IS WHY IT IS IN THIS FILE RATHER THAN
-- A LATER ONE: `schedule_blocks` holds 0 rows (measured 2026-09-03). The
-- rename is also why rule 5b does not bite — `fetch_field_jobs` changes its
-- emitted JSON keys, but it can only return rows that do not exist, so no
-- deployed UI can observe the change against live data.
alter table public.schedule_blocks rename column blocked to ready_by_conflict;
alter table public.schedule_blocks rename column blocked_reason to ready_by_conflict_reason;

comment on column public.schedule_blocks.ready_by_conflict is
  'FACT, not policy: this block starts before the latest ready_by among its trade''s material items. Whether that WARNS or BLOCKS is organizations.policy->>''enforce_stage_gating'' (SCOPE §2.8, default off). Renamed from "blocked" by A2.3 because that name asserted a refusal the default behaviour does not perform.';
comment on column public.schedule_blocks.ready_by_conflict_reason is
  'Human-readable form of ready_by_conflict, naming the governing material item and its date. NULL when there is no conflict.';

-- ------------------------------------------------------------------------
-- PART 2 — `enforce_stage_gating` IS PROMOTED TO THE TENANT.
-- ------------------------------------------------------------------------
-- It lived at tenant_modules.config -> lead_control_center and was consumed
-- only by CRM stage navigation. It is under that namespace because that is
-- where it was first needed, not because it belongs to the CRM: it answers
-- "does this tenant enforce process", which is a property of the TENANT.
-- Coordination is the second consumer, and a second consumer is what exposes
-- the namespacing as accidental. Reading a CRM-namespaced key from a
-- coordination RPC works, and makes the third module worse.
--
-- MEASURED BEFORE MOVING, because a promotion with data in flight is a data
-- migration and a different task: ZERO tenants carry this key today — not
-- nested under lead_control_center, not at top level, in any of the 11
-- tenant_modules rows across both orgs. Only BMR's `crm` row has a
-- lead_control_center object at all and the key is not in it. So every tenant
-- has always fallen through to the `false` default, no behaviour can change
-- here, and there is nothing to backfill.
--
-- One row per tenant means the key CANNOT come to disagree with itself, which
-- is the property tenant_modules.config could not offer (one row per module).
alter table public.organizations
  add column if not exists policy jsonb not null default '{}'::jsonb;

comment on column public.organizations.policy is
  'Tenant-level policy switches. Keys: enforce_stage_gating (boolean, default false — SCOPE §2.8 requires enforced process to be per-tenant and OFF by default). Promoted here from tenant_modules.config->lead_control_center by A2.3 when coordination became its second consumer.';

-- The one reader. SECURITY DEFINER because the callers are definer RPCs that
-- must resolve policy for an org the caller may be mid-write on.
create or replace function public.tenant_enforces_stage_gating(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  -- Closed default expressed three times over, deliberately: a missing org, a
  -- policy with no key, and a non-boolean value all mean OFF.
  select coalesce(
    (select (o.policy ->> 'enforce_stage_gating')::boolean
     from public.organizations o where o.id = p_org_id),
    false
  );
$function$;

comment on function public.tenant_enforces_stage_gating(uuid) is
  'Reads organizations.policy->>enforce_stage_gating. Default OFF per SCOPE §2.8. Called only from inside the database (add_schedule_block, update_schedule_block) — the UI reads organizations.policy directly.';

-- ------------------------------------------------------------------------
-- PART 3 — CLAUSE (3): THE POLICY LAYER.
-- ------------------------------------------------------------------------
-- Signatures are UNCHANGED on all three functions below, so CREATE OR REPLACE
-- replaces rather than overloading (CLAUDE.md migration rule 1). Verify
-- overload counts after applying anyway (rule 3).
--
-- SYMMETRIC ON add AND update. Moving an existing block earlier is the same
-- act as creating one early; a gate on only one of them is a gate somebody
-- routes around in a week.
create or replace function public.add_schedule_block(p_work_order_id uuid, p_crew_name text, p_start_date date, p_end_date date)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_block_id uuid;
  v_blocking_name text;
  v_blocking_ready_by date;
  v_conflict boolean;
  v_reason text;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');

  -- The governing date is the LATEST ready_by on the trade: the trade is not
  -- ready until ALL of it has arrived. Items with a NULL ready_by (hand-added,
  -- never ordered) cannot govern and are excluded rather than coalesced.
  select name, ready_by into v_blocking_name, v_blocking_ready_by
  from public.material_items
  where work_order_id = p_work_order_id and ready_by is not null
  order by ready_by desc
  limit 1;

  v_conflict := v_blocking_ready_by is not null and p_start_date < v_blocking_ready_by;
  v_reason := case when v_conflict
    then format('materials not ready until %s (%s)', v_blocking_ready_by, v_blocking_name)
    else null
  end;

  -- POLICY, read after the FACT is computed and never folded into it.
  if v_conflict and public.tenant_enforces_stage_gating(v_org_id) then
    raise exception '%. This workspace enforces stage gating, so the schedule block was not saved. Move the start date to % or later, or turn off enforce_stage_gating.',
      v_reason, v_blocking_ready_by;
  end if;

  insert into public.schedule_blocks
    (org_id, work_order_id, crew_name, start_date, end_date, ready_by_conflict, ready_by_conflict_reason)
  values
    (v_org_id, p_work_order_id, p_crew_name, p_start_date, p_end_date, v_conflict, v_reason)
  returning id into v_block_id;

  return v_block_id;
end;
$function$;

create or replace function public.update_schedule_block(p_schedule_block_id uuid, p_crew_name text default null::text, p_start_date date default null::date, p_end_date date default null::date)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
  v_start_date date;
  v_end_date date;
  v_blocking_name text;
  v_blocking_ready_by date;
  v_conflict boolean;
  v_reason text;
begin
  select org_id, work_order_id, start_date, end_date
  into v_org_id, v_work_order_id, v_start_date, v_end_date
  from public.schedule_blocks where id = p_schedule_block_id;

  if v_org_id is null then
    raise exception 'schedule block not found or not accessible: %', p_schedule_block_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'schedule block not found or not accessible: %', p_schedule_block_id;
  end if;

  v_start_date := coalesce(p_start_date, v_start_date);
  v_end_date := coalesce(p_end_date, v_end_date);

  select name, ready_by into v_blocking_name, v_blocking_ready_by
  from public.material_items
  where work_order_id = v_work_order_id and ready_by is not null
  order by ready_by desc
  limit 1;

  v_conflict := v_blocking_ready_by is not null and v_start_date < v_blocking_ready_by;
  v_reason := case when v_conflict
    then format('materials not ready until %s (%s)', v_blocking_ready_by, v_blocking_name)
    else null
  end;

  if v_conflict and public.tenant_enforces_stage_gating(v_org_id) then
    raise exception '%. This workspace enforces stage gating, so the change was not saved. Move the start date to % or later, or turn off enforce_stage_gating.',
      v_reason, v_blocking_ready_by;
  end if;

  update public.schedule_blocks
  set crew_name = coalesce(p_crew_name, crew_name),
      start_date = v_start_date,
      end_date = v_end_date,
      ready_by_conflict = v_conflict,
      ready_by_conflict_reason = v_reason,
      updated_at = now()
  where id = p_schedule_block_id;
end;
$function$;

-- Emits the renamed keys. The field UI reads these names.
create or replace function public.fetch_field_jobs(p_org_id uuid, p_today date default current_date)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'schedule_block_id', j.id,
        'work_order_id', j.work_order_id,
        'crew_name', j.crew_name,
        'start_date', j.start_date,
        'end_date', j.end_date,
        'ready_by_conflict', j.ready_by_conflict,
        'ready_by_conflict_reason', j.ready_by_conflict_reason,
        'job_title', coalesce(nullif(j.company, ''), j.contact_name),
        'site_address', j.site_address,
        'squares', j.squares,
        'pitch', j.pitch
      ) order by j.start_date, j.created_at
    ), '[]'::jsonb)
  from (
    select sb.id, sb.work_order_id, sb.crew_name, sb.start_date, sb.end_date,
           sb.ready_by_conflict, sb.ready_by_conflict_reason, sb.created_at,
           e.company, e.contact_name, e.site_address, e.squares, e.pitch
    from public.schedule_blocks sb
    join public.work_orders w on w.id = sb.work_order_id
    join public.estimates e on e.id = w.estimate_id
    where sb.org_id = p_org_id
      and p_org_id in (select my_org_ids())
      and w.kind = 'trade'
      and w.voided_at is null
      and sb.end_date >= p_today
    order by sb.start_date, sb.created_at
    limit 20
  ) j;
$function$;

-- ------------------------------------------------------------------------
-- PART 4 — GRANTS. CLAUDE.md migration rule 7, applied PER FUNCTION.
-- ------------------------------------------------------------------------
-- The PUBLIC grant is what makes a new function anon-executable; a revoke
-- naming only `anon` is a no-op. Read proacl after applying and confirm the
-- leading `=X/postgres` entry is gone from all four (rule 3 — never trust the
-- success response).
revoke execute on function public.add_schedule_block(uuid, text, date, date) from public, anon;
revoke execute on function public.update_schedule_block(uuid, text, date, date) from public, anon;
revoke execute on function public.fetch_field_jobs(uuid, date) from public, anon;

-- Rule 7's carve-out test answered per function: does anything OUTSIDE the
-- database call this? For tenant_enforces_stage_gating the answer is NO — the
-- two schedule RPCs are its only callers, and the UI reads organizations.policy
-- directly rather than through it. So `authenticated` is revoked here, as it
-- was for default_permissions_for_role and derive_catalog_price, and is KEPT on
-- the three above, whose call path IS a server action running as authenticated.
revoke execute on function public.tenant_enforces_stage_gating(uuid) from public, anon, authenticated;
