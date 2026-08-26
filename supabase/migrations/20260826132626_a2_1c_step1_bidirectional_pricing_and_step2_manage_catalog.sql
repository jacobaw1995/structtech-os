-- A2.1c Steps 1 & 2 — TWO PRODUCT DECISIONS BY JACOB, 2026-08-26.
-- Applied while `products` is at ZERO ROWS, which is why they are cheap today.
--
-- ===========================================================================
-- STEP 1 · PRICING: enter cost plus EITHER sell OR markup, the other fills in.
--
-- SHAPE CHOSEN: BOTH STORED, DERIVED IN THE RPC — agreeing with the
-- controller's lean, and here is the reasoning rather than just the agreement.
-- THE DIRECTIONALITY PROBLEM WAS NEVER A STORAGE PROBLEM. IT IS AN INPUT
-- PROBLEM. A generated column can only ever run one direction, so putting the
-- derivation in the column forces the input to run that way too. Moving the
-- derivation into the RPC makes input bidirectional and leaves storage alone.
-- That is the same move A2.0 made when a role default came off the read path
-- and onto the write path: put the rule where the intent arrives.
--
-- THE INVARIANT, and it is enforced STRUCTURALLY rather than by convention:
-- a CHECK constraint requires `markup` to be exactly the markup implied by the
-- stored `cost` and `sell`. cost, sell and markup therefore CANNOT be mutually
-- inconsistent in a stored row — not "are kept consistent", cannot be.
--
-- SAID PLAINLY RATHER THAN DRESSED UP: with an exact CHECK, `markup` carries no
-- information independent of cost and sell. It is a materialised convenience,
-- not a second source of truth, and the redundancy is safe precisely BECAUSE
-- the constraint makes disagreement impossible. This is the opposite of the
-- A2.0 failure, where two bodies were free to answer differently.
-- ===========================================================================

-- ALTER COLUMN ... DROP EXPRESSION converts the generated column to an ordinary
-- one IN PLACE. Deliberately not drop-and-re-add: that would move `markup` to
-- the end of the column list, and list_products()/fetch_product() select
-- POSITIONALLY into `setof public.products`. Re-adding it would have silently
-- mis-mapped three money columns — exactly the class of failure A2.1a already
-- cost a migration.
alter table public.products alter column markup drop expression;

alter table public.products add constraint products_markup_matches_prices check (
  markup is not distinct from (
    case when cost is null or sell is null or cost = 0 then null
         else round(((sell - cost) / cost) * 100, 2) end
  )
);

-- ONE authoritative implementation of the rule, called by both write RPCs, so
-- create and update cannot drift apart on how a price is derived.
create or replace function public.derive_catalog_price(
  p_cost numeric,
  p_sell numeric,
  p_markup numeric
)
returns table (out_sell numeric, out_markup numeric)
language plpgsql
immutable
set search_path to 'public'
as $function$
declare v_sell numeric := p_sell; v_implied numeric;
begin
  -- Markup means nothing without a non-zero cost. REFUSE rather than invent a
  -- price — a zero-cost labour line has no markup, and pretending otherwise
  -- would put a fabricated number in front of someone quoting a roof.
  if p_markup is not null and (p_cost is null or p_cost = 0) then
    raise exception 'markup needs a non-zero cost — enter a sell price for this item instead';
  end if;

  if p_sell is not null and p_markup is not null then
    -- BOTH SUPPLIED: they must agree. Never silently prefer one.
    v_implied := round(((p_sell - p_cost) / p_cost) * 100, 2);
    if abs(v_implied - p_markup) > 0.01 then
      raise exception
        'sell and markup disagree: cost % with sell % implies a markup of % percent, not % percent. Send one or the other, or correct them.',
        p_cost, p_sell, v_implied, p_markup;
    end if;
    -- Within a cent they agree; sell wins because sell is the money.
    v_sell := p_sell;
  elsif p_markup is not null then
    v_sell := round(p_cost * (1 + p_markup / 100), 2);
  end if;

  out_sell := v_sell;
  -- NORMALISE: markup is always re-derived from the final cost/sell, so the
  -- stored trio satisfies the CHECK by construction. A user who types 33.333
  -- gets a stored 33.33 and an EXACT sell price, which is the number that
  -- actually goes on the estimate.
  out_markup := case
    when p_cost is null or v_sell is null or p_cost = 0 then null
    else round(((v_sell - p_cost) / p_cost) * 100, 2)
  end;
  return next;
end;
$function$;
revoke execute on function public.derive_catalog_price(numeric,numeric,numeric) from public, anon;

