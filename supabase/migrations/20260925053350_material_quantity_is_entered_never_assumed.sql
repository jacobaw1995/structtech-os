-- A QUANTITY IS ENTERED, NEVER ASSUMED — add_material_item.
-- Controller ruling, Jacob, 2026-09-25, on Track U's residual from U-W1.32:
-- "REMOVING A DEFAULT DOES NOT MAKE A VALUE ILLEGAL; IT MAKES IT DELIBERATE."
--
-- THE DEFECT, measured 2026-09-23 by U and re-measured here before changing
-- anything. TWO invisible 1s, one behind the other:
--   · add_material_item declared `p_quantity numeric DEFAULT 1`
--   · material_items.quantity is NOT NULL DEFAULT 1
-- and NO refusal existed on either. The one app caller is
-- src/lib/coordination/actions.ts addMaterialItem, which sends
-- optionalNumber(formData,'quantity') — and optionalString returns undefined for
-- an EMPTY STRING, so an empty Qty box OMITS the argument and the RPC writes 1
-- with nobody told. U closed the form (`required`, no defaultValue) and reported
-- the RPC as ours. A submit that bypasses the browser check still landed on the 1.
--
-- CALLERS, NAMED FIRST as instructed. Exactly one, outside and inside:
--   · app:      src/lib/coordination/actions.ts → addMaterialItem (the only rpc call)
--   · database: NONE. No function body references add_material_item
--               (`select proname from pg_proc where prosrc ~ 'add_material_item'`
--               returns only itself). materialize_take_off inserts into
--               material_items DIRECTLY and NAMES quantity, so the column default
--               was never its path and dropping it cannot reach the take-off.
--
-- THE PO-LINE TREATMENT IS `DEFAULT NULL`, NOT "NO DEFAULT" — and this is a
-- correction to the instruction, made because the literal reading is worse than
-- the thing it was told to copy. add_purchase_order_line, the model, declares
-- `p_quantity_ordered numeric DEFAULT NULL::numeric` and refuses NULL by name.
-- With NO default at all, an omitted argument never enters the function: the
-- database answers 42883 undefined_function, and PostgREST answers PGRST202
-- "could not find the function … in the schema cache". Neither carries a
-- sentence, neither can carry a HINT, and no refusal we write is reachable.
-- Proved in a rolled-back transaction before this file was applied: with the
-- default removed, add_material_item(p_work_order_id=>…, p_name=>…) raised
-- `42883 function public.add_material_item(p_work_order_id => unknown, p_name => unknown)
-- does not exist`, whose hint is PostgreSQL's own generic "add explicit type
-- casts" — while the identical call with an EXPLICIT null reached the named
-- refusal. `DEFAULT NULL` keeps the argument omissible and makes the omission
-- ARRIVE somewhere that can name it. That is what makes the value deliberate:
-- NULL is not a value, it is the absence of one, and the absence now has a
-- sentence.
--
-- THE COLUMN DEFAULT IS DROPPED, unambiguously. It is the second, invisible 1,
-- and nothing legitimate reaches it: only an INSERT that omits the column can,
-- and after this migration the only such path is refused before the insert.
--
-- Identity signature copied verbatim from pg_get_function_identity_arguments
-- (rule 2, never retyped), and DROPped rather than REPLACEd because PostgreSQL
-- refuses to remove a parameter default through CREATE OR REPLACE
-- ("cannot remove parameter defaults from existing function"). A DROP+CREATE
-- resets proacl to the PUBLIC default, so the revoke at the bottom is not
-- ceremony — without it this function is anon-executable the moment it exists
-- (rule 7). `authenticated` is KEPT: the server action is the call path
-- (rule 7's carve-out, answered per function — the answer here is yes,
-- something outside the database calls this).

drop function if exists public.add_material_item(p_work_order_id uuid, p_name text, p_quantity numeric, p_ready_by date, p_sort_order integer);

create function public.add_material_item(
  p_work_order_id uuid,
  p_name text,
  p_quantity numeric default null::numeric,
  p_ready_by date default null::date,
  p_sort_order integer default 0
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_master_id uuid;
  v_sign_off_at timestamptz;
  v_trade text;
  v_item_id uuid;
  v_actor_id uuid;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');

  -- 2026-09-25 — THE QUANTITY IS THE USER'S OR IT IS REFUSED. Both refusals are
  -- named, and both fire AFTER the work-order check so a stranger learns nothing
  -- about a work order from a validation message.
  if p_quantity is null then
    raise exception 'enter a quantity for this material — a crew cannot be sent to a roof with an unknown count'
      using hint = 'material_quantity_required';
  end if;
  if p_quantity <= 0 then
    raise exception 'quantity must be greater than zero'
      using hint = 'material_quantity_not_positive';
  end if;

  select w.trade into v_trade from public.work_orders w where w.id = p_work_order_id;
  select s.master_id, s.sign_off_at into v_master_id, v_sign_off_at
  from public.job_master_sign_off(p_work_order_id) s;

  insert into public.material_items (org_id, work_order_id, name, quantity, ready_by, sort_order)
  values (v_org_id, p_work_order_id, p_name, p_quantity, p_ready_by, p_sort_order)
  returning id into v_item_id;

  if v_sign_off_at is not null then
    select id into v_actor_id from public.profiles where id = auth.uid();
    insert into public.work_order_activity (work_order_id, org_id, action, to_value, actor_id)
    values (v_master_id, v_org_id, 'material_added_after_signoff',
            format('%s (%s)', p_name, coalesce(v_trade, 'trade')), v_actor_id);
  end if;

  return v_item_id;
end;
$function$;

revoke execute on function public.add_material_item(p_work_order_id uuid, p_name text, p_quantity numeric, p_ready_by date, p_sort_order integer) from public, anon;
grant execute on function public.add_material_item(p_work_order_id uuid, p_name text, p_quantity numeric, p_ready_by date, p_sort_order integer) to authenticated;

alter table public.material_items alter column quantity drop default;
