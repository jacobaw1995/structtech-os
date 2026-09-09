-- ROLLBACK for 20260908 manage_purchasing_in_deriver.
-- Captured from pg_get_functiondef() on the LIVE database 2026-09-08 BEFORE the
-- change (§7.1 Rule 1 — restore what RAN, not present intent).
--
-- RESTORING THIS returns default_permissions_for_role to NINE keys, dropping
-- manage_purchasing from every branch. It does NOT strip the key from rows the
-- forward migration back-filled: those are data, and a function rollback does
-- not un-write them. To undo the backfill as well:
--   update public.org_members set permissions = permissions - 'manage_purchasing';
-- That statement is deliberately NOT part of this file — it would also remove
-- the key from any member a human has since set deliberately.

CREATE OR REPLACE FUNCTION public.default_permissions_for_role(p_role text)
 RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path TO 'public'
AS $function$
  select case
    when p_role in ('owner', 'admin', 'agency_admin') then jsonb_build_object(
      'view_financials', true, 'view_estimates', true, 'view_field', true,
      'add_notes', true, 'schedule', true, 'view_master_work_order', true,
      'edit_leads', true, 'create_estimates', true, 'manage_catalog', true)
    when p_role in ('field', 'client_portal_viewer') then jsonb_build_object(
      'view_financials', false, 'view_estimates', false, 'view_field', true,
      'add_notes', true, 'schedule', true, 'view_master_work_order', false,
      'edit_leads', false, 'create_estimates', false, 'manage_catalog', false)
    when p_role = 'office' then jsonb_build_object(
      'view_financials', true, 'view_estimates', true, 'view_field', true,
      'add_notes', true, 'schedule', true, 'view_master_work_order', true,
      'edit_leads', false, 'create_estimates', false, 'manage_catalog', true)
    when p_role = 'member' then jsonb_build_object(
      'view_financials', true, 'view_estimates', true, 'view_field', true,
      'add_notes', true, 'schedule', true, 'view_master_work_order', true,
      'edit_leads', false, 'create_estimates', false, 'manage_catalog', false)
    else jsonb_build_object(
      'view_financials', false, 'view_estimates', false, 'view_field', false,
      'add_notes', false, 'schedule', false, 'view_master_work_order', false,
      'edit_leads', false, 'create_estimates', false, 'manage_catalog', false)
  end;
$function$;
revoke execute on function public.default_permissions_for_role(text) from public, anon, authenticated;
