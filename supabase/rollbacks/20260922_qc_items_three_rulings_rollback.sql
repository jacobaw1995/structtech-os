-- ROLLBACK for 20260922 qc_items_three_rulings. Restores qc_items to the state X's proposal left it in:
-- no first/latest attestation pair, no attester allow-list, and photo_ref trusted rather than resolved.
-- The first_* values are dropped with the columns and cannot be recovered.
drop trigger if exists qc_items_guard_write on public.qc_items;
drop trigger if exists qc_items_carry_first_attestation on public.qc_items;
drop function if exists public.qc_items_guard_write();
drop function if exists public.qc_items_carry_first_attestation();
alter table public.qc_items drop column if exists first_occurred_at;
alter table public.qc_items drop column if exists first_actor_id;

create or replace function public.record_qc_item(
  p_work_order_id uuid, p_requirement_key text, p_kind text,
  p_photo_ref text default null, p_count_value integer default null
) returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_actor uuid := auth.uid();
  v_org uuid;
  v_kind text;
  v_id uuid;
begin
  if v_actor is null then
    raise exception 'not signed in';
  end if;
  select w.org_id, w.kind into v_org, v_kind
  from public.work_orders w
  where w.id = p_work_order_id
    and w.org_id in (select public.my_org_ids())
    and (w.kind = 'trade' or public.can_view_master_work_order(w.org_id));
  if v_org is null then
    raise exception 'that work order is not one you can record against';
  end if;
  update public.qc_items
     set cleared_at = now(), cleared_by = v_actor
   where work_order_id = p_work_order_id
     and requirement_key = p_requirement_key
     and cleared_at is null;
  insert into public.qc_items (org_id, work_order_id, requirement_key, kind, photo_ref, count_value, actor_id)
  values (v_org, p_work_order_id, p_requirement_key, p_kind, p_photo_ref, p_count_value, v_actor)
  returning id into v_id;
  return v_id;
end;
$function$;

create or replace function public.clear_qc_item(p_work_order_id uuid, p_requirement_key text)
returns integer language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_actor uuid := auth.uid();
  v_rows integer := 0;
begin
  if v_actor is null then
    raise exception 'not signed in';
  end if;
  update public.qc_items q
     set cleared_at = now(), cleared_by = v_actor
   where q.work_order_id = p_work_order_id
     and q.requirement_key = p_requirement_key
     and q.cleared_at is null
     and q.org_id in (select public.my_org_ids())
     and exists (
       select 1 from public.work_orders w
       where w.id = q.work_order_id
         and (w.kind = 'trade' or public.can_view_master_work_order(w.org_id))
     );
  get diagnostics v_rows = row_count;
  return v_rows;
end;
$function$;
drop function if exists public.qc_photo_on_work_order(uuid, text);
drop function if exists public.is_qc_attester(uuid);
