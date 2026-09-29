-- ROLLBACK for 20260929025510_member_capability_refusal_hints.
-- Restores set_member_capability with six of its seven refusals hintless.
--
-- READ THIS BEFORE RUNNING IT: no sentence changes either way — the messages are byte-identical
-- in both directions. What this removes is the CODE a caller reads from `error.hint`, which
-- sends any future consumer back to matching on prose.
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

  -- THE REFUSAL. On manager tier this write is inert: has_capability short-circuits first.
  if public.is_manager_role(v_role) then
    raise exception 'this member is an % and already passes every capability check — setting % here would change the stored row and nothing else. Change their role instead.', v_role, p_capability;
  end if;

  -- 2026-09-25 — THE RULING, said in words before the CHECK says it in a code.
  -- org_members_portal_viewer_never_schedules would refuse this write with a
  -- 23514 nobody can read; this refusal names the role, the key and the reason.
  if v_role = 'client_portal_viewer' and p_capability = 'schedule' and p_value is true then
    raise exception 'a client portal viewer cannot be given scheduling — that key creates crews and schedule blocks in this workspace. Change their role if they are meant to schedule.'
      using hint = 'portal_viewer_cannot_schedule';
  end if;

  update public.org_members
     set permissions = coalesce(permissions, '{}'::jsonb) || jsonb_build_object(p_capability, p_value)
   where org_id = p_org_id and user_id = p_user_id;
end;
$function$

;
