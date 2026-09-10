-- A WRITE NAMES THE TENANT IT WRITES TO. IT NEVER INFERS ONE FROM A MEMBERSHIP SET.
-- Track S · 2026-09-10. Two defects in the purchase-order write path, found by
-- Track U on 2026-09-09, who refused to ship a control on top of them.
-- Rollback: supabase/rollbacks/20260910_po_org_explicit_and_attach_rollback.sql
--
-- DEFECT 1 — CROSS-TENANT WRITE. create_purchase_order's no-job branch resolved
-- the org with
--     select org_id from org_members where user_id = auth.uid() limit 1
-- NO ORDER BY and NO org argument. my_org_ids() returns a SET by construction,
-- and the one human who drafts POs holds a seat in all three orgs. MEASURED
-- 2026-09-10 before this ran: for that user the expression picks STRUCTTECH —
-- so a jobless PO drafted from the Brothers Metal Roofing workspace would have
-- been written into StructTech's tenant. Same fact that disqualified
-- storage.objects.owner (9/04) and the edge log's subject (9/06): no value
-- derived from identity can be the scoping key when one identity holds every
-- seat. purchase_orders held 0 rows, so no live row was ever misfiled.
--
-- DEFECT 2 — AN INSTRUCTION THE API COULD NOT FOLLOW. job_id was written
-- EXACTLY ONCE, in create's INSERT. update_purchase_order's SET list was
-- supplier_name, supplier_org_id, status, updated_at — never job_id — and no
-- other function wrote it. So its own refusal, "this purchase order has no job,
-- so it cannot leave draft. Attach it to a job first", named an action that did
-- not exist, and a jobless PO could never leave draft by any path.
--
-- SHAPE, derived from the house pattern (create_product(p_org_id, ...) puts the
-- org first) and from rule 1 (a changed signature is an OVERLOAD, so the exact
-- old signature is DROPPED first, copied from pg_get_function_identity_arguments).

drop function if exists public.create_purchase_order(uuid, text, uuid);
drop function if exists public.update_purchase_order(uuid, text, uuid, text);

-- p_org_id is REQUIRED and first. p_job_id is `default null`, so the generated
-- type stops declaring it non-nullable while ruling (b) makes a jobless draft
-- legal. When a job IS given it must belong to the named org — otherwise a caller
-- could name tenant A and attach tenant B's job.
create function public.create_purchase_order(
  p_org_id uuid,
  p_supplier_name text,
  p_job_id uuid default null,
  p_supplier_org_id uuid default null
)
returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare v_job_org uuid; v_id uuid;
begin
  if p_org_id is null or p_org_id not in (select my_org_ids()) then
    raise exception 'organization not found or not accessible: %', p_org_id;
  end if;

  if p_job_id is not null then
    select org_id into v_job_org from public.jobs where id = p_job_id;
    if v_job_org is null or v_job_org <> p_org_id then
      raise exception 'job % does not belong to organization %', p_job_id, p_org_id;
    end if;
  end if;

  if not public.has_capability(p_org_id, 'manage_purchasing') then
    raise exception 'your role cannot create purchase orders in this workspace';
  end if;
  if coalesce(btrim(p_supplier_name), '') = '' then
    raise exception 'a purchase order needs a supplier name';
  end if;
  if p_supplier_org_id is not null and not exists (select 1 from public.organizations where id = p_supplier_org_id) then
    raise exception 'supplier organization not found: %', p_supplier_org_id;
  end if;

  insert into public.purchase_orders (org_id, job_id, supplier_name, supplier_org_id, created_by)
  values (p_org_id, p_job_id, btrim(p_supplier_name), p_supplier_org_id, auth.uid())
  returning id into v_id;
  return v_id;
end;
$function$;

-- THE ATTACH PATH. p_job_id added as a TRAILING DEFAULT, so every existing
-- named-argument caller still matches — the house coalesce-patch pattern of
-- update_schedule_block. The draft guard now tests the EFFECTIVE job, so
-- attach-and-send in one call works, which is exactly the advice the refusal
-- gives. coalesce means a job can be attached or changed but not cleared; no
-- ruling asks for clearing, and it is recorded here rather than implied.
create function public.update_purchase_order(
  p_po_id uuid,
  p_supplier_name text default null,
  p_supplier_org_id uuid default null,
  p_status text default null,
  p_job_id uuid default null
)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare v_org_id uuid; v_job_id uuid; v_status text; v_job_org uuid; v_effective_job uuid;
begin
  select org_id, job_id, status into v_org_id, v_job_id, v_status
  from public.purchase_orders where id = p_po_id;
  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'purchase order not found or not accessible: %', p_po_id;
  end if;
  if not public.has_capability(v_org_id, 'manage_purchasing') then
    raise exception 'your role cannot edit purchase orders in this workspace';
  end if;

  if p_job_id is not null then
    select org_id into v_job_org from public.jobs where id = p_job_id;
    if v_job_org is null or v_job_org <> v_org_id then
      raise exception 'job % does not belong to the organization this purchase order is in', p_job_id;
    end if;
  end if;

  v_effective_job := coalesce(p_job_id, v_job_id);

  -- RULING (b), unchanged in meaning: a PO cannot LEAVE draft without a job.
  -- Now testable against the job this very call attaches.
  if p_status is not null and p_status <> 'draft' and v_status = 'draft' and v_effective_job is null then
    raise exception 'this purchase order has no job, so it cannot leave draft. Attach it to a job first, then set it to %.', p_status;
  end if;

  update public.purchase_orders
     set supplier_name   = coalesce(btrim(p_supplier_name), supplier_name),
         supplier_org_id = coalesce(p_supplier_org_id, supplier_org_id),
         job_id          = v_effective_job,
         status          = coalesce(p_status, status),
         updated_at      = now()
   where id = p_po_id;

  if p_status is not null then
    perform public.recompute_material_item_ready_by(l.material_item_id)
    from (select distinct material_item_id from public.purchase_order_lines where purchase_order_id = p_po_id) l;
  end if;
end;
$function$;

-- Rule 7, per function: a new function in public is PUBLIC-executable from
-- birth. `authenticated` KEPT — a server action is the call path.
revoke execute on function public.create_purchase_order(uuid, text, uuid, uuid) from public, anon;
revoke execute on function public.update_purchase_order(uuid, text, uuid, text, uuid) from public, anon;
