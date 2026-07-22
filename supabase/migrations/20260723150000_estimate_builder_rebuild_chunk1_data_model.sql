-- StructTech OS — Estimate builder rebuild, Chunk 1: data model
--
-- NOT APPLIED. Author-only migration file — ask before applying, same as
-- every other migration in this repo.
--
-- Rebuilds the 4-step estimating wizard (preliminary -> validate -> present
-- -> sign) into a document-as-editor (Joist model): the editor IS the
-- document the customer receives. This migration only adds the columns/
-- table/RPC changes the document model needs — no UI changes here (that's
-- Chunks 2-5).
--
-- Two decisions this migration encodes, both confirmed with Jacob before
-- writing:
--
--   1. PRESENT DOES NOT FREEZE. Old behavior: present_estimate() locked
--      every line-item RPC from editing further (SCOPE §12C price-lock
--      habit taken literally as a hard gate). That's the exact thing
--      SCOPE §2.8 ("never block the user") rules out — revising a quote
--      live in front of the customer is the sale, not an edge case. New
--      behavior: only 'signed' and 'void' freeze the document.
--      present_estimate() still snapshots presented_total/presented_at —
--      that snapshot just isn't a lock anymore, and doesn't silently
--      re-sync if the live subtotal moves after presenting (the UI is
--      expected to show "edited since presented" and display the live
--      total — that's a Chunk 2/3 concern, not this migration's).
--      Backlogged, not built now: a FULL presented-snapshot (frozen line
--      items, or a stored rendered PDF) once R2 lands — presented_total
--      alone is a thin record of "what the customer saw," which is judged
--      good enough for now.
--
--   2. Status simplifies from preliminary/validated/presented/signed/void
--      to draft/presented/signed/void. 'signed' is kept as a literal value
--      on purpose — create_work_order_from_estimate() (coordination
--      module, 20260713120000) gates only on status = 'signed' and is not
--      touched by this migration at all.
--
-- Constraint-order note (flagged in review): the old constraint must be
-- DROPPED before rows are updated to 'draft' — 'draft' isn't legal under
-- the OLD check, so updating rows first would abort mid-migration. Same
-- ordering bug class as the lead_type fix (20260714180000). Order here is
-- DROP -> UPDATE rows -> ADD new constraint.
--
-- estimate_number_counters is a new table, RLS enabled with NO policies —
-- deny-all for anon/authenticated, definer-only (same pattern as the BMR
-- migration staging tables, 20260723120000). App code never reads/writes
-- it directly; only create_estimate_from_deal() (security definer) touches
-- it, to claim the next per-org "EST-####" number atomically.
--
-- Live DB state confirmed before writing this: 2 rows in estimates (both
-- 'preliminary'), 0 rows in estimate_line_items, 0 in signatures —
-- genuinely greenfield, so the status backfill below touches at most 2
-- rows and there's no line-item/signature data at risk.

-- ============================================================================
-- 1. estimate_number_counters — per-org sequence, definer-only
-- ============================================================================
create table public.estimate_number_counters (
  org_id uuid primary key references public.organizations(id),
  next_number int not null default 1
);

comment on table public.estimate_number_counters is
  'Per-org counter for human-readable estimate_number ("EST-1042"). Claimed atomically by create_estimate_from_deal() via INSERT ... ON CONFLICT DO UPDATE (row lock, no race). Never read/written directly by app code.';

alter table public.estimate_number_counters enable row level security;
-- Deliberately no policies: deny-all for anon/authenticated, definer-only.

-- ============================================================================
-- 2. estimates — new document-level columns
-- ============================================================================
alter table public.estimates
  add column estimate_number text,
  add column notes_terms text,
  add column tax_rate numeric,
  add column estimate_date date default current_date,
  add column valid_until date,
  add column build_mode text not null default 'manual' check (build_mode in ('manual', 'guided'));

-- Separate statement: tax_amount's generated expression references
-- tax_rate, which must already exist as a real column first. Mirrors
-- line_total's existing pattern (estimate_line_items, 20260712140000) —
-- generated, not app-maintained, so it can never drift from subtotal *
-- tax_rate the way a trigger could if a call site forgot to invoke it.
alter table public.estimates
  add column tax_amount numeric generated always as (round(subtotal * coalesce(tax_rate, 0), 2)) stored;

comment on column public.estimates.estimate_number is
  'Human-readable per-org number ("EST-1042"), claimed from estimate_number_counters at creation. Nullable: the 2 pre-existing rows have none and aren''t backfilled — nothing reads this as required.';
