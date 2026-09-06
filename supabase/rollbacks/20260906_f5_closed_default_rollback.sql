-- ROLLBACK for 20260906 f5_unrecognised_role_gets_nothing.
-- Captured from pg_get_functiondef() on the LIVE database 2026-09-06 BEFORE the
-- change (§7.1 Rule 1 — restore what RAN, not present intent).
--
-- RESTORING THIS RE-OPENS THE FAIL-OPEN DEFAULT: an unrecognised role again
-- receives six of nine capabilities TRUE, including view_financials.
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
    -- `member` and anything future.
    else jsonb_build_object(
      'view_financials', true, 'view_estimates', true, 'view_field', true,
      'add_notes', true, 'schedule', true, 'view_master_work_order', true,
      'edit_leads', false, 'create_estimates', false, 'manage_catalog', false)
  end;
$function$;
revoke execute on function public.default_permissions_for_role(text) from public, anon, authenticated;
