-- ROLLBACK for 20260925053350_material_quantity_is_entered_never_assumed.
-- Restores both invisible 1s. Written before the migration was applied.
--
-- READ THIS BEFORE RUNNING IT: this rollback re-opens the defect. An empty Qty
-- box will again write 1 with nobody told. It exists so the change is reversible,
-- not because reversing it is safe.

drop function if exists public.add_material_item(p_work_order_id uuid, p_name text, p_quantity numeric, p_ready_by date, p_sort_order integer);

create function public.add_material_item(
  p_work_order_id uuid,
  p_name text,
  p_quantity numeric default 1,
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

alter table public.material_items alter column quantity set default 1;
