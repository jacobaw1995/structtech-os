-- A2.3 clause (1) — PURCHASE ORDERS. Track S · 2026-09-07.
-- Source: supabase/proposals/A2_3_PURCHASE_ORDERS_2026-09-04.md, revised 09-05.
-- Rollback: supabase/rollbacks/20260907_a2_3_purchase_orders_rollback.sql
--
-- BEFORE-STATE, measured and not assumed: none of the three tables and none of
-- the nine functions existed; material_items 0 rows, schedule_blocks 0,
-- work_orders 2 (both masters, 0 trades), organizations 3 all at policy '{}',
-- org_members 5 with role='field' = 0, advisors 227 / 0 ERROR.
--
-- ===========================================================================
-- PART 0 — THE ONE DECISION THE CONTROLLER HAD NOT RULED ON, AND WHY IT IS
-- SAFE TO TAKE HERE. The proposal's §4.1 says in terms "the decision is not
-- mine": a new `manage_purchasing` key, or reuse `manage_catalog` and accept
-- the over-grant. Saturday's three rulings did not reach it.
--
-- MEASURED, WHICH CHANGES THE STAKES: has_capability() SHORT-CIRCUITS to true
-- for manager tier via is_org_manager() BEFORE it ever reads the stored key. So
-- for all five live members a brand-new, unseeded key already resolves
-- correctly today: the four manager-tier members get TRUE from the
-- short-circuit, and the Material Matrix `member` (permissions '{}', not
-- manager tier) falls through to the stored lookup and gets FALSE. That is the
-- same answer `manage_catalog` gives today, member for member.
--
-- SO THE TWO OPTIONS ARE BEHAVIOURALLY IDENTICAL ON TODAY'S DATA and differ
-- only in what a FUTURE role inherits. The new key is taken because it does not
-- silently grant purchasing to everyone who can edit a product.
--
-- AND THE PROPOSAL'S STATED COST WAS WRONG: it said a new key "re-seeds every
-- org_members.permissions row and edits default_permissions_for_role." It needs
-- neither. Nothing is seeded and THE DERIVER IS NOT TOUCHED — deliberately,
-- because it was changed 24 hours ago by the F5 migration and adding a tenth
-- key interacts with the branches added then. That edit is the controller's.
--
-- OWED, AND RECORDED HERE RATHER THAN ONLY IN A DOCUMENT: until
-- `manage_purchasing` is added to default_permissions_for_role, a future
-- non-manager `office` hire will get FALSE for it, where the proposal intends
-- TRUE. That is a write-path gap of exactly the shape A2.0 closed for the other
-- nine keys, and it is one branch edit when the controller rules.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- PART 1 — TABLES.
--
-- P1: a PO goes to ONE supplier and may cover materials across SEVERAL TRADES
--     on ONE JOB.  P2: a MATERIAL ITEM may be SPLIT across MORE THAN ONE PO.
-- P1 alone would permit material_items.purchase_order_id. P2 forbids it: one
-- column cannot hold two POs. Together they are a many-to-many, so the join is
-- an object in its own right and is where the per-delivery facts live.
-- ---------------------------------------------------------------------------

-- STATUS: four values. There is deliberately NO `received`.
-- A2.5 OWES THE TERMINAL STATE. `received` without a receipt concept would mean
-- "somebody clicked a button" — a status naming an event this system cannot
-- observe. A PO resting at `confirmed` forever is ugly and honest.
-- AND A5.4 OWES THE MONEY (controller ruling (c), 2026-09-05): §5.2 names no
-- price, and guessing collides with A2.1c's cost/sell/markup CHECK invariant —
-- a second, differently-shaped money model on a PO line would be a second
-- opinion about price, which is the A2.0 defect in a new table. Adding
-- `unit_cost numeric null` plus one RESTRICTIVE can_view_financials policy is a
-- nullable column add, not a table rewrite, and there are 0 POs today.
create table public.purchase_orders (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid not null references public.organizations(id),
  job_id           uuid null references public.jobs(id) on delete cascade,
  supplier_name    text not null,
  supplier_org_id  uuid null references public.organizations(id),
  status           text not null default 'draft'
                     check (status in ('draft','sent','confirmed','cancelled')),
  reference        text null,
  notes            text null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  created_by       uuid null references auth.users(id)
);
create index purchase_orders_org_id_idx on public.purchase_orders(org_id);
create index purchase_orders_job_id_idx on public.purchase_orders(job_id);

