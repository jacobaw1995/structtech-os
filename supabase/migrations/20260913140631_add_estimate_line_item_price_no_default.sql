-- RULING (c), 2026-09-12, Jacob: `add_estimate_line_item p_unit_price DEFAULT 0` — THE
-- DEFAULT GOES. Zero stays a LEGAL typed value; it stops being an ASSUMED one. NO CHECK
-- CONSTRAINT: free lines are real, and a constraint is the wrong instrument.
-- Track S · 2026-09-13. Rollback: supabase/rollbacks/20260913_estimate_line_price_no_default_rollback.sql
--
-- PROVED BEFORE THIS RAN, as `authenticated` with the BMR owner's JWT on a draft estimate
-- in a rolled-back transaction: add_estimate_line_item with the price OMITTED saved
-- unit_price = 0; a DIRECT INSERT (RLS "member insert own estimate_line_items" permits it)
-- omitting the price saved unit_price = 0 via the COLUMN default. Two doors, one answer.
--
-- CALLING SURFACES, enumerated on the merged tree at main eacaf48 and in pg_proc:
--   src/lib/estimating/actions.ts:273 addEstimateDocumentLineItem — the ONLY app caller.
--     Fed by src/components/estimating/LineItemsEditor.tsx:
--       :133 handleAdd            sends unit_price "0" EXPLICITLY (blank row)
--       :149 handleAddFromCatalog sends String(product.sell ?? 0) EXPLICITLY
--     NEITHER relies on this default, so this narrowing breaks neither. BOTH SUBSTITUTE A
--     ZERO THEMSELVES — the same silent answer, already living in the UI, and for a member
--     without view_financials list_products() nulls sell, so every catalog pick is $0.
--     These are Track U surfaces: reported, not fixed from here. This migration does not
--     change what the live UI stores.
--   No database function calls add_estimate_line_item.
--   upsert_estimate_scope_line_items inserts a LITERAL 0 for unit_price — not this default,
--     unaffected, same class, not ruled.
--
-- BEFORE-MEASUREMENT (live, 2026-09-13): estimate_line_items holds 21 rows (all Brothers
-- Metal Roofing; 20 on signed estimates, 1 on a void one). unit_price = 0: 0 of 21.
-- ON EXISTING ROWS A TYPED ZERO CANNOT BE DISTINGUISHED FROM AN OMITTED ZERO. That is the
-- finding and it is UNANSWERABLE RETROACTIVELY: the table records the value, not whether a
-- human chose it, and no audit column or activity row records the input. Today's count is
-- 0, so no row carries the ambiguity — but that is a fact about these 21 rows, not a
-- property of the table. No interpretation is backfilled onto any row.
--
-- THE MECHANICS. Postgres requires every parameter after one with a default to have a
-- default (p_quantity DEFAULT 1 precedes this one; three follow it). So "the default goes"
-- is implemented as DEFAULT NULL plus a refusal in words when the price is absent: an
-- omission can no longer produce a value. A default cannot be changed by CREATE OR
-- REPLACE, so the exact signature is dropped first (rule 1, copied per rule 2).
-- The COLUMN default goes too, so a direct INSERT omitting the price hits NOT NULL — a
-- constraint preventing an assumed value, not a CHECK on the value. 0 remains insertable.
-- NOT CHANGED, SAME CLASS, NOT RULED: p_quantity DEFAULT 1 and the quantity column DEFAULT 1.

drop function if exists public.add_estimate_line_item(uuid, text, numeric, numeric, uuid, integer, text);

create function public.add_estimate_line_item(
  p_estimate_id uuid, p_description text,
  p_quantity numeric default 1, p_unit_price numeric default null,
  p_product_id uuid default null, p_sort_order integer default 0, p_unit text default null
)
returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_status text;
  v_line_id uuid;
  v_product_org uuid;
begin
  select org_id, status into v_org_id, v_status
  from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  if v_status in ('signed', 'void') then
    raise exception 'estimate % is locked (status: %) — line items can only change before signing', p_estimate_id, v_status;
  end if;

  -- A price is an answer only the user can give. 0 is a legal answer (a free line);
  -- no answer is not 0.
  if p_unit_price is null then
    raise exception 'enter a unit price for this line — 0 is allowed for a free line, but it has to be entered';
  end if;

  -- The catalog item must belong to the SAME org as the estimate. Not merely
  -- "an org I am a member of": an agency_admin belongs to several, and pricing
  -- one tenant's roof from another tenant's catalog is wrong even when the
  -- caller can legitimately see both.
  if p_product_id is not null then
    select org_id into v_product_org from public.products where id = p_product_id;
    if v_product_org is null then
      raise exception 'catalog item not found: %', p_product_id;
    end if;
    if v_product_org <> v_org_id then
      raise exception 'that catalog item belongs to a different tenant and cannot price this estimate';
    end if;
  end if;

  insert into public.estimate_line_items
    (org_id, estimate_id, product_id, description, quantity, unit_price, sort_order, unit)
  values
    (v_org_id, p_estimate_id, p_product_id, p_description, p_quantity, p_unit_price, p_sort_order, p_unit)
  returning id into v_line_id;

  return v_line_id;
end;
$function$;

revoke execute on function public.add_estimate_line_item(uuid, text, numeric, numeric, uuid, integer, text) from public, anon;

alter table public.estimate_line_items alter column unit_price drop default;

-- Rule 3: never trust the success response.
do $$
begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'add_estimate_line_item') <> 1
    then raise exception 'add_estimate_line_item has more than one overload'; end if;
  if (select pg_get_function_arguments(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'add_estimate_line_item') !~ 'p_unit_price numeric DEFAULT NULL'
    then raise exception 'p_unit_price still substitutes a value'; end if;
  if (select column_default from information_schema.columns
      where table_schema = 'public' and table_name = 'estimate_line_items' and column_name = 'unit_price') is not null
    then raise exception 'estimate_line_items.unit_price still has a column default'; end if;
end $$;