-- ===========================================================================
-- STEP 2 · `manage_catalog`: managers AND office. Jacob's decision — the person
-- who builds estimates maintains the item list, which is plainly right for a
-- real business and was wrong as shipped.
--
-- Mapping, stated precisely because it is a permission: manager tier TRUE,
-- `office` TRUE, and EVERYTHING ELSE FALSE — `field`, `client_portal_viewer`,
-- the legacy `member` role, and any future role added to the CHECK constraint.
-- `member` gets FALSE rather than inheriting the office branch: it is not
-- office, the instruction named office, and an unrecognised role failing closed
-- is A2.0's posture. This is the first key on which `member` and `office`
-- differ, and that is deliberate.
-- ===========================================================================
create or replace function public.default_permissions_for_role(p_role text)
returns jsonb
language sql
immutable
set search_path to 'public'
as $function$
  select case
    when p_role in ('owner', 'admin', 'agency_admin') then jsonb_build_object(
      'view_financials',        true,
      'view_estimates',         true,
      'view_field',             true,
      'add_notes',              true,
      'schedule',               true,
      'view_master_work_order', true,
      'edit_leads',             true,
      'create_estimates',       true,
      'manage_catalog',         true
    )
    when p_role in ('field', 'client_portal_viewer') then jsonb_build_object(
      'view_financials',        false,
      'view_estimates',         false,
      'view_field',             true,
      'add_notes',              true,
      'schedule',               true,
      'view_master_work_order', false,
      'edit_leads',             false,
      'create_estimates',       false,
      'manage_catalog',         false
    )
    when p_role = 'office' then jsonb_build_object(
      'view_financials',        true,
      'view_estimates',         true,
      'view_field',             true,
      'add_notes',              true,
      'schedule',               true,
      'view_master_work_order', true,
      'edit_leads',             false,
      'create_estimates',       false,
      'manage_catalog',         true
    )
    -- `member` and anything future. Identical to the office branch on every key
    -- that existed before today; manage_catalog is the one difference.
    else jsonb_build_object(
      'view_financials',        true,
      'view_estimates',         true,
      'view_field',             true,
      'add_notes',              true,
      'schedule',               true,
      'view_master_work_order', true,
      'edit_leads',             false,
      'create_estimates',       false,
      'manage_catalog',         false
    )
  end;
$function$;
revoke execute on function public.default_permissions_for_role(text) from public, anon;
revoke execute on function public.default_permissions_for_role(text) from authenticated;

-- BACK-FILL so Monday's seeded rows stay consistent with today's default.
-- Without this, `default_permissions_for_role` and the stored rows disagree the
-- moment this migration lands — which is precisely the divergence A2.0 closed,
-- reintroduced by adding a key and forgetting the rows. `where not ... ? key`
-- so an explicitly-set value is never overwritten.
update public.org_members m
   set permissions = m.permissions || jsonb_build_object(
         'manage_catalog',
         (public.default_permissions_for_role(m.role) ->> 'manage_catalog')::boolean)
 where not (m.permissions ? 'manage_catalog');

-- ===========================================================================
-- RE-POINT BOTH LAYERS. The RLS write policies move off is_org_manager() too —
-- leaving them behind would mean an office member's RPC write succeeded while
-- the same write direct to the table was refused, which is the two-answers
-- shape this stage exists to stop.
-- ===========================================================================
drop policy "manager insert own products" on public.products;
drop policy "manager update own products" on public.products;
drop policy "manager delete own products" on public.products;

create policy "catalog manager insert own products" on public.products for insert to authenticated
  with check (org_id in (select my_org_ids()) and has_capability(org_id, 'manage_catalog'));
create policy "catalog manager update own products" on public.products for update to authenticated
  using (org_id in (select my_org_ids()) and has_capability(org_id, 'manage_catalog'))
  with check (org_id in (select my_org_ids()) and has_capability(org_id, 'manage_catalog'));
create policy "catalog manager delete own products" on public.products for delete to authenticated
  using (org_id in (select my_org_ids()) and has_capability(org_id, 'manage_catalog'));

-- ===========================================================================
-- RPCs.
-- create_product gains p_markup, which CHANGES THE SIGNATURE, so the exact old
-- one is DROPPED FIRST — migration rule 1: CREATE OR REPLACE with a changed
-- signature makes an OVERLOAD, not a replacement. The identity argument list
-- below is copied verbatim from pg_get_function_identity_arguments(), never
-- retyped (rule 2: DROP ... IF EXISTS with a mistyped signature silently
-- succeeds and drops nothing).
-- ===========================================================================
drop function public.create_product(p_org_id uuid, p_name text, p_category text, p_unit text, p_cost numeric, p_sell numeric);

