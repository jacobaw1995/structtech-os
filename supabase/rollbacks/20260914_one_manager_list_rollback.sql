-- ROLLBACK for 2026-09-14 one_manager_list (ruling 3c).
-- All three bodies captured from pg_get_functiondef() on the LIVE database 2026-09-14 BEFORE the
-- change. Signatures unchanged by the forward migration, so CREATE OR REPLACE restores them, and
-- is_manager_role is dropped last (nothing references it once the three are restored).
--
-- RESTORING THIS RE-OPENS: the manager list ('owner', 'admin', 'agency_admin') written out three
-- times, free to drift.

CREATE OR REPLACE FUNCTION public.is_org_manager(p_org_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.org_members
    where user_id = auth.uid()
      and org_id = p_org_id
      and role in ('owner', 'admin', 'agency_admin')
  );
$function$;

CREATE OR REPLACE FUNCTION public.set_member_capability(p_org_id uuid, p_user_id uuid, p_capability text, p_value boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role text;
begin
  if p_org_id is null or p_org_id not in (select my_org_ids()) then
    raise exception 'organization not found or not accessible: %', p_org_id;
  end if;

  if not public.is_org_manager(p_org_id) then
    raise exception 'only an owner or admin can change what a member can do in this workspace';
  end if;

  select role into v_role from public.org_members
   where org_id = p_org_id and user_id = p_user_id;
  if v_role is null then
    raise exception 'that person is not a member of this organization';
  end if;

  -- The capability must be one the model actually derives. A typo would
  -- otherwise create a phantom key that nothing reads and nothing reports.
  if not (public.default_permissions_for_role('owner') ? p_capability) then
    raise exception '% is not a capability in this system', p_capability;
  end if;

  if p_value is null then
    raise exception 'a capability is granted or denied, never null';
  end if;

  -- THE REFUSAL. See the header: on manager tier this write is inert.
  if v_role in ('owner', 'admin', 'agency_admin') then
    raise exception 'this member is an % and already passes every capability check — setting % here would change the stored row and nothing else. Change their role instead.', v_role, p_capability;
  end if;

  update public.org_members
     set permissions = coalesce(permissions, '{}'::jsonb) || jsonb_build_object(p_capability, p_value)
   where org_id = p_org_id and user_id = p_user_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.default_permissions_for_role(p_role text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case
    when p_role in ('owner', 'admin', 'agency_admin') then jsonb_build_object(
      'view_financials',        true,
      'view_estimates',         true,
      'view_field',             true,
      'add_notes',              true,
      'schedule',               true,
      'view_master_work_order', true,
      'edit_leads',             true,
      'create_estimates',       true,
      'manage_catalog',         true,
      'manage_purchasing',      true
    )
    when p_role in ('field', 'client_portal_viewer') then jsonb_build_object(
      'view_financials',        false,
      'view_estimates',         false,
      'view_field',             true,
      'add_notes',              true,
      'schedule',               true,
      'view_master_work_order', false,
      'edit_leads',             false,
      'create_estimates',       false,
      'manage_catalog',         false,
      'manage_purchasing',      false
    )
    when p_role = 'office' then jsonb_build_object(
      'view_financials',        true,
      'view_estimates',         true,
      'view_field',             true,
      'add_notes',              true,
      'schedule',               true,
      'view_master_work_order', true,
      'edit_leads',             false,
      'create_estimates',       false,
      'manage_catalog',         true,
      'manage_purchasing',      true
    )
    -- `member` — explicit since F5 (2026-09-06). Mirrors manage_catalog: FALSE.
    when p_role = 'member' then jsonb_build_object(
      'view_financials',        true,
      'view_estimates',         true,
      'view_field',             true,
      'add_notes',              true,
      'schedule',               true,
      'view_master_work_order', true,
      'edit_leads',             false,
      'create_estimates',       false,
      'manage_catalog',         false,
      'manage_purchasing',      false
    )
    -- THE CLOSED DEFAULT (F5). An unrecognised role receives NOTHING.
    else jsonb_build_object(
      'view_financials',        false,
      'view_estimates',         false,
      'view_field',             false,
      'add_notes',              false,
      'schedule',               false,
      'view_master_work_order', false,
      'edit_leads',             false,
      'create_estimates',       false,
      'manage_catalog',         false,
      'manage_purchasing',      false
    )
  end;
$function$;

drop function if exists public.is_manager_role(text);
