-- StructTech OS — Week 2 Stage 3: live estimating schema (contractor-only)
--
-- NOT APPLIED. Author-only migration file — ask before applying, same as
-- every other migration in this repo. Depends on Stage 0/1 (org_id +
-- my_org_ids()-scoped RLS on deals; crm stage config + RPCs) already being
-- applied — create_estimate_from_deal() reads a deal's org_id/contact
-- fields the same way the Stage 1 RPCs do.
--
-- Three new tables, no existing ones touched — unlike Stage 0's backfill,
-- there's no legacy data to reconcile, so org_id is NOT NULL from the
-- start and RLS is the clean my_org_ids() pattern with no is_staff()
-- layering to preserve.
--
-- Two gaps worth flagging up front, both because the source data simply
-- doesn't exist yet elsewhere in the schema — not oversights:
--   1. "carrying contact/address... from the deal": deals has
--      contact_name/company/phone/email but NO address column at all (it
--      was built for StructTech's own sign-a-client funnel, never needed
--      one). create_estimate_from_deal() copies the four contact fields
--      that do exist; estimates.site_address is a new nullable field with
--      nothing to copy INTO it — it starts empty and gets filled during
--      the on-roof validate step (Stage 4 UI), not carried from the deal.
--      That's not a "no re-entry" violation (there's nothing to re-enter),
--      just new data the deal never captured.
--   2. "any known roof attributes from the deal": deals has no
--      roof-specific columns (no squares/pitch/roof_type) either.
--      estimates.squares/pitch start null on creation for the same reason
--      — nothing upstream to copy.
--
-- Two RPCs added beyond the requested list, both because the schema can't
-- support the stated preliminary -> validate -> present -> sign flow
-- without them:
--   - fetch_estimate(id): the single-record fetch RPC Stage 4's UI needs
--     per CLAUDE.md rule 4 (direct .select().eq(id).single() fails RLS) —
--     same reason fetch_deal exists.
--   - update_estimate_details(id, squares, pitch): the only way to persist
--     the on-roof squares/pitch numbers and advance preliminary ->
--     validated. Without it "validate & adjust" has no write path.
-- Flagging both rather than quietly expanding scope — cut them if you'd
-- rather Stage 4 own that decision.

