-- A2.1 — TENANT PRODUCT CATALOG.
--
-- The join point is NOT new work and was not rebuilt: estimate_line_items.product_id
-- is live and add_estimate_line_item already takes p_product_id uuid. What did not
-- exist is the tenant-owned table those columns point at. The only product-shaped
-- tables here are wh_*, which belong to Material Matrix — not a template, not
-- extended, not referenced.
--
-- PER-ORG, NO SHARED TIER. Every row carries org_id NOT NULL and is owned by
-- exactly one tenant. This is a CONTROLLER DECISION flagged for confirmation, not
-- a schema detail: §5.2 says "tenant-owned ... including items MM does not carry",
-- and CLAUDE.md's North Star says org isolation is the default but a controlled
-- cross-tenant published supplier catalog must not be PRECLUDED. Building a shared
-- tier today would be speculative; the shape chosen keeps it additive — a later
-- `published boolean` plus a widened SELECT predicate needs no data migration and
-- no change to any row's ownership. Nothing shared is built.

create table public.products (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  category text,
  unit text,
  cost numeric(12,2),
  sell numeric(12,2),
  -- GENERATED, not stored independently. §5.2 lists cost, sell AND markup, and
  -- storing all three invites exactly the failure A2.0 spent a day closing: two
  -- places holding one fact, free to disagree. cost and sell are the source of
  -- truth; markup is derived and cannot contradict them. Consequence stated
  -- rather than buried: this means "enter a markup, get a sell price" is not
  -- available. If that is the workflow Isaac wants, it is a controller decision
  -- and the column flips to stored-with-a-trigger, not something to discover in
  -- the UI later.
  markup numeric(8,2) generated always as (
    case when cost is null or sell is null or cost = 0 then null
         else round(((sell - cost) / cost) * 100, 2) end
  ) stored,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  constraint products_name_not_blank check (btrim(name) <> '')
);

-- Deliberately NO unique constraint on (org_id, name). Two catalog items can
-- legitimately share a name (same product, two suppliers), and §6.6's org-identity
-- entry records the rule this follows: do not settle a product question inside a
-- schema as if it were a guard.
create index products_org_active_idx on public.products (org_id, active);

-- The join point, now actually enforced. Safe as a plain ADD CONSTRAINT because
-- all 21 existing estimate_line_items rows carry product_id IS NULL (measured,
-- not assumed). ON DELETE SET NULL so a historical estimate line survives its
-- catalog item being removed — the line keeps its own description, quantity and
-- unit_price, which are snapshotted on the line, not read through the join.
alter table public.estimate_line_items
  add constraint estimate_line_items_product_id_fkey
  foreign key (product_id) references public.products(id) on delete set null;

alter table public.products enable row level security;
grant select, insert, update, delete on table public.products to authenticated;

-- EVERY POLICY IS SCOPED `TO authenticated`, which departs from the house style
-- of leaving them `TO public`. That is deliberate and it is the 2026-08-20
-- incident's lesson applied rather than restated: a policy left `TO public` whose
-- expression calls a security-definer helper has to be EVALUATED for anon, and
-- that is exactly what took the Material Matrix storefront down. The RESTRICTIVE
-- policy below is `FOR ALL` and calls can_view_financials() — precisely the shape
-- that broke. anon holds no grant on this table and no permissive policy, so it
-- reaches nothing either way.
create policy "member read own products" on public.products for select to authenticated
  using (org_id in (select my_org_ids()));

-- Writes require manager tier. NOT a new capability key: adding one would mean
-- re-seeding every org_members.permissions row one day after A2.0 established
-- that vocabulary, for no access gained here. A per-capability catalog permission
-- (so an `office` member can maintain the catalog) is a real follow-up and is
-- filed, not built.
create policy "manager insert own products" on public.products for insert to authenticated
  with check (org_id in (select my_org_ids()) and is_org_manager(org_id));
create policy "manager update own products" on public.products for update to authenticated
  using (org_id in (select my_org_ids()) and is_org_manager(org_id))
  with check (org_id in (select my_org_ids()) and is_org_manager(org_id));
create policy "manager delete own products" on public.products for delete to authenticated
  using (org_id in (select my_org_ids()) and is_org_manager(org_id));

-- LAYER ONE of the crew gate. Same name and same shape as A1.5's policies on
-- deals/estimates/estimate_line_items, so the class is greppable as one thing.
-- RESTRICTIVE because permissive policies OR together — a permissive one here
-- would gate nothing, which is the trap A1.5 recorded.
create policy "no dollars in the field - products" on public.products
  as restrictive for all to authenticated
  using (can_view_financials(org_id))
  with check (can_view_financials(org_id));

create or replace function public.products_touch_updated_at()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;
revoke execute on function public.products_touch_updated_at() from public, anon;

create trigger products_touch_updated_at
  before update on public.products
  for each row execute function public.products_touch_updated_at();

