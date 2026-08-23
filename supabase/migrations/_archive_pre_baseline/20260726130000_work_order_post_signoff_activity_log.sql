-- Task B (7/24 walkthrough) — post-signature change logging, interim.
--
-- The estimate itself already freezes at status='signed' (Chunk 1). Nothing
-- downstream of it in the coordination module has an equivalent record of
-- "this changed after the customer already approved it." work_orders.
-- sign_off_at is the coordination module's own approval moment (the
-- homeowner has approved color/finish/materials as captured) — a work
-- order can only exist once its estimate is signed
-- (create_work_order_from_estimate enforces that already), so re-checking
-- estimate.status here would be redundant; sign_off_at is the meaningful
-- gate for THIS module.
--
-- Explicitly NOT locking scope fields (color/finish via sign_off_notes,
-- materials via material_items) after sign-off — SCOPE §2.6 forbids
-- stranding the user with no path forward, and Change Orders (the real
-- gate) is backlogged. This is visibility + audit trail only: stamp any
-- change made after sign_off_at into a new activity log, with actor, and
-- the UI surfaces it as "changed after sign-off" (same pattern as the
-- estimate's "edited since presented").

create table public.work_order_activity (
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  org_id uuid not null,
  action text not null,
  from_value text,
  to_value text,
  actor_id uuid,
  created_at timestamptz not null default now()
);

alter table public.work_order_activity enable row level security;

create policy "member read own work_order_activity" on public.work_order_activity
  for select
  using (org_id in (select my_org_ids()));

-- add_material_item: a material added after sign-off is itself the
-- "changed after sign-off" event — no old value to compare against.
create or replace function public.add_material_item(p_work_order_id uuid, p_name text, p_quantity numeric default 1, p_ready_by date default null::date, p_sort_order integer default 0)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_sign_off_at timestamptz;
  v_item_id uuid;
  v_actor_id uuid;
begin
  select org_id, sign_off_at into v_org_id, v_sign_off_at
  from public.work_orders where id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  insert into public.material_items (org_id, work_order_id, name, quantity, ready_by, sort_order)
  values (v_org_id, p_work_order_id, p_name, p_quantity, p_ready_by, p_sort_order)
  returning id into v_item_id;

  if v_sign_off_at is not null then
    select id into v_actor_id from public.profiles where id = auth.uid();
    insert into public.work_order_activity (work_order_id, org_id, action, to_value, actor_id)
    values (p_work_order_id, v_org_id, 'material_added_after_signoff', p_name, v_actor_id);
  end if;

  return v_item_id;
end;
$function$;

create or replace function public.update_material_item(p_material_item_id uuid, p_name text default null::text, p_quantity numeric default null::numeric, p_ready_by date default null::date, p_sort_order integer default null::integer)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
  v_sign_off_at timestamptz;
  v_old_name text;
  v_old_quantity numeric;
  v_old_ready_by date;
  v_actor_id uuid;
begin
  select mi.org_id, mi.work_order_id, wo.sign_off_at, mi.name, mi.quantity, mi.ready_by
  into v_org_id, v_work_order_id, v_sign_off_at, v_old_name, v_old_quantity, v_old_ready_by
  from public.material_items mi
  join public.work_orders wo on wo.id = mi.work_order_id
  where mi.id = p_material_item_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'material item not found or not accessible: %', p_material_item_id;
  end if;

  update public.material_items
  set name = coalesce(p_name, name),
      quantity = coalesce(p_quantity, quantity),
      ready_by = coalesce(p_ready_by, ready_by),
      sort_order = coalesce(p_sort_order, sort_order),
      updated_at = now()
  where id = p_material_item_id;

  if v_sign_off_at is not null then
    select id into v_actor_id from public.profiles where id = auth.uid();
    insert into public.work_order_activity (work_order_id, org_id, action, from_value, to_value, actor_id)
    values (
      v_work_order_id, v_org_id, 'material_updated_after_signoff',
      format('%s (qty %s%s)', v_old_name, v_old_quantity, case when v_old_ready_by is not null then ', ready ' || v_old_ready_by else '' end),
      format('%s (qty %s%s)', coalesce(p_name, v_old_name), coalesce(p_quantity, v_old_quantity), case when coalesce(p_ready_by, v_old_ready_by) is not null then ', ready ' || coalesce(p_ready_by, v_old_ready_by) else '' end),
      v_actor_id
    );
  end if;
end;
$function$;

create or replace function public.delete_material_item(p_material_item_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_work_order_id uuid;
  v_sign_off_at timestamptz;
  v_name text;
  v_actor_id uuid;
begin
  select mi.org_id, mi.work_order_id, wo.sign_off_at, mi.name
  into v_org_id, v_work_order_id, v_sign_off_at, v_name
  from public.material_items mi
  join public.work_orders wo on wo.id = mi.work_order_id
  where mi.id = p_material_item_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'material item not found or not accessible: %', p_material_item_id;
  end if;

  delete from public.material_items where id = p_material_item_id;

  if v_sign_off_at is not null then
    select id into v_actor_id from public.profiles where id = auth.uid();
    insert into public.work_order_activity (work_order_id, org_id, action, from_value, actor_id)
    values (v_work_order_id, v_org_id, 'material_deleted_after_signoff', v_name, v_actor_id);
  end if;
end;
$function$;

-- record_work_order_sign_off is called twice in the normal flow: once to
-- SET sign_off_at (the initial approval — not a "change after," it IS the
-- signature) and, if called again, to edit sign_off_notes on an
-- already-signed-off work order — that second call is the "color/finish
-- changed after sign-off" case.
create or replace function public.record_work_order_sign_off(p_work_order_id uuid, p_notes text default null::text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_was_signed_off boolean;
  v_old_notes text;
  v_actor_id uuid;
begin
  select org_id, sign_off_at is not null, sign_off_notes
  into v_org_id, v_was_signed_off, v_old_notes
  from public.work_orders where id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  update public.work_orders
  set sign_off_at = coalesce(sign_off_at, now()),
      sign_off_notes = coalesce(p_notes, sign_off_notes),
      updated_at = now()
  where id = p_work_order_id;

  if v_was_signed_off and p_notes is not null and p_notes is distinct from v_old_notes then
    select id into v_actor_id from public.profiles where id = auth.uid();
    insert into public.work_order_activity (work_order_id, org_id, action, from_value, to_value, actor_id)
    values (p_work_order_id, v_org_id, 'signoff_notes_updated_after_signoff', coalesce(v_old_notes, '—'), p_notes, v_actor_id);
  end if;
end;
$function$;