comment on column public.estimates.tax_amount is
  'Generated from subtotal * tax_rate, same reasoning as estimate_line_items.line_total — never written directly.';
comment on column public.estimates.build_mode is
  'Manual (default — Isaac types line items directly, any order) vs Guided (line items generated from the site-visit scope checklist + pricing matrix, Chunk 4). Switchable both ways without losing manual edits.';

-- ============================================================================
-- 3. estimate_line_items — unit column
-- ============================================================================
alter table public.estimate_line_items
  add column unit text;

comment on column public.estimate_line_items.unit is
  'Free text (ea/sq/lf/hr/...), no enum lock-in — same reasoning as product_id staying unconstrained until a real catalog exists.';

-- ============================================================================
-- 4. status simplification — DROP old constraint BEFORE touching rows
-- ============================================================================
alter table public.estimates drop constraint estimates_status_check;

update public.estimates set status = 'draft' where status in ('preliminary', 'validated');

alter table public.estimates add constraint estimates_status_check
  check (status in ('draft', 'presented', 'signed', 'void'));

comment on table public.estimates is
  'Live on-site estimate, generated from a deal. Status: draft -> presented (snapshot, not a lock) -> signed, or void. Only signed/void freeze the document (SCOPE §2.8 — presenting no longer locks edits).';

-- ============================================================================
-- 5. RPC changes
-- ============================================================================

-- 5a. create_estimate_from_deal — claims estimate_number + sets
-- estimate_date at creation. Same signature (p_deal_id uuid), everything
-- else about it (structured-address preference, contact copy) unchanged
-- from 20260716140000.
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
  v_next_number int;
  v_estimate_number text;
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

  -- Atomic claim: INSERT ... ON CONFLICT takes a row lock on the counter
  -- row, so two concurrent creates for the same org can't claim the same
  -- number. First-ever call for an org inserts next_number=2 and returns
  -- 2-1=1; every later call updates next_number=N+1 and returns (N+1)-1=N
  -- (the value the counter held before this call) — same claimed-value-
  -- then-bump semantics either way.
  insert into public.estimate_number_counters (org_id, next_number)
  values (v_org_id, 2)
  on conflict (org_id) do update set next_number = estimate_number_counters.next_number + 1
  returning next_number - 1 into v_next_number;

  v_estimate_number := 'EST-' || v_next_number;

  insert into public.estimates
    (org_id, deal_id, contact_name, company, phone, email, site_address, estimate_number, estimate_date)
  values
    (v_org_id, p_deal_id, v_contact_name, v_company, v_phone, v_email, v_site_address, v_estimate_number, current_date)
  returning id into v_estimate_id;

  return v_estimate_id;
end;
$function$;

