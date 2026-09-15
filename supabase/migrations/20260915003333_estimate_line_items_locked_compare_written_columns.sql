-- CORRECTIVE to estimate_line_items_locked_at_the_table, same session. Track S · 2026-09-14.
-- The "a write that changes nothing is not gated" branch compared row(new.*) to row(old.*). In a
-- BEFORE trigger a GENERATED column is not yet computed, so NEW.line_total (quantity * unit_price,
-- GENERATED ALWAYS) is NULL while OLD.line_total is not — every row differed, and an unchanged
-- re-send onto a signed line was REFUSED. Found by the rule-8 control in the after-probe, before
-- anything depended on it.
-- Now compares every column a writer can set, excluding line_total (generated) and updated_at
-- (bookkeeping — touching it records nothing a signer agreed to).

create or replace function public.estimate_line_items_locked()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
declare v_status text; v_old_status text;
begin
  if tg_op = 'DELETE' then
    select status into v_status from public.estimates where id = old.estimate_id;
    if v_status in ('signed', 'void') then
      raise exception 'estimate % is locked (status: %) — its line items cannot be deleted', old.estimate_id, v_status;
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE'
     and (new.id, new.org_id, new.estimate_id, new.product_id, new.description, new.quantity, new.unit_price,
          new.sort_order, new.created_at, new.unit, new.scope_key)
         is not distinct from
         (old.id, old.org_id, old.estimate_id, old.product_id, old.description, old.quantity, old.unit_price,
          old.sort_order, old.created_at, old.unit, old.scope_key) then
    return new;
  end if;

  select status into v_status from public.estimates where id = new.estimate_id;
  if tg_op = 'UPDATE' and new.estimate_id is distinct from old.estimate_id then
    select status into v_old_status from public.estimates where id = old.estimate_id;
  end if;

  if v_status in ('signed', 'void') or v_old_status in ('signed', 'void') then
    raise exception 'estimate % is locked (status: %) — line items can only change before signing',
      case when v_status in ('signed', 'void') then new.estimate_id else old.estimate_id end,
      coalesce(case when v_status in ('signed', 'void') then v_status end, v_old_status);
  end if;
  return new;
end;
$function$;

revoke execute on function public.estimate_line_items_locked() from public, anon, authenticated;