-- ---------------------------------------------------------------------------
-- RPCs. LAYER TWO of the crew gate.
--
-- SECURITY DEFINER BYPASSES RLS, so every one of these re-states the org check
-- itself and the read paths re-state the money gate. That is A1.5's lesson and
-- the controller's instruction: the RESTRICTIVE policy alone would be a gate with
-- a documented way around it.
--
-- Every one gates money on can_view_financials(), never on has_capability()
-- directly. After A2.0 the former IS a thin wrapper over the latter, so this is
-- about which NAME the code depends on — the closed-default name is the one that
-- reads correctly to whoever maintains this next.
-- ---------------------------------------------------------------------------
create or replace function public.create_product(
  p_org_id uuid,
  p_name text,
  p_category text default null,
  p_unit text default null,
  p_cost numeric default null,
  p_sell numeric default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_id uuid;
begin
  if p_org_id is null or p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of that org';
  end if;
  -- coalesce per CLAUDE.md migration rule 5: PL/pgSQL treats a NULL IF condition
  -- as FALSE, so `if not (...)` on a nullable expression silently ALLOWS.
  if not coalesce(public.is_org_manager(p_org_id), false) then
    raise exception 'only an owner, admin or agency admin can change the catalog';
  end if;
  if (p_cost is not null or p_sell is not null)
     and not coalesce(public.can_view_financials(p_org_id), false) then
    raise exception 'not permitted to set catalog cost or sell';
  end if;

  insert into public.products (org_id, name, category, unit, cost, sell, created_by)
  values (p_org_id, btrim(p_name),
          nullif(btrim(coalesce(p_category, '')), ''),
          nullif(btrim(coalesce(p_unit, '')), ''),
          p_cost, p_sell, auth.uid())
  returning id into v_id;

  return v_id;
end;
$function$;
revoke execute on function public.create_product(uuid,text,text,text,numeric,numeric) from public, anon;

-- jsonb patch, mirroring update_deal_fields (§4.3 — extend the shipped pattern).
-- Unknown keys are REFUSED rather than ignored, so a typo is an error instead of
-- a silent no-op.
create or replace function public.update_product(p_product_id uuid, p_patch jsonb)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_org uuid; v_key text;
begin
  select org_id into v_org from public.products where id = p_product_id;
  if v_org is null then raise exception 'catalog item not found'; end if;
  if v_org not in (select my_org_ids()) then raise exception 'not a member of that org'; end if;
  if not coalesce(public.is_org_manager(v_org), false) then
    raise exception 'only an owner, admin or agency admin can change the catalog';
  end if;

  for v_key in select jsonb_object_keys(coalesce(p_patch, '{}'::jsonb)) loop
    if v_key not in ('name','category','unit','cost','sell','active') then
      raise exception 'unknown catalog field: %', v_key;
    end if;
  end loop;

  if (p_patch ? 'cost' or p_patch ? 'sell')
     and not coalesce(public.can_view_financials(v_org), false) then
    raise exception 'not permitted to set catalog cost or sell';
  end if;

  update public.products set
    name     = case when p_patch ? 'name'
                    then coalesce(nullif(btrim(p_patch->>'name'), ''), name) else name end,
    category = case when p_patch ? 'category' then nullif(btrim(coalesce(p_patch->>'category','')), '') else category end,
    unit     = case when p_patch ? 'unit'     then nullif(btrim(coalesce(p_patch->>'unit','')), '')     else unit end,
    cost     = case when p_patch ? 'cost'     then (p_patch->>'cost')::numeric   else cost end,
    sell     = case when p_patch ? 'sell'     then (p_patch->>'sell')::numeric   else sell end,
    active   = case when p_patch ? 'active'   then (p_patch->>'active')::boolean else active end
  where id = p_product_id;
end;
$function$;
revoke execute on function public.update_product(uuid,jsonb) from public, anon;

-- REFUSE AND NAME THE COUNT — A1.4's precedent, not a cascade. Archiving
-- (active=false) is the non-destructive path and the UI offers both.
create or replace function public.delete_product(p_product_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_org uuid; v_refs integer;
begin
  select org_id into v_org from public.products where id = p_product_id;
  if v_org is null then raise exception 'catalog item not found'; end if;
  if v_org not in (select my_org_ids()) then raise exception 'not a member of that org'; end if;
  if not coalesce(public.is_org_manager(v_org), false) then
    raise exception 'only an owner, admin or agency admin can change the catalog';
  end if;

  select count(*) into v_refs from public.estimate_line_items where product_id = p_product_id;
  if v_refs > 0 then
    raise exception 'Cannot delete: % estimate line item(s) still reference this catalog item. Archive it instead.', v_refs;
  end if;

  delete from public.products where id = p_product_id;
end;
$function$;
revoke execute on function public.delete_product(uuid) from public, anon;

create or replace function public.list_products(p_org_id uuid, p_include_inactive boolean default false)
returns setof public.products
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare v_fin boolean;
begin
  if p_org_id is null or p_org_id not in (select my_org_ids()) then
    return;
  end if;
  v_fin := coalesce(public.can_view_financials(p_org_id), false);
  return query
    select p.id, p.org_id, p.name, p.category, p.unit,
           case when v_fin then p.cost   else null end,
           case when v_fin then p.sell   else null end,
           case when v_fin then p.markup else null end,
           p.active, p.created_at, p.updated_at, p.created_by
    from public.products p
    where p.org_id = p_org_id
      and (p_include_inactive or p.active)
    order by p.active desc, lower(p.name);
end;
$function$;
revoke execute on function public.list_products(uuid,boolean) from public, anon;

-- Single-record fetch through an RPC per CLAUDE.md rule 4.
create or replace function public.fetch_product(p_product_id uuid)
returns setof public.products
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare v_org uuid; v_fin boolean;
begin
  select org_id into v_org from public.products where id = p_product_id;
  if v_org is null or v_org not in (select my_org_ids()) then
    return;
  end if;
  v_fin := coalesce(public.can_view_financials(v_org), false);
  return query
    select p.id, p.org_id, p.name, p.category, p.unit,
           case when v_fin then p.cost   else null end,
           case when v_fin then p.sell   else null end,
           case when v_fin then p.markup else null end,
           p.active, p.created_at, p.updated_at, p.created_by
    from public.products p
    where p.id = p_product_id;
end;
$function$;
revoke execute on function public.fetch_product(uuid) from public, anon;