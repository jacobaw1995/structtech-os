-- StructTech OS — Phase A Week 2, Chunk 1: work_order_agreements data model.
--
-- NOT APPLIED. Author-only migration file — ask before applying.
--
-- Context: roadmap "Real homeowner sign-off + signed doc (both paths)" +
-- docs/reference/COORDINATION_MODULE_SCOPE.md §7-8. Locked decisions (Jacob
-- 7/29, this chunk): snapshot (not live reference) frozen at agreement
-- creation; one signature anchored to colors/finishes, not two; colors_
-- finishes as jsonb (shape TBD by the sign-off UI in chunk 2 — jsonb keeps
-- this migration from guessing field names); sign_token stored HASHED, not
-- plaintext (the existing signatures.sign_token column is plaintext —
-- deliberately not copying that here); work_orders.sign_off_at/notes stay
-- as a mirror, updated by the chunk-2 sign RPC, so coordinationStages()
-- and anything else already reading them keeps working unchanged.
--
-- Verified live before writing this file: work_order_agreements does not
-- exist (information_schema.tables), and none of
-- create_work_order_agreement/fetch_work_order_agreement exist in pg_proc
-- — a clean create, no overload risk.
--
-- Scope (chunk 1 only, per instruction): table + RLS + create/fetch RPCs.
-- No sign/void/remote-token RPCs yet — those are chunks 2/4. colors_finishes
-- defaults to '{}' at creation; chunk 2 fills it in as part of the sign
-- flow, chunk 1 just needs the column to exist.
--
-- ============================================================================
-- 1. work_order_agreements
-- ============================================================================
create table public.work_order_agreements (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  work_order_id uuid not null references public.work_orders(id) on delete cascade,

  status text not null default 'pending' check (status in ('pending', 'signed', 'voided')),

  -- Frozen at create_work_order_agreement() time — what was actually shown
  -- to the homeowner, immune to later edits to work_orders/material_items/
  -- schedule_blocks (§2.6 keeps those editable post-sign-off). Same
  -- reasoning as estimates.presented_total/tax_amount being locked at
  -- present_estimate() time. Never regenerated in place — a change order
  -- (later chunk) creates a NEW row with a new snapshot instead.
  snapshot jsonb not null,

  -- Structured colors/finishes capture — the field the hard signature
  -- requirement is anchored to. Shape intentionally undecided at the
  -- schema level; the chunk-2 sign-off form defines and validates it.
  colors_finishes jsonb not null default '{}'::jsonb,

  -- In-person signing (chunk 2).
  signer_name text,
  signer_role text,
  signature_data text,
  signed_at timestamptz,

  -- Remote/email signing (chunk 4) — hashed, never the plaintext token.
  -- The plaintext exists only transiently (generated, emailed, discarded)
  -- and is never written to this table.
  sign_token_hash text unique,
  sent_at timestamptz,

  -- Change-order void (later chunk uses this; column exists now so the
  -- versioned-entity shape is right from the start, per the §8 guardrail
  -- this whole table exists to satisfy).
  voided_at timestamptz,
  void_reason text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index work_order_agreements_work_order_id_idx on public.work_order_agreements(work_order_id);
create index work_order_agreements_org_id_idx on public.work_order_agreements(org_id);

-- Enforces "one active agreement per work order" (Jacob 7/29): a work
-- order can have any number of voided agreements (history), but at most
-- one pending-or-signed row at a time. A change order must void the
-- current one before a new one can be created.
create unique index work_order_agreements_one_active_idx
  on public.work_order_agreements(work_order_id)
  where status <> 'voided';

comment on table public.work_order_agreements is
  'Versioned sign-off agreement (COORDINATION_MODULE_SCOPE.md §8) — original + each change order as its own row, only one active (non-voided) at a time. Replaces work_orders.sign_off_at/sign_off_notes as the source of truth; those columns stay as a denormalized mirror, updated by the sign RPC (chunk 2).';
comment on column public.work_order_agreements.snapshot is
  'Frozen work order + estimate + materials + schedule at agreement-creation time — what was actually shown/signed, immune to later live edits.';
comment on column public.work_order_agreements.sign_token_hash is
  'Hash of the remote-signing link token (chunk 4), never the plaintext. Unlike signatures.sign_token (existing, plaintext, unused) — deliberate hardening for a bearer-credential link.';

-- ============================================================================
-- 2. RLS — org-scoped member read/write via my_org_ids(), same shape as
-- work_orders. No DELETE policy, deliberately: an agreement is voided
-- (status='voided'), never hard-deleted — same reasoning work_orders
-- itself already follows (no "member delete own work_orders" policy
-- either; deletion of a work order goes through delete_work_order(), which
-- is security-definer and bypasses RLS for its own internal DML). The
-- anon token-authorized read path for the remote-signing flow is chunk 4,
-- not this migration.
-- ============================================================================
alter table public.work_order_agreements enable row level security;

create policy "member read own work_order_agreements"
  on public.work_order_agreements for select
  using (org_id in (select my_org_ids()));

create policy "member insert own work_order_agreements"
  on public.work_order_agreements for insert
  with check (org_id in (select my_org_ids()));

create policy "member update own work_order_agreements"
  on public.work_order_agreements for update
  using (org_id in (select my_org_ids()))
  with check (org_id in (select my_org_ids()));

-- ============================================================================
-- 3. create_work_order_agreement(work_order_id) — builds the snapshot from
-- the LIVE work order/estimate/materials/schedule at call time, then
-- inserts a 'pending' row. Idempotent against the partial unique index,
-- same reasoning as create_work_order_from_estimate: a second call (double
-- click, a re-render racing a slow first insert) returns the existing
-- active agreement instead of hitting the unique-index violation.
-- ============================================================================
create or replace function public.create_work_order_agreement(p_work_order_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_existing_id uuid;
  v_snapshot jsonb;
  v_agreement_id uuid;
begin
  select org_id into v_org_id
  from public.work_orders where id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  select id into v_existing_id
  from public.work_order_agreements
  where work_order_id = p_work_order_id and status <> 'voided';

  if v_existing_id is not null then
    return v_existing_id;
  end if;

  select jsonb_build_object(
    'work_order', jsonb_build_object(
      'id', wo.id,
      'sign_off_notes', wo.sign_off_notes
    ),
    'estimate', jsonb_build_object(
      'id', e.id,
      'estimate_number', e.estimate_number,
      'contact_name', e.contact_name,
      'company', e.company,
      'phone', e.phone,
      'email', e.email,
      'site_address', e.site_address,
      'squares', e.squares,
      'pitch', e.pitch
    ),
    'materials', coalesce((
      select jsonb_agg(
        jsonb_build_object('name', mi.name, 'quantity', mi.quantity, 'ready_by', mi.ready_by)
        order by mi.sort_order
      )
      from public.material_items mi
      where mi.work_order_id = p_work_order_id
    ), '[]'::jsonb),
    'schedule', coalesce((
      select jsonb_agg(
        jsonb_build_object('crew_name', sb.crew_name, 'start_date', sb.start_date, 'end_date', sb.end_date)
        order by sb.start_date
      )
      from public.schedule_blocks sb
      where sb.work_order_id = p_work_order_id
    ), '[]'::jsonb)
  )
  into v_snapshot
  from public.work_orders wo
  join public.estimates e on e.id = wo.estimate_id
  where wo.id = p_work_order_id;

  insert into public.work_order_agreements (org_id, work_order_id, snapshot)
  values (v_org_id, p_work_order_id, v_snapshot)
  returning id into v_agreement_id;

  return v_agreement_id;
end;
$$;

comment on function public.create_work_order_agreement(uuid) is
  'Creates the pending sign-off agreement for a work order, snapshotting the current work order/estimate/materials/schedule. Idempotent — returns the existing active agreement if one already exists rather than erroring on the partial unique index.';

-- ============================================================================
-- 4. fetch_work_order_agreement(work_order_id) — single-record fetch RPC
-- (CLAUDE.md rule 4), returns the one active (non-voided) agreement for a
-- work order, or no rows if none exists yet. Listing the full version
-- history (voided rows included) is a plain list query per rule 5 — no
-- RPC needed for that, RLS already scopes it correctly.
-- ============================================================================
create or replace function public.fetch_work_order_agreement(p_work_order_id uuid)
returns setof public.work_order_agreements
language sql
security definer
stable
set search_path = public
as $$
  select a.*
  from public.work_order_agreements a
  where a.work_order_id = p_work_order_id
    and a.status <> 'voided'
    and a.org_id in (select my_org_ids())
  order by a.created_at desc
  limit 1;
$$;

comment on function public.fetch_work_order_agreement(uuid) is
  'Returns the single active (non-voided) agreement for a work order, if any.';
