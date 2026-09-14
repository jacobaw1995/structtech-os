-- RULING 3(b), 2026-09-14, Jacob: estimate line QUANTITY still defaults to 1; Friday's ruling
-- covered price only. EXTEND IT. Same order: callers named, before-measurement, then narrow.
-- Track S · 2026-09-14. Rollback: supabase/rollbacks/20260914_estimate_line_quantity_no_default_rollback.sql
--
-- CALLERS, enumerated on main and in pg_proc:
--   src/lib/estimating/actions.ts:276 addEstimateDocumentLineItem — the ONLY app caller of
--     add_estimate_line_item. Fed by src/components/estimating/LineItemsEditor.tsx:
--       handleAdd (blank row) sends quantity "1" EXPLICITLY
--       handleAddFromCatalog sends quantity "1" EXPLICITLY
--     NEITHER relies on this default, so this narrowing breaks neither — and BOTH substitute
--     a 1 themselves: the same silent answer, living in a Track U surface. Reported, not fixed.
--   No database function calls add_estimate_line_item.
--   upsert_estimate_scope_line_items names quantity from its items; it does not rely on the
--     column default and is not changed here.
--
-- BEFORE-MEASUREMENT (live, 2026-09-14): 21 estimate lines on 4 estimates; quantity = 1 on 15
-- (14 of 20 on signed estimates, 1 of 1 on the void one); quantity = 0 on 0.
-- PROVED before this ran (authenticated, BMR owner JWT, rolled back): add_estimate_line_item
-- with the quantity OMITTED saved 1; a DIRECT INSERT omitting it saved 1 via the column default.
-- ON EXISTING ROWS A TYPED 1 CANNOT BE DISTINGUISHED FROM AN OMITTED 1. That is UNANSWERABLE
-- RETROACTIVELY and is recorded as such; no interpretation is backfilled onto the 15 rows.
--
-- MECHANICS, same as 20260913140631: parameters after a defaulted one must have defaults, so
-- "the default goes" is DEFAULT NULL plus a refusal in words; the exact signature is dropped
-- first (rule 1); the COLUMN default is dropped so a direct insert omitting it hits NOT NULL.
-- Zero stays legal. No CHECK constraint.

drop function if exists public.add_estimate_line_item(uuid, text, numeric, numeric, uuid, integer, text);

create function public.add_estimate_line_item(
  p_estimate_id uuid, p_description text,
  p_quantity numeric default null, p_unit_price numeric default null,
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

  -- A quantity and a price are answers only the user can give. 0 is a legal answer;
  -- no answer is not 1 and not 0.
  if p_quantity is null then
    raise exception 'enter a quantity for this line — it has to be entered, not assumed';
  end if;

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

alter table public.estimate_line_items alter column quantity drop default;

-- Rule 3: never trust the success response.
do $$
begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'add_estimate_line_item') <> 1
    then raise exception 'add_estimate_line_item has more than one overload'; end if;
  if (select pg_get_function_arguments(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'add_estimate_line_item') !~ 'p_quantity numeric DEFAULT NULL'
    then raise exception 'p_quantity still substitutes a value'; end if;
  if (select column_default from information_schema.columns
      where table_schema = 'public' and table_name = 'estimate_line_items' and column_name = 'quantity') is not null
    then raise exception 'estimate_line_items.quantity still has a column default'; end if;
end $$;