-- 5b. update_estimate_details — required fix, not a feature add: the old
-- gate (`status not in ('preliminary','validated')`) would always raise
-- once those values stop existing, permanently locking this RPC. Relaxed
-- to the same signed/void-only gate as everything else, and the
-- preliminary->validated auto-advance line is removed outright (that
-- status pair no longer exists — squares/pitch/site_address are just
-- editable document fields now, no separate "validate" transition).
create or replace function public.update_estimate_details(
  p_estimate_id uuid,
  p_squares numeric default null,
  p_pitch text default null,
  p_site_address text default null
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
      updated_at = now()
  where id = p_estimate_id;
end;
$$;

-- 5c. present_estimate — snapshot, not a lock. Callable from 'draft' or
-- 'presented' (re-present re-snapshots after edits); refuses signed/void.
create or replace function public.present_estimate(p_estimate_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_status text;
  v_subtotal numeric;
begin
  select org_id, status, subtotal into v_org_id, v_status, v_subtotal
  from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  if v_status in ('signed', 'void') then
    raise exception 'estimate % cannot be presented from status %', p_estimate_id, v_status;
  end if;

  update public.estimates
  set status = 'presented',
      presented_total = v_subtotal,
      presented_at = now()
  where id = p_estimate_id;
end;
$$;

-- 5d. Line-item CRUD — relaxed to block only signed/void (was
-- preliminary/validated-only, i.e. anything before present_estimate()
-- locked it). Also thread the new p_unit param through add/update.
--
-- OVERLOAD TRAP (caught in review): adding p_unit changes both signatures.
-- CREATE OR REPLACE only replaces a function with the SAME argument list —
-- a changed signature creates a SECOND overload instead, leaving the old
-- 6-arg version live alongside the new 7-arg one. "New params are trailing
-- defaults, safe for existing named-parameter callers" is a statement about
-- callers, not about overloads; PostgREST/Postgres still needs the old
-- signature gone. Exact live signatures confirmed against pg_proc before
-- writing these drops.
drop function if exists public.add_estimate_line_item(uuid, text, numeric, numeric, uuid, integer);
drop function if exists public.update_estimate_line_item(uuid, text, numeric, numeric, integer);

create or replace function public.add_estimate_line_item(
  p_estimate_id uuid,
  p_description text,
  p_quantity numeric default 1,
  p_unit_price numeric default 0,
  p_product_id uuid default null,
  p_sort_order int default 0,
  p_unit text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_status text;
  v_line_id uuid;
begin
  select org_id, status into v_org_id, v_status
  from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  if v_status in ('signed', 'void') then
    raise exception 'estimate % is locked (status: %) — line items can only change before signing', p_estimate_id, v_status;
  end if;

  insert into public.estimate_line_items
    (org_id, estimate_id, product_id, description, quantity, unit_price, sort_order, unit)
  values
    (v_org_id, p_estimate_id, p_product_id, p_description, p_quantity, p_unit_price, p_sort_order, p_unit)
  returning id into v_line_id;

  return v_line_id;
end;
$$;

create or replace function public.update_estimate_line_item(
  p_line_item_id uuid,
  p_description text default null,
  p_quantity numeric default null,
  p_unit_price numeric default null,
  p_sort_order int default null,
  p_unit text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_estimate_id uuid;
  v_status text;
begin
  select li.org_id, li.estimate_id into v_org_id, v_estimate_id
  from public.estimate_line_items li
  where li.id = p_line_item_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'line item not found or not accessible: %', p_line_item_id;
  end if;

  select status into v_status from public.estimates where id = v_estimate_id;

  if v_status in ('signed', 'void') then
    raise exception 'estimate is locked (status: %) — line items can only change before signing', v_status;
  end if;

  update public.estimate_line_items
  set description = coalesce(p_description, description),
      quantity = coalesce(p_quantity, quantity),
      unit_price = coalesce(p_unit_price, unit_price),
      sort_order = coalesce(p_sort_order, sort_order),
      unit = coalesce(p_unit, unit),
      updated_at = now()
  where id = p_line_item_id;
end;
$$;

create or replace function public.delete_estimate_line_item(p_line_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_estimate_id uuid;
  v_status text;
begin
  select li.org_id, li.estimate_id into v_org_id, v_estimate_id
  from public.estimate_line_items li
  where li.id = p_line_item_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'line item not found or not accessible: %', p_line_item_id;
  end if;

  select status into v_status from public.estimates where id = v_estimate_id;

  if v_status in ('signed', 'void') then
    raise exception 'estimate is locked (status: %) — line items can only change before signing', v_status;
  end if;

  delete from public.estimate_line_items where id = p_line_item_id;
end;
$$;

-- 5e. reorder_estimate_line_items — new. Batch version of the p_sort_order
-- param update_estimate_line_item already had (unused until now): sets
-- sort_order to array index for each id, one transaction. IDs that don't
-- belong to p_estimate_id are silently skipped (the AND estimate_id =
-- p_estimate_id guard), not raised — same tolerant-of-mismatch style as
-- the coalesce-based updates above.
create or replace function public.reorder_estimate_line_items(
  p_estimate_id uuid,
  p_line_item_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_status text;
  v_id uuid;
  v_idx int := 0;
begin
  select org_id, status into v_org_id, v_status
  from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  if v_status in ('signed', 'void') then
    raise exception 'estimate % is locked (status: %) — cannot reorder line items', p_estimate_id, v_status;
  end if;

  foreach v_id in array p_line_item_ids loop
    update public.estimate_line_items
    set sort_order = v_idx, updated_at = now()
    where id = v_id and estimate_id = p_estimate_id;
    v_idx := v_idx + 1;
  end loop;
end;
$$;

-- Not touched by this migration, and confirmed why:
--   - sign_estimate() already gates on `status <> 'presented'`, which
--     remains a legal value under the new enum — no change needed.
--   - update_estimate_contact() / void_estimate() / delete_estimate() have
--     no status-value gates at all (20260713180000) — unaffected by the
--     enum rename.
--   - create_work_order_from_estimate() (coordination, 20260713120000)
--     gates only on status = 'signed' — unaffected, per the Chunk 0 audit.
