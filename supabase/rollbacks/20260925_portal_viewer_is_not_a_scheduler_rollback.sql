-- ROLLBACK for 20260925052825_portal_viewer_is_not_a_scheduler.
-- Written before the migration was applied. Restores the three layers in reverse.
--
-- WHAT THIS CANNOT UNDO, stated rather than implied: step (2) of the migration
-- set `schedule: false` on any client_portal_viewer row that held true. It
-- matched 0 rows on 2026-09-25, so on that day this rollback loses nothing. If
-- it is run after a portal viewer has been created, that row keeps
-- `schedule: false` — which is the safe direction, and re-granting it is a
-- deliberate act through set_member_capability once the constraint is gone.

alter table public.org_members
  drop constraint if exists org_members_portal_viewer_never_schedules;

-- set_member_capability, without the portal-viewer refusal.
create or replace function public.set_member_capability(p_org_id uuid, p_user_id uuid, p_capability text, p_value boolean)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
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

  if not (public.default_permissions_for_role('owner') ? p_capability) then
    raise exception '% is not a capability in this system', p_capability;
  end if;

  if p_value is null then
    raise exception 'a capability is granted or denied, never null';
  end if;

  if public.is_manager_role(v_role) then
    raise exception 'this member is an % and already passes every capability check — setting % here would change the stored row and nothing else. Change their role instead.', v_role, p_capability;
  end if;

  update public.org_members
     set permissions = coalesce(permissions, '{}'::jsonb) || jsonb_build_object(p_capability, p_value)
   where org_id = p_org_id and user_id = p_user_id;
end;
$function$;

-- The deriver, with `field` and `client_portal_viewer` sharing one branch again.
create or replace function public.default_permissions_for_role(p_role text)
returns jsonb
language sql
immutable
set search_path to 'public'
as $function$
  select case
    when public.is_manager_role(p_role) then jsonb_build_object(
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
