-- ROLLBACK for 20260907 a2_3_purchase_orders.
-- Written BEFORE the forward migration. The three tables and nine functions do
-- not exist yet (confirmed against pg_class/pg_proc 2026-09-07, not assumed),
-- so there is nothing to capture from the catalog for them — the rollback is a
-- drop list. The ONE pre-existing object this migration alters is
-- `material_items`, whose pre-change column list was read from the live
-- catalog and is reproduced here:
--   id, org_id, work_order_id, name, quantity, ready_by, sort_order,
--   created_at, updated_at, estimate_line_item_id, product_id, unit
-- i.e. WITHOUT ready_by_source. Dropping that column restores it exactly.

drop function if exists public.list_purchase_orders(uuid, uuid);
drop function if exists public.fetch_purchase_order(uuid);
drop function if exists public.delete_purchase_order_line(uuid);
drop function if exists public.update_purchase_order_line(uuid, numeric, date);
drop function if exists public.add_purchase_order_line(uuid, uuid, numeric, date);
drop function if exists public.delete_purchase_order(uuid);
drop function if exists public.update_purchase_order(uuid, text, uuid, text);
drop function if exists public.create_purchase_order(uuid, text, uuid);
drop function if exists public.recompute_material_item_ready_by(uuid);

drop table if exists public.purchase_order_line_promises;
drop table if exists public.purchase_order_lines;
drop table if exists public.purchase_orders;

alter table public.material_items drop column if exists ready_by_source;

-- `default_permissions_for_role` is NOT edited by the forward migration, so
-- there is nothing to restore here. The new capability key `manage_purchasing`
-- is resolved for every live member by has_capability()'s manager short-circuit
-- and is stored on no row; dropping the policies above removes every reader of
-- it. See the forward migration's PART 0 for why.