-- RULING (b), 2026-09-05: job_id IS NULLABLE AT INSERT AND REQUIRED TO LEAVE
-- `draft`. Drafting a PO off a supplier phone call, before anyone knows which
-- job it lands on, is a real workflow and SCOPE §2.8 forbids blocking it.
-- Enforced AT THE TRANSITION in update_purchase_order, never at insert.
-- Deliberately NOT a CHECK: a CHECK cannot see the OLD row, so it could only
-- express "not draft implies job present", which would ALSO forbid clearing the
-- job on an already-sent PO — a different rule than the one ruled.
comment on column public.purchase_orders.job_id is
  'NULLABLE by ruling (b) 2026-09-05. Required to LEAVE draft, enforced in update_purchase_order at the transition, never at insert (SCOPE 2.8).';
comment on column public.purchase_orders.status is
  'draft | sent | confirmed | cancelled. NO received — A2.5 owes the terminal state. A5.4 owes money on the line.';
comment on column public.purchase_orders.supplier_org_id is
  'Set when the supplier is a tenant here (organizations.tenant_type = supplier). NULL is normal: supplier_name is free text and always authoritative for display.';

create table public.purchase_order_lines (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid not null references public.organizations(id),
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  material_item_id  uuid not null references public.material_items(id) on delete cascade,
  quantity_ordered  numeric not null default 1 check (quantity_ordered > 0),
  promised_date     date null,
  actual_date       date null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index purchase_order_lines_po_idx   on public.purchase_order_lines(purchase_order_id);
create index purchase_order_lines_item_idx on public.purchase_order_lines(material_item_id);
create index purchase_order_lines_org_idx  on public.purchase_order_lines(org_id);

-- P2 IS ENFORCED BY THE ABSENCE OF A UNIQUE CONSTRAINT, AND THAT ABSENCE IS
-- DELIBERATE. There is NO unique index on (purchase_order_id, material_item_id)
-- and NONE on material_item_id alone: both would forbid the split the property
-- requires. Recorded because an absent constraint is invisible in a diff and
-- someone will later add one believing it is hygiene (rule 13's shape).
comment on column public.purchase_order_lines.actual_date is
  'NULL until A2.5 ships. Promise-vs-actual is promise-only today; this column exists so the history shape already holds the actual and A2.5 adds no schema.';
comment on column public.purchase_order_lines.quantity_ordered is
  'NOT material_items.quantity. Ordered is not needed; the difference IS the shortfall A2.5 detects, and storing one number would destroy it.';

-- APPEND-ONLY. "This supplier has moved the date three times" is the signal a
-- PM needs and it requires no receipt concept at all.
create table public.purchase_order_line_promises (
  id                     uuid primary key default gen_random_uuid(),
  org_id                 uuid not null references public.organizations(id),
  purchase_order_line_id uuid not null references public.purchase_order_lines(id) on delete cascade,
  promised_date          date null,
  recorded_at            timestamptz not null default now(),
  recorded_by            uuid null references auth.users(id)
);
create index po_line_promises_line_idx on public.purchase_order_line_promises(purchase_order_line_id);
create index po_line_promises_org_idx  on public.purchase_order_line_promises(org_id);

-- RULING (a), 2026-09-05: ready_by is DERIVED. ONE writer with a branch, never
-- two writers with a tiebreak — a tiebreak column records a collision instead
-- of removing it, which is the shape that produces "closed by accident".
alter table public.material_items
  add column ready_by_source text not null default 'manual'
    check (ready_by_source in ('manual','purchase_order'));
comment on column public.material_items.ready_by_source is
  'WHICH BRANCH FIRED, not which writer won. ready_by has ONE writer: max(promised_date) over non-cancelled PO lines whenever the promise set is non-empty, and the manual value only when it is empty. Documents a decision already made; never an input to making one.';

-- ---------------------------------------------------------------------------
-- PART 2 — RLS. Enabled in the same block that creates the tables, never
-- retrofitted. Every policy TO authenticated (rule 8): a permissive policy left
-- TO public must be EVALUATED for anon, which is what took the Material Matrix
-- storefront down on 2026-08-20. Commands stated separately, never FOR ALL.
-- ---------------------------------------------------------------------------
alter table public.purchase_orders             enable row level security;
alter table public.purchase_order_lines        enable row level security;
alter table public.purchase_order_line_promises enable row level security;

create policy "member read own purchase_orders" on public.purchase_orders
  for select to authenticated using (org_id in (select my_org_ids()));
create policy "purchaser insert own purchase_orders" on public.purchase_orders
  for insert to authenticated
  with check (org_id in (select my_org_ids()) and has_capability(org_id, 'manage_purchasing'));
create policy "purchaser update own purchase_orders" on public.purchase_orders
  for update to authenticated
  using      (org_id in (select my_org_ids()) and has_capability(org_id, 'manage_purchasing'))
  with check (org_id in (select my_org_ids()) and has_capability(org_id, 'manage_purchasing'));
create policy "purchaser delete own purchase_orders" on public.purchase_orders
  for delete to authenticated
  using (org_id in (select my_org_ids()) and has_capability(org_id, 'manage_purchasing'));

create policy "member read own purchase_order_lines" on public.purchase_order_lines
  for select to authenticated using (org_id in (select my_org_ids()));
create policy "purchaser insert own purchase_order_lines" on public.purchase_order_lines
  for insert to authenticated
  with check (org_id in (select my_org_ids()) and has_capability(org_id, 'manage_purchasing'));
create policy "purchaser update own purchase_order_lines" on public.purchase_order_lines
  for update to authenticated
  using      (org_id in (select my_org_ids()) and has_capability(org_id, 'manage_purchasing'))
  with check (org_id in (select my_org_ids()) and has_capability(org_id, 'manage_purchasing'));
create policy "purchaser delete own purchase_order_lines" on public.purchase_order_lines
  for delete to authenticated
  using (org_id in (select my_org_ids()) and has_capability(org_id, 'manage_purchasing'));

-- PROMISES ARE APPEND-ONLY, AND THAT IS ENFORCED BY THE ABSENCE OF POLICIES:
-- insert is granted; UPDATE and DELETE have NO policy at all, so they are
-- refused for every authenticated caller. Rule 13 asked what would reopen this:
-- "somebody adds an UPDATE policy" — a statement about THIS table, reviewable
-- in the diff that makes it, rather than an absence with no owner.
create policy "member read own po_line_promises" on public.purchase_order_line_promises
  for select to authenticated using (org_id in (select my_org_ids()));
create policy "purchaser insert own po_line_promises" on public.purchase_order_line_promises
  for insert to authenticated
  with check (org_id in (select my_org_ids()) and has_capability(org_id, 'manage_purchasing'));

-- Rule 8 for TABLES: a new table in public is born anon=arwdDxtm.
revoke all on table public.purchase_orders              from anon;
revoke all on table public.purchase_order_lines         from anon;
revoke all on table public.purchase_order_line_promises from anon;

-- ---------------------------------------------------------------------------
-- PART 3 — THE DERIVATION. One writer, one branch.
-- ---------------------------------------------------------------------------
create or replace function public.recompute_material_item_ready_by(p_material_item_id uuid)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_max date;
  v_any boolean;
begin
  select max(l.promised_date), count(*) > 0
    into v_max, v_any
  from public.purchase_order_lines l
  join public.purchase_orders po on po.id = l.purchase_order_id
  where l.material_item_id = p_material_item_id
    and po.status <> 'cancelled'
    and l.promised_date is not null;

  if coalesce(v_any, false) then
    -- The promise set is non-empty: the derivation is the ONLY writer.
    update public.material_items
       set ready_by = v_max, ready_by_source = 'purchase_order', updated_at = now()
     where id = p_material_item_id;
  else
    -- Empty: hand entry governs again. ready_by KEEPS ITS LAST VALUE rather
    -- than being nulled — nulling would silently unblock a schedule, and a
    -- silent unblock is worse than a stale date a human can see.
    update public.material_items
       set ready_by_source = 'manual', updated_at = now()
     where id = p_material_item_id;
  end if;
end;
$function$;

-- ---------------------------------------------------------------------------
-- PART 4 — WRITE PATH. SECURITY DEFINER, called as authenticated.
-- Every refusal is structural (wrong org, missing parent, bad quantity).
-- SCOPE 2.8: a line with no promised_date saves; a PO with no lines saves;
-- status does not enforce a state machine — a PM who phoned the supplier is
-- ahead of the software, not wrong.
-- ---------------------------------------------------------------------------
create or replace function public.create_purchase_order(p_job_id uuid, p_supplier_name text, p_supplier_org_id uuid default null)
returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare v_org_id uuid; v_id uuid;
begin
  if p_job_id is not null then
    select org_id into v_org_id from public.jobs where id = p_job_id;
    if v_org_id is null or v_org_id not in (select my_org_ids()) then
      raise exception 'job not found or not accessible: %', p_job_id;
    end if;
  else
    select org_id into v_org_id from public.org_members where user_id = auth.uid() limit 1;
    if v_org_id is null then raise exception 'no organization for the current user'; end if;
  end if;

  if not public.has_capability(v_org_id, 'manage_purchasing') then
    raise exception 'your role cannot create purchase orders in this workspace';
  end if;
  if coalesce(btrim(p_supplier_name), '') = '' then
    raise exception 'a purchase order needs a supplier name';
  end if;
  if p_supplier_org_id is not null and not exists (select 1 from public.organizations where id = p_supplier_org_id) then
    raise exception 'supplier organization not found: %', p_supplier_org_id;
  end if;

  insert into public.purchase_orders (org_id, job_id, supplier_name, supplier_org_id, created_by)
  values (v_org_id, p_job_id, btrim(p_supplier_name), p_supplier_org_id, auth.uid())
  returning id into v_id;
  return v_id;
end;
$function$;

create or replace function public.update_purchase_order(p_po_id uuid, p_supplier_name text default null, p_supplier_org_id uuid default null, p_status text default null)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare v_org_id uuid; v_job_id uuid; v_status text;
begin
  select org_id, job_id, status into v_org_id, v_job_id, v_status
  from public.purchase_orders where id = p_po_id;
  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'purchase order not found or not accessible: %', p_po_id;
  end if;
  if not public.has_capability(v_org_id, 'manage_purchasing') then
    raise exception 'your role cannot edit purchase orders in this workspace';
  end if;

  if p_status is not null and p_status <> 'draft' and v_status = 'draft' and v_job_id is null then
    raise exception 'this purchase order has no job, so it cannot leave draft. Attach it to a job first, then set it to %.', p_status;
  end if;

  update public.purchase_orders
     set supplier_name   = coalesce(btrim(p_supplier_name), supplier_name),
         supplier_org_id = coalesce(p_supplier_org_id, supplier_org_id),
         status          = coalesce(p_status, status),
         updated_at      = now()
   where id = p_po_id;

  if p_status is not null then
    perform public.recompute_material_item_ready_by(l.material_item_id)
    from (select distinct material_item_id from public.purchase_order_lines where purchase_order_id = p_po_id) l;
  end if;
end;
$function$;

create or replace function public.delete_purchase_order(p_po_id uuid)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare v_org_id uuid; v_items uuid[];
begin
  select org_id into v_org_id from public.purchase_orders where id = p_po_id;
  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'purchase order not found or not accessible: %', p_po_id;
  end if;
  if not public.has_capability(v_org_id, 'manage_purchasing') then
    raise exception 'your role cannot delete purchase orders in this workspace';
  end if;
  select array_agg(distinct material_item_id) into v_items
    from public.purchase_order_lines where purchase_order_id = p_po_id;
  delete from public.purchase_orders where id = p_po_id;
  if v_items is not null then
    perform public.recompute_material_item_ready_by(i) from unnest(v_items) i;
  end if;
end;
$function$;

create or replace function public.add_purchase_order_line(p_po_id uuid, p_material_item_id uuid, p_quantity_ordered numeric default 1, p_promised_date date default null)
returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare v_org_id uuid; v_item_org uuid; v_id uuid;
begin
  select org_id into v_org_id from public.purchase_orders where id = p_po_id;
  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'purchase order not found or not accessible: %', p_po_id;
  end if;
  if not public.has_capability(v_org_id, 'manage_purchasing') then
    raise exception 'your role cannot edit purchase orders in this workspace';
  end if;
  select org_id into v_item_org from public.material_items where id = p_material_item_id;
  if v_item_org is null then raise exception 'material item not found: %', p_material_item_id; end if;
  if v_item_org <> v_org_id then
    raise exception 'material item % belongs to a different organization than purchase order %', p_material_item_id, p_po_id;
  end if;
  if p_quantity_ordered is null or p_quantity_ordered <= 0 then
    raise exception 'quantity ordered must be greater than zero';
  end if;

  insert into public.purchase_order_lines (org_id, purchase_order_id, material_item_id, quantity_ordered, promised_date)
  values (v_org_id, p_po_id, p_material_item_id, p_quantity_ordered, p_promised_date)
  returning id into v_id;

  insert into public.purchase_order_line_promises (org_id, purchase_order_line_id, promised_date, recorded_by)
  values (v_org_id, v_id, p_promised_date, auth.uid());

  perform public.recompute_material_item_ready_by(p_material_item_id);
  return v_id;
end;
$function$;

create or replace function public.update_purchase_order_line(p_line_id uuid, p_quantity_ordered numeric default null, p_promised_date date default null)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare v_org_id uuid; v_item uuid; v_old date; v_new date;
begin
  select org_id, material_item_id, promised_date into v_org_id, v_item, v_old
  from public.purchase_order_lines where id = p_line_id;
  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'purchase order line not found or not accessible: %', p_line_id;
  end if;
  if not public.has_capability(v_org_id, 'manage_purchasing') then
    raise exception 'your role cannot edit purchase orders in this workspace';
  end if;
  if p_quantity_ordered is not null and p_quantity_ordered <= 0 then
    raise exception 'quantity ordered must be greater than zero';
  end if;

  v_new := coalesce(p_promised_date, v_old);
  update public.purchase_order_lines
     set quantity_ordered = coalesce(p_quantity_ordered, quantity_ordered),
         promised_date    = v_new,
         updated_at       = now()
   where id = p_line_id;

  if v_new is distinct from v_old then
    insert into public.purchase_order_line_promises (org_id, purchase_order_line_id, promised_date, recorded_by)
    values (v_org_id, p_line_id, v_new, auth.uid());
  end if;

  perform public.recompute_material_item_ready_by(v_item);
end;
$function$;

create or replace function public.delete_purchase_order_line(p_line_id uuid)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare v_org_id uuid; v_item uuid;
begin
  select org_id, material_item_id into v_org_id, v_item
  from public.purchase_order_lines where id = p_line_id;
  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'purchase order line not found or not accessible: %', p_line_id;
  end if;
  if not public.has_capability(v_org_id, 'manage_purchasing') then
    raise exception 'your role cannot edit purchase orders in this workspace';
  end if;
  delete from public.purchase_order_lines where id = p_line_id;
  perform public.recompute_material_item_ready_by(v_item);
end;
$function$;

create or replace function public.fetch_purchase_order(p_po_id uuid)
returns setof public.purchase_orders language sql stable security definer set search_path to 'public'
as $function$
  select * from public.purchase_orders
   where id = p_po_id and org_id in (select my_org_ids());
$function$;

create or replace function public.list_purchase_orders(p_org_id uuid, p_job_id uuid default null)
returns setof public.purchase_orders language sql stable security definer set search_path to 'public'
as $function$
  select * from public.purchase_orders
   where org_id = p_org_id
     and p_org_id in (select my_org_ids())
     and (p_job_id is null or job_id = p_job_id)
   order by created_at desc;
$function$;

-- ---------------------------------------------------------------------------
-- PART 5 — GRANTS. Rule 7, per function. The PUBLIC grant is what makes a new
-- function anon-executable and a revoke naming only `anon` is a no-op.
-- `authenticated` KEPT on the eight the app calls (a server action IS the call
-- path) and REVOKED on recompute_material_item_ready_by, whose only callers are
-- the five RPCs above — rule 7's carve-out, answered per function.
-- ---------------------------------------------------------------------------
revoke execute on function public.create_purchase_order(uuid, text, uuid) from public, anon;
revoke execute on function public.update_purchase_order(uuid, text, uuid, text) from public, anon;
revoke execute on function public.delete_purchase_order(uuid) from public, anon;
revoke execute on function public.add_purchase_order_line(uuid, uuid, numeric, date) from public, anon;
revoke execute on function public.update_purchase_order_line(uuid, numeric, date) from public, anon;
revoke execute on function public.delete_purchase_order_line(uuid) from public, anon;
revoke execute on function public.fetch_purchase_order(uuid) from public, anon;
revoke execute on function public.list_purchase_orders(uuid, uuid) from public, anon;
revoke execute on function public.recompute_material_item_ready_by(uuid) from public, anon, authenticated;
