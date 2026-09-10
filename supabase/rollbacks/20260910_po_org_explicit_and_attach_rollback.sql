-- ROLLBACK for 20260910 po_org_explicit_and_attach.
-- Both bodies captured from pg_get_functiondef() on the LIVE database 2026-09-10
-- BEFORE the change (§7.1 Rule 1). Signatures copied from
-- pg_get_function_identity_arguments(), never retyped (rule 2).
--
-- RESTORING THIS RE-OPENS BOTH DEFECTS: a jobless PO lands in an arbitrary
-- tenant for a multi-org caller, and nothing can attach a job after insert.
-- It also breaks any caller passing p_org_id (the forward shape).

drop function if exists public.create_purchase_order(uuid, text, uuid, uuid);
drop function if exists public.update_purchase_order(uuid, text, uuid, text, uuid);

CREATE OR REPLACE FUNCTION public.create_purchase_order(p_job_id uuid, p_supplier_name text, p_supplier_org_id uuid DEFAULT NULL::uuid)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_org_id uuid; v_id uuid;
begin
  if p_job_id is not null then
    select org_id into v_org_id from public.jobs where id = p_job_id;
    if v_org_id is null or v_org_id not in (select my_org_ids()) then
      raise exception 'job not found or not accessible: %', p_job_id;
    end if;
  else
    select org_id into v_org_id from public.org_members where user_id = auth.uid() limit 1;
    if v_org_id is null then raise exception 'no organization for the current user'; end if;
  end if;
  if not public.has_capability(v_org_id, 'manage_purchasing') then
    raise exception 'your role cannot create purchase orders in this workspace';
  end if;
  if coalesce(btrim(p_supplier_name), '') = '' then
    raise exception 'a purchase order needs a supplier name';
  end if;
  if p_supplier_org_id is not null and not exists (select 1 from public.organizations where id = p_supplier_org_id) then
    raise exception 'supplier organization not found: %', p_supplier_org_id;
  end if;
  insert into public.purchase_orders (org_id, job_id, supplier_name, supplier_org_id, created_by)
  values (v_org_id, p_job_id, btrim(p_supplier_name), p_supplier_org_id, auth.uid())
  returning id into v_id;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.update_purchase_order(p_po_id uuid, p_supplier_name text DEFAULT NULL::text, p_supplier_org_id uuid DEFAULT NULL::uuid, p_status text DEFAULT NULL::text)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_org_id uuid; v_job_id uuid; v_status text;
begin
  select org_id, job_id, status into v_org_id, v_job_id, v_status
  from public.purchase_orders where id = p_po_id;
  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'purchase order not found or not accessible: %', p_po_id;
  end if;
  if not public.has_capability(v_org_id, 'manage_purchasing') then
    raise exception 'your role cannot edit purchase orders in this workspace';
  end if;
  if p_status is not null and p_status <> 'draft' and v_status = 'draft' and v_job_id is null then
    raise exception 'this purchase order has no job, so it cannot leave draft. Attach it to a job first, then set it to %.', p_status;
  end if;
  update public.purchase_orders
     set supplier_name   = coalesce(btrim(p_supplier_name), supplier_name),
         supplier_org_id = coalesce(p_supplier_org_id, supplier_org_id),
         status          = coalesce(p_status, status),
         updated_at      = now()
   where id = p_po_id;
  if p_status is not null then
    perform public.recompute_material_item_ready_by(l.material_item_id)
    from (select distinct material_item_id from public.purchase_order_lines where purchase_order_id = p_po_id) l;
  end if;
end;
$function$;

revoke execute on function public.create_purchase_order(uuid, text, uuid) from public, anon;
revoke execute on function public.update_purchase_order(uuid, text, uuid, text) from public, anon;
