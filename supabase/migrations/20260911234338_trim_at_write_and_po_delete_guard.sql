-- Track S · 2026-09-11. Two things, both measured before being changed.
-- Rollback: supabase/rollbacks/20260911_trim_at_write_and_po_delete_guard_rollback.sql
--
-- ===========================================================================
-- (1) TRIM AT THE WRITE, NOT ON DISPLAY.
--
-- The first live material item is `"Ag panel: 26 ga black replacement. "` —
-- a sentence copied verbatim out of an estimate line, trailing space, no unit.
-- Trimming on DISPLAY is a proxy: the PDF, a supplier email and a screen reader
-- all still receive the raw value. So it is fixed where the value is stored.
--
-- WHAT COPIES TEXT, measured rather than assumed: `generate_take_off` selects
-- `e.description` into `material_items.name` and `e.unit` into
-- `material_items.unit`. Those are the only machine-to-machine text copies into
-- this table; `add_material_item`/`update_material_item` take typed text, which
-- deserves the same treatment.
--
-- WHY A TRIGGER AND NOT AN EDIT INSIDE generate_take_off — stated because it
-- departs from the literal wording of the ruling:
--   · "At the write" is satisfied more completely here. A trigger covers EVERY
--     writer — the take-off, the hand-add, the hand-edit, and any future path —
--     where editing the take-off covers one.
--   · generate_take_off is ~100 lines and would have to be reproduced whole to
--     change two expressions. CLAUDE.md rule 2 exists because hand-transcribing
--     a definition is how a signature gets silently mangled; the same risk
--     applies to a body.
-- If the trim should ALSO be visible inside generate_take_off's own SQL, that is
-- a follow-up edit, not a correction of this one.
--
-- `nullif(btrim(...),'')` on unit, so a whitespace-only unit becomes NULL
-- rather than an empty string that renders as a gap.
-- ===========================================================================
create function public.material_items_trim_text()
returns trigger language plpgsql set search_path to 'public'
as $function$
begin
  new.name := btrim(new.name);
  new.unit := nullif(btrim(new.unit), '');
  return new;
end;
$function$;

create trigger material_items_trim_text
  before insert or update of name, unit on public.material_items
  for each row execute function public.material_items_trim_text();

comment on function public.material_items_trim_text() is
  'Trims material_items.name and nullifs a whitespace-only unit AT THE WRITE, for every writer — the
   take-off copies estimate text verbatim, and trimming on display leaves the PDF, supplier email and
   screen reader holding the raw value.';

-- The one existing row, fixed. Measured before: 1 of 1 material_items rows had
-- untrimmed name; 0 had untrimmed unit. The SOURCE estimate line is itself
-- untrimmed (1 of 21 estimate_line_items) and is deliberately NOT touched — it
-- is the user's own text inside a signed estimate document, and rewriting that
-- is a different decision with a different owner.
update public.material_items
   set name = btrim(name)
 where name <> btrim(name);

-- ===========================================================================
-- (2) A PURCHASE ORDER THAT HAS LEFT DRAFT CANNOT BE DELETED.
--
-- MEASURED BY BEHAVIOUR BEFORE THE CHANGE, not by reading the body: a PO at
-- `sent` and a PO at `confirmed` were BOTH deleted successfully — the function
-- never read `status`. So cancel was not the only path out, and a sent order
-- could be erased rather than cancelled, taking its promise history with it.
-- The control in the same run: a jobless DRAFT deleted cleanly, which the
-- 2026-09-11 ruling requires and which this change preserves.
--
-- THE RULING: a draft with no job is a phone call that never became an order
-- and has no history worth keeping, so delete stays. Once a PO has been SENT,
-- somebody outside the company has been told something; cancel records that,
-- delete pretends it never happened.
-- ===========================================================================
create or replace function public.delete_purchase_order(p_po_id uuid)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare v_org_id uuid; v_status text; v_items uuid[];
begin
  select org_id, status into v_org_id, v_status
  from public.purchase_orders where id = p_po_id;
  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'purchase order not found or not accessible: %', p_po_id;
  end if;
  if not public.has_capability(v_org_id, 'manage_purchasing') then
    raise exception 'your role cannot delete purchase orders in this workspace';
  end if;

  if v_status <> 'draft' then
    raise exception 'this purchase order is % and cannot be deleted — a supplier has already been told about it. Cancel it instead, which keeps the record and its promise history.', v_status;
  end if;

  select array_agg(distinct material_item_id) into v_items
    from public.purchase_order_lines where purchase_order_id = p_po_id;
  delete from public.purchase_orders where id = p_po_id;
  if v_items is not null then
    perform public.recompute_material_item_ready_by(i) from unnest(v_items) i;
  end if;
end;
$function$;

-- Rule 7: signature unchanged, but re-assert since the function was replaced.
revoke execute on function public.delete_purchase_order(uuid) from public, anon;

-- Rule 3: never trust the success response.
do $$
declare v_untrimmed int;
begin
  select count(*) into v_untrimmed from public.material_items where name <> btrim(name);
  if v_untrimmed <> 0 then raise exception '% material_items rows still hold an untrimmed name', v_untrimmed; end if;
  if not exists (select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid
                 where c.relname='material_items' and t.tgname='material_items_trim_text' and not t.tgisinternal)
    then raise exception 'the trim trigger is not attached'; end if;
end $$;
