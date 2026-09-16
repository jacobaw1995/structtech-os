-- ROLLBACK for 20260916 class_a_provenance_on_change. Restores the four bodies exactly as they were before
-- (each rewrote its stamp on a no-op). Signatures and grants are unchanged by the migration.
CREATE OR REPLACE FUNCTION public.archive_deal(p_deal_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_owner_id uuid;
  v_actor_id uuid;
begin
  select org_id, owner_id into v_org_id, v_owner_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (
    public.is_org_manager(v_org_id)
    or coalesce(v_owner_id = auth.uid(), false)
    or public.has_capability(v_org_id, 'edit_leads')
  ) then
    raise exception 'not authorized: only the deal owner, an org manager, or a caller with edit_leads can archive this deal';
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals set archived_at = now() where id = p_deal_id;

  update public.follow_ups set status = 'cancelled'
  where deal_id = p_deal_id and status = 'pending';

  insert into public.deal_activity (deal_id, org_id, action, actor_id)
  values (p_deal_id, v_org_id, 'archived', v_actor_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.archive_tracker_item(p_item_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.tracker_items where id = p_item_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'tracker item not found or not accessible: %', p_item_id;
  end if;

  update public.tracker_items
  set archived_at = now(), updated_at = now()
  where id = p_item_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.archive_tracker_project(p_project_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.tracker_projects where id = p_project_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'tracker project not found or not accessible: %', p_project_id;
  end if;

  update public.tracker_projects
  set status = 'archived', archived_at = now(), updated_at = now()
  where id = p_project_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.present_estimate(p_estimate_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_status text;
  v_subtotal numeric;
  v_tax_amount numeric;
begin
  select org_id, status, subtotal, tax_amount into v_org_id, v_status, v_subtotal, v_tax_amount
  from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  if v_status in ('signed', 'void') then
    raise exception 'estimate % cannot be presented from status %', p_estimate_id, v_status;
  end if;

  update public.estimates
  set status = 'presented',
      presented_total = v_subtotal + coalesce(v_tax_amount, 0),
      presented_at = now()
  where id = p_estimate_id;
end;
$function$;
