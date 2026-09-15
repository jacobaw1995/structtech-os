-- A SIGNED OR VOID ESTIMATE'S LINES ARE LOCKED AT THE TABLE. Track S · 2026-09-14.
--
-- Found 2026-09-14 while building the take-off, not fixed then; fixed now. Every RPC that writes
-- estimate_line_items (add, update, delete, reorder, upsert_estimate_scope_line_items) refuses a
-- signed or void estimate. The TABLE did not: "member update own estimate_line_items" (and the
-- insert/delete policies) test org and view_estimates, never status.
--
-- PROVED BEFORE THIS RAN (rolled back), as `authenticated` with the BMR owner's JWT on the signed
-- Fake Lead estimate: a direct UPDATE set quantity 99 / unit_price 1 on a signed line — SAVED;
-- a direct INSERT added a $500 line to the signed estimate — SAVED; a direct DELETE removed it —
-- SAVED. A signed quote could be rewritten after the homeowner signed it.
--
-- THE LOCK IS A TRIGGER, NOT A POLICY, so it holds for every writer — a policy binds only RLS-subject
-- roles, and the definer RPCs and any future definer path would walk past it. SECURITY DEFINER so it
-- always reads the parent's status, whatever the writer can see.
--   · INSERT onto a locked estimate: refused.
--   · UPDATE of a line on a locked estimate (or moving a line onto one): refused — unless the write
--     CHANGES NOTHING (§7.1 RULE 8: presence is not a change; a re-send passes).
--   · DELETE of a line on a locked estimate: refused while the estimate still exists. When the
--     estimate itself is being deleted, its row is already gone when the cascade reaches the lines,
--     so the cascade passes. (delete_estimate refuses a signed estimate on its own.)
-- Rollback: drop trigger estimate_line_items_locked on public.estimate_line_items; drop function
-- public.estimate_line_items_locked().

create function public.estimate_line_items_locked()
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

  if tg_op = 'UPDATE' and row(new.*) is not distinct from row(old.*) then
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

create trigger estimate_line_items_locked
  before insert or update or delete on public.estimate_line_items
  for each row execute function public.estimate_line_items_locked();

revoke execute on function public.estimate_line_items_locked() from public, anon, authenticated;