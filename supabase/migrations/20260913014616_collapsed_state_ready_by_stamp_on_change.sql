-- THIRD CORRECTIVE, 2026-09-12, to 20260913012939 collapsed_state. PROVED BEFORE FIXED.
--
-- src/components/coordination/MaterialItemRow.tsx PREFILLS the ready_by input with
-- the stored date and submits on blur, so src/lib/coordination/actions.ts
-- updateMaterialItem sends p_ready_by = THE UNCHANGED DATE on every name or
-- quantity edit. collapsed_state stamped 'manual' whenever p_ready_by was NOT NULL,
-- so the most common edit on the page erased the state the migration exists to add:
--   cancel the only PO -> 'orphaned' -> change the quantity -> 'manual'.
-- A form that resends what it was given is not a human typing a date.
--
-- The stamp (and the recompute that follows it) now fires only when the date
-- supplied DIFFERS from the stored one. Signature unchanged.

create or replace function public.update_material_item(
  p_material_item_id uuid, p_name text default null, p_quantity numeric default null,
  p_ready_by date default null, p_sort_order integer default null
)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_org_id uuid; v_work_order_id uuid; v_trade text; v_master_id uuid; v_sign_off_at timestamptz;
  v_old_name text; v_old_quantity numeric; v_old_ready_by date; v_actor_id uuid;
  v_date_changed boolean;
begin
  select mi.org_id, mi.work_order_id, mi.name, mi.quantity, mi.ready_by
  into v_org_id, v_work_order_id, v_old_name, v_old_quantity, v_old_ready_by
  from public.material_items mi where mi.id = p_material_item_id;

  if v_org_id is null then
    raise exception 'material item not found or not accessible: %', p_material_item_id;
  end if;
  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'material item not found or not accessible: %', p_material_item_id;
  end if;

  select w.trade into v_trade from public.work_orders w where w.id = v_work_order_id;
  select s.master_id, s.sign_off_at into v_master_id, v_sign_off_at
  from public.job_master_sign_off(v_work_order_id) s;

  v_date_changed := p_ready_by is not null and p_ready_by is distinct from v_old_ready_by;

  update public.material_items
  set name = coalesce(p_name, name),
      quantity = coalesce(p_quantity, quantity),
      ready_by = coalesce(p_ready_by, ready_by),
      ready_by_source = case when v_date_changed then 'manual' else ready_by_source end,
      sort_order = coalesce(p_sort_order, sort_order),
      updated_at = now()
  where id = p_material_item_id;

  if v_date_changed then
    perform public.recompute_material_item_ready_by(p_material_item_id);
  end if;

  if v_sign_off_at is not null then
    select id into v_actor_id from public.profiles where id = auth.uid();
    insert into public.work_order_activity (work_order_id, org_id, action, from_value, to_value, actor_id)
    values (
      coalesce(v_master_id, v_work_order_id), v_org_id, 'material_updated_after_signoff',
      format('%s (qty %s%s)', v_old_name, v_old_quantity, case when v_old_ready_by is not null then ', ready ' || v_old_ready_by else '' end),
      format('%s (qty %s%s) [%s]', coalesce(p_name, v_old_name), coalesce(p_quantity, v_old_quantity), case when coalesce(p_ready_by, v_old_ready_by) is not null then ', ready ' || coalesce(p_ready_by, v_old_ready_by) else '' end, coalesce(v_trade, 'trade')),
      v_actor_id
    );
  end if;
end;
$function$;

revoke execute on function public.update_material_item(uuid, text, numeric, date, integer) from public, anon;