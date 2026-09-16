-- CLASS A PROVENANCE: A NO-OP NO LONGER RE-STAMPS WHEN. Track S · 2026-09-16. §7.1 RULE 10.
-- Rollback: supabase/rollbacks/20260916_class_a_provenance_on_change_rollback.sql
-- Sweep: supabase/sweeps/provenance_stamp_sweep.sql (Class A, BREAKS 4).
--
-- PROVED BEFORE (rolled back, synthetic Fake Lead deal/estimate and a synthetic tracker project + item, each
-- stamp SEEDED to 2020-01-01 first — a same-transaction comparison of now() is an empty instrument):
--   archive_deal on an archived deal       → archived_at rewritten to now, a second 'archived' activity row
--   present_estimate, same total            → presented_at rewritten to now
--   archive_tracker_project on archived     → archived_at and updated_at rewritten to now
--   archive_tracker_item on archived        → archived_at and updated_at rewritten to now
-- Live exposure at the time: 0 archived deals with an 'archived' activity row, 0 archived tracker items.
--
-- THE CHANGE: each function compares what it would write with what is stored and writes only what differs.
--   archive_deal     — already archived: archived_at and the 'archived' activity row are left as they are.
--                      Pending follow-ups are still cancelled (a real change on those rows, as before).
--   present_estimate — already 'presented' at the same presented_total: nothing is written. A changed total
--                      is a real re-presentation and stamps presented_at, as before.
--   archive_tracker_* — archived_at keeps its first value; the row is updated (and updated_at stamped) only
--                      when a value actually changes.
-- Signatures, grants and refusals are unchanged. Class B (7 activity-row functions) is NOT in this migration.

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
  v_archived_at timestamptz;
begin
  select org_id, owner_id, archived_at into v_org_id, v_owner_id, v_archived_at from public.deals where id = p_deal_id;

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

  update public.follow_ups set status = 'cancelled'
  where deal_id = p_deal_id and status = 'pending';

  -- RULE 10: archiving an archived deal changes no value, so it does not change when it was archived or who did it.
  if v_archived_at is not null then
    return;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals set archived_at = now() where id = p_deal_id;

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

  -- RULE 10: only an unarchived item is stamped.
  update public.tracker_items
  set archived_at = now(), updated_at = now()
  where id = p_item_id and archived_at is null;
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

  -- RULE 10: archived_at keeps its first value; the row is touched only when status or archived_at changes.
  update public.tracker_projects
  set status = 'archived', archived_at = coalesce(archived_at, now()), updated_at = now()
  where id = p_project_id
    and (status is distinct from 'archived' or archived_at is null);
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
  v_presented_total numeric;
begin
  select org_id, status, subtotal, tax_amount, presented_total
    into v_org_id, v_status, v_subtotal, v_tax_amount, v_presented_total
  from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  if v_status in ('signed', 'void') then
    raise exception 'estimate % cannot be presented from status %', p_estimate_id, v_status;
  end if;

  -- RULE 10: re-presenting the same total changes no value, so presented_at keeps when it was first presented.
  if v_status = 'presented' and v_presented_total is not distinct from (v_subtotal + coalesce(v_tax_amount, 0)) then
    return;
  end if;

  update public.estimates
  set status = 'presented',
      presented_total = v_subtotal + coalesce(v_tax_amount, 0),
      presented_at = now()
  where id = p_estimate_id;
end;
$function$;
