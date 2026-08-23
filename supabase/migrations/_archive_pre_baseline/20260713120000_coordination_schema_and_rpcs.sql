-- StructTech OS — Week 3 Stage 1: coordination schema (contractor-only)
--
-- NOT APPLIED. Author-only migration file — ask before applying, same as
-- every other migration in this repo. Depends on Week 2's estimating schema
-- (20260712140000_estimating_schema_and_rpcs.sql) already being applied —
-- create_work_order_from_estimate() reads a signed estimate's org_id the
-- same way create_estimate_from_deal() reads a deal's.
--
-- Three new tables, no existing ones touched — same clean-slate situation
-- as estimating: org_id is NOT NULL from the start, RLS is the plain
-- my_org_ids() pattern with no is_staff() layering.
--
-- Two scope calls made here, both flagged in BUILD_PLAN_3WEEK.md as
-- "include only if cheap" — cheap versions chosen, not skipped:
--
--   1. Homeowner sign-off (colors/finishes) is captured as two nullable
--      columns on work_orders (sign_off_at, sign_off_notes) set by a single
--      RPC, NOT a hard gate blocking work-order/material/schedule creation.
--      The wireframe (1d/2d) and BUILD_PLAN both sequence it before the
--      work order; a true gate would mean create_work_order_from_estimate
--      can't run until sign-off exists, which either (a) adds a second
--      pre-work-order entity to hold the sign-off, or (b) blocks the "no
--      re-entry" one-click work-order creation on a step that has no home
--      yet. The soft version — create the work order immediately (nothing
--      to re-key), track sign-off as a fact on it, let the UI show it as an
--      outstanding item in the progress chips — gets the data model in
--      place without inventing a blocking flow under deadline. Flagging for
--      review, not deciding unilaterally that this is final.
--
--   2. Material ready-by gating is enforced at write time, not live. Adding
--      or updating a schedule_block computes whether its start_date is
--      before the latest ready_by across that work order's material_items
--      and stores the verdict (blocked, blocked_reason) on the row. It does
--      NOT recompute existing schedule_blocks when materials change later,
--      and it does not auto-clamp the date — it flags. That matches the
--      wireframe's own admission ("build note: multi-job per crew,
--      drag-to-reschedule, and conflict detection not modeled here") and
--      avoids a trigger that would have to fan out from material_items to
--      every schedule_block on the work order.
--
-- No separate "status" column on work_orders. Week 2's estimates.status is
-- a real state machine because it locks edits (present_estimate freezes the
-- total, sign_estimate is terminal). Nothing here needs that — a work order
-- is a running checklist, not a document with a signature. The UI derives
-- its progress-chip stage from data presence (sign_off_at set? any
-- material_items? any schedule_blocks?) instead of a parallel column that
-- could drift from the rows it's summarizing.
--
-- No crew/resource table. crew_name is free text on schedule_blocks, same
-- as the wireframe's "Crew A" / "Crew B" labels — a real crew entity
-- (with member assignment, capacity) is Field-module-adjacent scope, not
-- needed to produce a materials-gated schedule this week.

-- ============================================================================
-- 1. work_orders
-- ============================================================================
create table public.work_orders (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  estimate_id uuid not null references public.estimates(id),

  -- Homeowner sign-off (colors/finishes) — soft capture, not a gate. See
  -- header note 1.
  sign_off_at timestamptz,
  sign_off_notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- One work order per estimate — create_work_order_from_estimate() below
  -- is idempotent against this, returning the existing row instead of
  -- erroring on a second click.
  unique (estimate_id)
);

create index work_orders_org_id_idx on public.work_orders(org_id);

comment on table public.work_orders is
  'Generated from a signed estimate — no re-entry (SCOPE.md §6). One per estimate. Progress is derived by the UI from sign_off_at / material_items / schedule_blocks presence, not a stored status.';
comment on column public.work_orders.sign_off_at is
  'Homeowner sign-off on colors/finishes — soft capture, does not block material/schedule creation. See migration header note 1.';

alter table public.work_orders enable row level security;

create policy "member read own work_orders"
  on public.work_orders for select
  using (org_id in (select my_org_ids()));

create policy "member insert own work_orders"
  on public.work_orders for insert
  with check (org_id in (select my_org_ids()));

