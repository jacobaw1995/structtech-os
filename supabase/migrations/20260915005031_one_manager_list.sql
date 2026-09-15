-- RULING 3(c), 2026-09-14, Jacob: THE MANAGER LIST EXISTS IN THREE PLACES. RECONCILE TO ONE.
-- In one database, three copies of the same rule will drift. Track S · 2026-09-14.
-- Rollback: supabase/rollbacks/20260914_one_manager_list_rollback.sql
--
-- MEASURED BEFORE (catalog, 2026-09-14): the literal list ('owner', 'admin', 'agency_admin') appears in
-- exactly three function bodies and nowhere else in public —
--   · is_org_manager(org)            "is the CALLER a manager of this org"
--   · set_member_capability(…)       "is the TARGET a manager" (the manager-tier refusal)
--   · default_permissions_for_role(role)  "a manager role derives every capability"
-- The three answer one question — IS THIS ROLE MANAGER TIER — about three different people. Two of the
-- copies had no reason to exist beyond not having a function to call.
--
-- THE ONE COPY: is_manager_role(role). The other three call it. Behaviour is unchanged by construction,
-- and proved unchanged: the before-fingerprint is re-taken after this runs —
--   role_capability_matrix(): 70 rows, md5 e0f402f2339f62d6b1e4c209a98d07fa
--   default_permissions_for_role over 7 roles + an unknown role: md5 52c913b00cf73c167473aefa58630d68
--   is_org_manager for every live membership: 4 true, 1 false (the Material Matrix member)
--   set_member_capability on an owner target: refused with the manager-tier message.
--
-- EXECUTE on is_manager_role is revoked from authenticated: every caller is either SECURITY DEFINER
-- (is_org_manager, set_member_capability, and every function that calls default_permissions_for_role —
-- whose own EXECUTE is already revoked from authenticated) or is evaluated inside one.

create function public.is_manager_role(p_role text)
returns boolean language sql immutable set search_path to 'public'
as $function$
  -- THE manager tier. The only place this list is written.
  select coalesce(p_role in ('owner', 'admin', 'agency_admin'), false);
$function$;

create or replace function public.is_org_manager(p_org_id uuid)
returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select exists (
    select 1 from public.org_members
    where user_id = auth.uid()
      and org_id = p_org_id
      and public.is_manager_role(role)
  );
$function$;

create or replace function public.set_member_capability(p_org_id uuid, p_user_id uuid, p_capability text, p_value boolean)
returns void language plpgsql security definer set search_path to 'public'
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

  -- The capability must be one the model actually derives. A typo would
  -- otherwise create a phantom key that nothing reads and nothing reports.
  if not (public.default_permissions_for_role('owner') ? p_capability) then
    raise exception '% is not a capability in this system', p_capability;
  end if;

  if p_value is null then
    raise exception 'a capability is granted or denied, never null';
  end if;

  -- THE REFUSAL. On manager tier this write is inert: has_capability short-circuits first.
  if public.is_manager_role(v_role) then
    raise exception 'this member is an % and already passes every capability check — setting % here would change the stored row and nothing else. Change their role instead.', v_role, p_capability;
  end if;

  update public.org_members
     set permissions = coalesce(permissions, '{}'::jsonb) || jsonb_build_object(p_capability, p_value)
   where org_id = p_org_id and user_id = p_user_id;
end;
$function$;

create or replace function public.default_permissions_for_role(p_role text)
returns jsonb language sql immutable set search_path to 'public'
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

revoke execute on function public.is_manager_role(text) from public, anon, authenticated;
revoke execute on function public.is_org_manager(uuid) from public, anon;
revoke execute on function public.set_member_capability(uuid, uuid, text, boolean) from public, anon;
revoke execute on function public.default_permissions_for_role(text) from public, anon, authenticated;

-- Rule 3: the list is now written exactly once.
do $$
begin
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
       and prosrc ~* $re$'owner'\s*,\s*'admin'\s*,\s*'agency_admin'$re$) <> 1 then
    raise exception 'the manager list is not written exactly once';
  end if;
end $$;