-- ============================================================================
-- 1. estimates
-- ============================================================================
create table public.estimates (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  deal_id uuid not null references public.deals(id),
  status text not null default 'preliminary'
    check (status in ('preliminary', 'validated', 'presented', 'signed', 'void')),

  -- Contact fields copied from the deal at creation (see header note 1) —
  -- denormalized on purpose so the estimate is a stable snapshot even if
  -- the underlying deal's contact info changes later.
  contact_name text,
  company text,
  phone text,
  email text,
  site_address text,

  -- On-roof measurements — null until the validate step fills them in.
  squares numeric,
  pitch text,

  -- Kept in sync by trg_estimate_line_items_sync_subtotal (section 3)
  -- whenever estimate_line_items changes — never written directly by app
  -- code, only ever read.
  subtotal numeric not null default 0,

  -- Frozen at present_estimate() time (SCOPE.md §12C price-lock habit) —
  -- deliberately NOT kept in sync with subtotal after that point, even if
  -- line items are edited (they shouldn't be, once presented — see the
  -- lock check in the line-item RPCs — but presented_total staying frozen
  -- is the actual price-lock guarantee, independent of that lock holding).
  presented_total numeric,
  presented_at timestamptz,
  signed_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index estimates_org_id_idx on public.estimates(org_id);
create index estimates_deal_id_idx on public.estimates(deal_id);

comment on table public.estimates is
  'Live on-site estimate, generated from a deal. Flow: preliminary -> validated -> presented (frozen total) -> signed, or void.';
comment on column public.estimates.presented_total is
  'Snapshot of subtotal at present_estimate() time — the price-lock habit (SCOPE.md §12C). Not re-synced after presenting.';

alter table public.estimates enable row level security;

create policy "member read own estimates"
  on public.estimates for select
  using (org_id in (select my_org_ids()));

create policy "member insert own estimates"
  on public.estimates for insert
  with check (org_id in (select my_org_ids()));

create policy "member update own estimates"
  on public.estimates for update
  using (org_id in (select my_org_ids()))
  with check (org_id in (select my_org_ids()));

-- ============================================================================
-- 2. estimate_line_items
-- ============================================================================
create table public.estimate_line_items (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  estimate_id uuid not null references public.estimates(id) on delete cascade,

  -- SCOPE.md §12B — reserved for the future product catalog, deliberately
  -- no FK yet (no products table exists). Nullable: lines are not
  -- free-text only forever, but they are today.
  product_id uuid,

  description text not null,
  quantity numeric not null default 1,
  unit_price numeric not null default 0,
  -- Generated, not app-maintained — line_total can never drift from
  -- quantity * unit_price. estimates.subtotal (the sum across lines) is
  -- the thing that needs a trigger, not this.
  line_total numeric generated always as (quantity * unit_price) stored,
  sort_order int not null default 0,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index estimate_line_items_estimate_id_idx on public.estimate_line_items(estimate_id);
create index estimate_line_items_org_id_idx on public.estimate_line_items(org_id);

comment on column public.estimate_line_items.product_id is
  'Reserved for the future product catalog (SCOPE.md §12B) — no FK yet, no products table exists. Nullable: lines are free-text-only until then.';

alter table public.estimate_line_items enable row level security;

create policy "member read own estimate_line_items"
  on public.estimate_line_items for select
  using (org_id in (select my_org_ids()));

create policy "member insert own estimate_line_items"
  on public.estimate_line_items for insert
  with check (org_id in (select my_org_ids()));

create policy "member update own estimate_line_items"
  on public.estimate_line_items for update
  using (org_id in (select my_org_ids()))
  with check (org_id in (select my_org_ids()));

create policy "member delete own estimate_line_items"
  on public.estimate_line_items for delete
  using (org_id in (select my_org_ids()));

-- ============================================================================
-- 3. subtotal sync trigger — the single writer for estimates.subtotal.
-- None of the RPCs below touch it directly.
-- ============================================================================
create or replace function public.estimate_line_items_sync_subtotal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estimate_id uuid;
begin
  v_estimate_id := coalesce(new.estimate_id, old.estimate_id);

  update public.estimates
  set subtotal = coalesce(
        (select sum(line_total) from public.estimate_line_items where estimate_id = v_estimate_id),
        0
      ),
      updated_at = now()
  where id = v_estimate_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_estimate_line_items_sync_subtotal
after insert or update or delete on public.estimate_line_items
for each row execute function public.estimate_line_items_sync_subtotal();

-- ============================================================================
-- 4. signatures
-- ============================================================================
create table public.signatures (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  estimate_id uuid not null references public.estimates(id) on delete cascade,

  signer_name text not null,
  signer_role text not null,
  signature_data text not null,
  pdf_url text,

  -- Reserved for future remote signing (a client signing on their own
  -- device via a link, not the rep's phone in the same session). No
  -- anon/public RPC path reads this column yet — sign_estimate() below is
  -- authenticated-caller-only. Unique so it's usable as a lookup key
  -- whenever that lands; multiple NULLs are fine under a unique
  -- constraint, so this doesn't block same-session signing rows.
  sign_token text unique,

  signed_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index signatures_estimate_id_idx on public.signatures(estimate_id);
create index signatures_org_id_idx on public.signatures(org_id);

comment on column public.signatures.sign_token is
  'Reserved for future remote signing — no anon/public path uses it this phase. sign_estimate() is same-session, authenticated-caller-only.';

alter table public.signatures enable row level security;

create policy "member read own signatures"
  on public.signatures for select
  using (org_id in (select my_org_ids()));

create policy "member insert own signatures"
  on public.signatures for insert
  with check (org_id in (select my_org_ids()));

-- ============================================================================
-- 5. RPCs — all security-definer, org-scoped from the caller's own
-- membership (never a caller-supplied org_id trust assumption), per the
-- pattern established in Stage 1.
-- ============================================================================

-- 5a. create_estimate_from_deal — the shell estimate. See header note 1/2
-- for exactly what does and doesn't get carried over.
create or replace function public.create_estimate_from_deal(p_deal_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_contact_name text;
  v_company text;
  v_phone text;
  v_email text;
  v_estimate_id uuid;
begin
  select org_id, contact_name, company, phone, email
  into v_org_id, v_contact_name, v_company, v_phone, v_email
  from public.deals
  where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  insert into public.estimates (org_id, deal_id, contact_name, company, phone, email)
  values (v_org_id, p_deal_id, v_contact_name, v_company, v_phone, v_email)
  returning id into v_estimate_id;

  return v_estimate_id;
end;
$$;

-- 5b. fetch_estimate — single-record fetch RPC (rule 4). Not on the
-- requested list; see header note.
create or replace function public.fetch_estimate(p_estimate_id uuid)
returns setof public.estimates
language sql
security definer
stable
set search_path = public
as $$
  select e.*
  from public.estimates e
  where e.id = p_estimate_id
    and e.org_id in (select my_org_ids());
$$;

-- 5c. update_estimate_details — the validate step's write path. Not on
-- the requested list; see header note. Advances preliminary -> validated
-- the first time it's called (providing on-roof numbers IS the
-- validation), idempotent after that.
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

  if v_status not in ('preliminary', 'validated') then
    raise exception 'estimate % is locked (status: %)', p_estimate_id, v_status;
  end if;

  update public.estimates
  set squares = coalesce(p_squares, squares),
      pitch = coalesce(p_pitch, pitch),
      site_address = coalesce(p_site_address, site_address),
      status = case when status = 'preliminary' then 'validated' else status end,
      updated_at = now()
  where id = p_estimate_id;
end;
$$;

-- 5d. Line-item CRUD. All three gate on the parent estimate's status —
-- 'preliminary'/'validated' only, i.e. anything before present_estimate()
-- has frozen it. This is the actual enforcement of "present_estimate locks
-- further edits": present_estimate() doesn't need to do anything special
-- to the line items themselves, these three checks are the lock.
create or replace function public.add_estimate_line_item(
  p_estimate_id uuid,
  p_description text,
  p_quantity numeric default 1,
  p_unit_price numeric default 0,
  p_product_id uuid default null,
  p_sort_order int default 0
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

  if v_status not in ('preliminary', 'validated') then
    raise exception 'estimate % is locked (status: %) — line items can only change before presenting', p_estimate_id, v_status;
  end if;

  insert into public.estimate_line_items
    (org_id, estimate_id, product_id, description, quantity, unit_price, sort_order)
  values
    (v_org_id, p_estimate_id, p_product_id, p_description, p_quantity, p_unit_price, p_sort_order)
  returning id into v_line_id;

  return v_line_id;
end;
$$;

create or replace function public.update_estimate_line_item(
  p_line_item_id uuid,
  p_description text default null,
  p_quantity numeric default null,
  p_unit_price numeric default null,
  p_sort_order int default null
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

  if v_status not in ('preliminary', 'validated') then
    raise exception 'estimate is locked (status: %) — line items can only change before presenting', v_status;
  end if;

  update public.estimate_line_items
  set description = coalesce(p_description, description),
      quantity = coalesce(p_quantity, quantity),
      unit_price = coalesce(p_unit_price, unit_price),
      sort_order = coalesce(p_sort_order, sort_order),
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

  if v_status not in ('preliminary', 'validated') then
    raise exception 'estimate is locked (status: %) — line items can only change before presenting', v_status;
  end if;

  delete from public.estimate_line_items where id = p_line_item_id;
end;
$$;

-- 5e. present_estimate — freezes presented_total from the current
-- (trigger-maintained) subtotal, locks further line-item edits (via the
-- status checks above, not anything done here).
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

  if v_status not in ('preliminary', 'validated') then
    raise exception 'estimate % cannot be presented from status %', p_estimate_id, v_status;
  end if;

  update public.estimates
  set status = 'presented',
      presented_total = v_subtotal,
      presented_at = now()
  where id = p_estimate_id;
end;
$$;

-- 5f. sign_estimate — same-session, authenticated-caller-only (the rep's
-- own device). Requires 'presented' first, matching the stated flow order.
create or replace function public.sign_estimate(
  p_estimate_id uuid,
  p_signer_name text,
  p_signer_role text,
  p_signature_data text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_status text;
  v_signature_id uuid;
begin
  select org_id, status into v_org_id, v_status
  from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  if v_status <> 'presented' then
    raise exception 'estimate % must be presented before it can be signed (current status: %)', p_estimate_id, v_status;
  end if;

  insert into public.signatures (org_id, estimate_id, signer_name, signer_role, signature_data)
  values (v_org_id, p_estimate_id, p_signer_name, p_signer_role, p_signature_data)
  returning id into v_signature_id;

  update public.estimates
  set status = 'signed',
      signed_at = now()
  where id = p_estimate_id;

  return v_signature_id;
end;
$$;