create or replace function public.create_product(
  p_org_id uuid,
  p_name text,
  p_category text default null,
  p_unit text default null,
  p_cost numeric default null,
  p_sell numeric default null,
  p_markup numeric default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_id uuid; v_sell numeric; v_markup numeric;
begin
  if p_org_id is null or p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of that org';
  end if;
  if not coalesce(public.has_capability(p_org_id, 'manage_catalog'), false) then
    raise exception 'you do not have permission to change the catalog';
  end if;
  if (p_cost is not null or p_sell is not null or p_markup is not null)
     and not coalesce(public.can_view_financials(p_org_id), false) then
    raise exception 'not permitted to set catalog cost, sell or markup';
  end if;

  select out_sell, out_markup into v_sell, v_markup
  from public.derive_catalog_price(p_cost, p_sell, p_markup);

  insert into public.products (org_id, name, category, unit, cost, sell, markup, created_by)
  values (p_org_id, btrim(p_name),
          nullif(btrim(coalesce(p_category, '')), ''),
          nullif(btrim(coalesce(p_unit, '')), ''),
          p_cost, v_sell, v_markup, auth.uid())
  returning id into v_id;

  return v_id;
end;
$function$;
revoke execute on function public.create_product(uuid,text,text,text,numeric,numeric,numeric) from public, anon;

create or replace function public.update_product(p_product_id uuid, p_patch jsonb)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_row public.products;
  v_key text;
  v_cost numeric; v_sell_in numeric; v_markup_in numeric;
  v_sell numeric; v_markup numeric;
begin
  select * into v_row from public.products where id = p_product_id;
  if v_row.id is null then raise exception 'catalog item not found'; end if;
  if v_row.org_id not in (select my_org_ids()) then raise exception 'not a member of that org'; end if;
  if not coalesce(public.has_capability(v_row.org_id, 'manage_catalog'), false) then
    raise exception 'you do not have permission to change the catalog';
  end if;

  for v_key in select jsonb_object_keys(coalesce(p_patch, '{}'::jsonb)) loop
    if v_key not in ('name','category','unit','cost','sell','markup','active') then
      raise exception 'unknown catalog field: %', v_key;
    end if;
  end loop;

  if (p_patch ? 'cost' or p_patch ? 'sell' or p_patch ? 'markup')
     and not coalesce(public.can_view_financials(v_row.org_id), false) then
    raise exception 'not permitted to set catalog cost, sell or markup';
  end if;

  v_cost := case when p_patch ? 'cost' then (p_patch->>'cost')::numeric else v_row.cost end;

  if (p_patch ? 'markup') and not (p_patch ? 'sell') then
    -- markup alone: derive sell from it and IGNORE the stored sell, which is
    -- what the old value now contradicts.
    v_sell_in := null;
    v_markup_in := (p_patch->>'markup')::numeric;
  else
    v_sell_in := case when p_patch ? 'sell' then (p_patch->>'sell')::numeric else v_row.sell end;
    -- markup only counts as "supplied" when sell was supplied too, so that a
    -- cost-only edit re-derives markup instead of being refused against a stale
    -- stored value.
    v_markup_in := case when (p_patch ? 'sell') and (p_patch ? 'markup')
                        then (p_patch->>'markup')::numeric else null end;
  end if;

  select out_sell, out_markup into v_sell, v_markup
  from public.derive_catalog_price(v_cost, v_sell_in, v_markup_in);

  update public.products set
    name     = case when p_patch ? 'name'
                    then coalesce(nullif(btrim(p_patch->>'name'), ''), name) else name end,
    category = case when p_patch ? 'category' then nullif(btrim(coalesce(p_patch->>'category','')), '') else category end,
    unit     = case when p_patch ? 'unit'     then nullif(btrim(coalesce(p_patch->>'unit','')), '')     else unit end,
    cost     = v_cost,
    sell     = v_sell,
    markup   = v_markup,
    active   = case when p_patch ? 'active'   then (p_patch->>'active')::boolean else active end
  where id = p_product_id;
end;
$function$;
revoke execute on function public.update_product(uuid,jsonb) from public, anon;

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
  if not coalesce(public.has_capability(v_org, 'manage_catalog'), false) then
    raise exception 'you do not have permission to change the catalog';
  end if;

  select count(*) into v_refs from public.estimate_line_items where product_id = p_product_id;
  if v_refs > 0 then
    raise exception 'Cannot delete: % estimate line item(s) still reference this catalog item. Archive it instead.', v_refs;
  end if;

  delete from public.products where id = p_product_id;
end;
$function$;
revoke execute on function public.delete_product(uuid) from public, anon;