create policy "member update own work_orders"
  on public.work_orders for update
  using (org_id in (select my_org_ids()))
  with check (org_id in (select my_org_ids()));

-- ============================================================================
-- 2. material_items
-- ============================================================================
create table public.material_items (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  work_order_id uuid not null references public.work_orders(id) on delete cascade,

  name text not null,
  quantity numeric not null default 1,
  ready_by date,
  sort_order int not null default 0,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index material_items_work_order_id_idx on public.material_items(work_order_id);
create index material_items_org_id_idx on public.material_items(org_id);

alter table public.material_items enable row level security;

create policy "member read own material_items"
  on public.material_items for select
  using (org_id in (select my_org_ids()));

create policy "member insert own material_items"
  on public.material_items for insert
  with check (org_id in (select my_org_ids()));

create policy "member update own material_items"
  on public.material_items for update
  using (org_id in (select my_org_ids()))
  with check (org_id in (select my_org_ids()));

create policy "member delete own material_items"
  on public.material_items for delete
  using (org_id in (select my_org_ids()));

-- ============================================================================
-- 3. schedule_blocks
-- ============================================================================
create table public.schedule_blocks (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  work_order_id uuid not null references public.work_orders(id) on delete cascade,

  crew_name text not null,
  start_date date not null,
  end_date date not null,

  -- Written by the add/update RPCs at save time by comparing start_date to
  -- the work order's material_items.ready_by — see header note 2. Never
  -- written directly by app code.
  blocked boolean not null default false,
  blocked_reason text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  check (end_date >= start_date)
);

create index schedule_blocks_work_order_id_idx on public.schedule_blocks(work_order_id);
create index schedule_blocks_org_id_idx on public.schedule_blocks(org_id);

comment on column public.schedule_blocks.blocked is
  'Computed at write time only (start_date vs. latest material ready_by) — not recomputed when material_items change later. See migration header note 2.';

alter table public.schedule_blocks enable row level security;

create policy "member read own schedule_blocks"
  on public.schedule_blocks for select
  using (org_id in (select my_org_ids()));

create policy "member insert own schedule_blocks"
  on public.schedule_blocks for insert
  with check (org_id in (select my_org_ids()));

create policy "member update own schedule_blocks"
  on public.schedule_blocks for update
  using (org_id in (select my_org_ids()))
  with check (org_id in (select my_org_ids()));

create policy "member delete own schedule_blocks"
  on public.schedule_blocks for delete
  using (org_id in (select my_org_ids()));

-- ============================================================================
-- 4. RPCs — all security-definer, org-scoped from the caller's own
-- membership, per the pattern established in Week 2.
-- ============================================================================

-- 4a. create_work_order_from_estimate — idempotent: a second call for the
-- same estimate returns the existing work order instead of erroring, so a
-- double-click on the "Create work order" CTA is harmless.
create or replace function public.create_work_order_from_estimate(p_estimate_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_status text;
  v_work_order_id uuid;
begin
  select org_id, status into v_org_id, v_status
  from public.estimates
  where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  if v_status <> 'signed' then
    raise exception 'estimate % must be signed before a work order can be created (current status: %)', p_estimate_id, v_status;
  end if;

  select id into v_work_order_id
  from public.work_orders
  where estimate_id = p_estimate_id;

  if v_work_order_id is not null then
    return v_work_order_id;
  end if;

  insert into public.work_orders (org_id, estimate_id)
  values (v_org_id, p_estimate_id)
  returning id into v_work_order_id;

  return v_work_order_id;
end;
$$;

-- 4b. fetch_work_order — single-record fetch RPC (CLAUDE.md rule 4).
create or replace function public.fetch_work_order(p_work_order_id uuid)
returns setof public.work_orders
language sql
security definer
stable
set search_path = public
as $$
  select w.*
  from public.work_orders w
  where w.id = p_work_order_id
    and w.org_id in (select my_org_ids());
$$;

-- 4c. record_work_order_sign_off — soft capture, see header note 1.
create or replace function public.record_work_order_sign_off(
  p_work_order_id uuid,
  p_notes text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id
  from public.work_orders where id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  update public.work_orders
  set sign_off_at = now(),
      sign_off_notes = coalesce(p_notes, sign_off_notes),
      updated_at = now()
  where id = p_work_order_id;
end;
$$;

-- 4d. Material item CRUD.
create or replace function public.add_material_item(
  p_work_order_id uuid,
  p_name text,
  p_quantity numeric default 1,
  p_ready_by date default null,
  p_sort_order int default 0
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_item_id uuid;
begin
  select org_id into v_org_id
  from public.work_orders where id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  insert into public.material_items (org_id, work_order_id, name, quantity, ready_by, sort_order)
  values (v_org_id, p_work_order_id, p_name, p_quantity, p_ready_by, p_sort_order)
  returning id into v_item_id;

  return v_item_id;
end;
$$;

create or replace function public.update_material_item(
  p_material_item_id uuid,
  p_name text default null,
  p_quantity numeric default null,
  p_ready_by date default null,
  p_sort_order int default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id
  from public.material_items where id = p_material_item_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'material item not found or not accessible: %', p_material_item_id;
  end if;

  update public.material_items
  set name = coalesce(p_name, name),
      quantity = coalesce(p_quantity, quantity),
      ready_by = coalesce(p_ready_by, ready_by),
      sort_order = coalesce(p_sort_order, sort_order),
      updated_at = now()
  where id = p_material_item_id;
end;
$$;

create or replace function public.delete_material_item(p_material_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id
  from public.material_items where id = p_material_item_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'material item not found or not accessible: %', p_material_item_id;
  end if;

  delete from public.material_items where id = p_material_item_id;
end;
$$;

-- 4e. Schedule block CRUD — both writers compute (blocked, blocked_reason)
-- against the work order's material_items at save time (header note 2).
create or replace function public.add_schedule_block(
  p_work_order_id uuid,
  p_crew_name text,
  p_start_date date,
  p_end_date date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_block_id uuid;
  v_blocking_name text;
  v_blocking_ready_by date;
  v_blocked boolean;
  v_reason text;
begin
  select org_id into v_org_id
  from public.work_orders where id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  select name, ready_by into v_blocking_name, v_blocking_ready_by
  from public.material_items
  where work_order_id = p_work_order_id and ready_by is not null
  order by ready_by desc
  limit 1;

  v_blocked := v_blocking_ready_by is not null and p_start_date < v_blocking_ready_by;
  v_reason := case when v_blocked
    then format('blocked on %s (ready %s)', v_blocking_name, v_blocking_ready_by)
    else null
  end;

  insert into public.schedule_blocks
    (org_id, work_order_id, crew_name, start_date, end_date, blocked, blocked_reason)
  values
    (v_org_id, p_work_order_id, p_crew_name, p_start_date, p_end_date, v_blocked, v_reason)
  returning id into v_block_id;

  return v_block_id;
end;
$$;

create or replace function public.update_schedule_block(
  p_schedule_block_id uuid,
  p_crew_name text default null,
  p_start_date date default null,
  p_end_date date default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_work_order_id uuid;
  v_start_date date;
  v_end_date date;
  v_blocking_name text;
  v_blocking_ready_by date;
  v_blocked boolean;
  v_reason text;
begin
  select org_id, work_order_id, start_date, end_date
  into v_org_id, v_work_order_id, v_start_date, v_end_date
  from public.schedule_blocks where id = p_schedule_block_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'schedule block not found or not accessible: %', p_schedule_block_id;
  end if;

  v_start_date := coalesce(p_start_date, v_start_date);
  v_end_date := coalesce(p_end_date, v_end_date);

  select name, ready_by into v_blocking_name, v_blocking_ready_by
  from public.material_items
  where work_order_id = v_work_order_id and ready_by is not null
  order by ready_by desc
  limit 1;

  v_blocked := v_blocking_ready_by is not null and v_start_date < v_blocking_ready_by;
  v_reason := case when v_blocked
    then format('blocked on %s (ready %s)', v_blocking_name, v_blocking_ready_by)
    else null
  end;

  update public.schedule_blocks
  set crew_name = coalesce(p_crew_name, crew_name),
      start_date = v_start_date,
      end_date = v_end_date,
      blocked = v_blocked,
      blocked_reason = v_reason,
      updated_at = now()
  where id = p_schedule_block_id;
end;
$$;

create or replace function public.delete_schedule_block(p_schedule_block_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id
  from public.schedule_blocks where id = p_schedule_block_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'schedule block not found or not accessible: %', p_schedule_block_id;
  end if;

  delete from public.schedule_blocks where id = p_schedule_block_id;
end;
$$;
