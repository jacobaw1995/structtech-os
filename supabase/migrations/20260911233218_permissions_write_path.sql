-- THE PERMISSIONS WRITE PATH. Track S · 2026-09-11. Owed since 2026-09-04; G3 is Monday.
-- Rollback: supabase/rollbacks/20260911_permissions_write_path_rollback.sql
--
-- BEFORE-MEASUREMENT, by property rather than by name. THREE things write
-- org_members.permissions, and ALL THREE WRITE THE WHOLE ROLE DEFAULT:
--   accept_invite                                   INSERT column list (the invitee's own path)
--   add_org_member                                  INSERT column list (is_platform_admin only)
--   org_members_rederive_permissions_on_role_change TRIGGER on UPDATE (A2.0b)
-- NOTHING writes an individual capability. The capability grid has been a
-- read-only mirror for eight days because there was no verb for it.
--
-- THE TRIGGER IS THE THIRD WRITER AND IT IS EASY TO MISS — my own first sweep
-- did, because its body says `new.permissions`, not `org_members`. It matters
-- here: A2.0b chose REPLACE-not-merge deliberately, so that a demotion strips
-- elevated keys. CONSEQUENCE, RECORDED RATHER THAN DISCOVERED LATER: an
-- individual grant made below DOES NOT SURVIVE A ROLE CHANGE. That is correct
-- — a role change is a re-statement of what someone is — but any surface
-- offering per-member toggles must say so, or a grant will quietly vanish.

-- ---------------------------------------------------------------------------
-- (a) THE WRITE. One capability, one member.
--
-- WHO MAY CALL IT: is_org_manager(p_org_id) — owner / admin / agency_admin in
-- THAT org. Chosen from the live model, not from preference:
--   · add_org_member is is_platform_admin() only, which would stop Isaac
--     managing his own office staff — the whole point of an editable grid.
--   · No capability key governs member management, and adding an eleventh
--     repeats A2.1's warned re-seed cost plus F5's five branches.
--   · It is the SAME set has_capability() short-circuits, so a manager can
--     never gate themselves out of their own capabilities. No self-lockout.
--
-- THE PROPERTY THAT MAKES IT SAFE: IT REFUSES ON A MANAGER-TIER TARGET.
-- has_capability() returns true for manager tier via is_org_manager() BEFORE it
-- ever reads the stored row. So writing false onto a manager succeeds, changes
-- the row, and changes NOTHING OBSERVABLE — the member still passes every gate.
-- A WRITE THAT SILENTLY DOES NOTHING IS THE SAME FAILURE CLASS AS A CHECK THAT
-- CANNOT FAIL: it reports success and teaches the operator to trust a control
-- that is not connected to anything. So it refuses, and the message says why.
-- ---------------------------------------------------------------------------
create function public.set_member_capability(
  p_org_id uuid,
  p_user_id uuid,
  p_capability text,
  p_value boolean
)
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

  -- THE REFUSAL. See the header: on manager tier this write is inert.
  if v_role in ('owner', 'admin', 'agency_admin') then
    raise exception 'this member is an % and already passes every capability check — setting % here would change the stored row and nothing else. Change their role instead.', v_role, p_capability;
  end if;

  update public.org_members
     set permissions = coalesce(permissions, '{}'::jsonb) || jsonb_build_object(p_capability, p_value)
   where org_id = p_org_id and user_id = p_user_id;
end;
$function$;

comment on function public.set_member_capability(uuid, uuid, text, boolean) is
  'Grant or deny ONE capability for ONE member. Caller must be is_org_manager() in that org. REFUSES on a
   manager-tier target because has_capability() short-circuits for those roles, so the write would be inert —
   a write that silently does nothing is the same failure class as a check that cannot fail. NOTE: A2.0b''s
   trigger re-derives the whole permissions object on a role change, so an individual grant does not survive one.';

-- ---------------------------------------------------------------------------
-- (b) THE READ. The role x capability matrix, as data.
--
-- default_permissions_for_role had EXECUTE revoked from `authenticated` by
-- A2.1c step 1a, and THAT REVOKE STANDS — this does not touch it. Track U
-- therefore carries hand-copied mirrors of it, and they go stale silently: one
-- was false within a day when `schedule` was wired, another when
-- `manage_purchasing` was seeded. This is the narrow read surface that retires
-- them. GUARD THE API BOUNDARY, NOT THE SHARED READER: a definer function runs
-- as its owner, so this can read the deriver while `authenticated` still cannot.
--
-- BOTH AXES ARE DERIVED, NOT LISTED. Roles come from org_members_role_check
-- itself, so adding a role to the constraint makes it appear here immediately —
-- showing all-false until someone gives it a branch, which is exactly F5's
-- visible-failure design. Capabilities come from the deriver's own key set.
-- ---------------------------------------------------------------------------
create function public.role_capability_matrix()
returns table (role text, capability text, allowed boolean)
language sql stable security definer set search_path to 'public'
as $function$
  with roles as (
    select m[1] as role
    from pg_constraint c,
         lateral regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''::text', 'g') as m
    where c.conname = 'org_members_role_check'
  ),
  caps as (
    select jsonb_object_keys(public.default_permissions_for_role('owner')) as capability
  )
  select r.role,
         c.capability,
         (public.default_permissions_for_role(r.role) ->> c.capability)::boolean as allowed
  from roles r cross join caps c
  order by r.role, c.capability;
$function$;

comment on function public.role_capability_matrix() is
  'The role x capability matrix as data, for surfaces that must not hand-copy it. Both axes are DERIVED —
   roles from org_members_role_check, capabilities from default_permissions_for_role''s own key set — so a
   new role or key appears here without anyone editing this function. Exists because the deriver''s EXECUTE
   is revoked from authenticated (A2.1c step 1a) and that revoke stands: this is the narrow boundary, not a
   widening of the shared reader.';

-- Rule 7, per function. `authenticated` KEPT on both: a server action is the
-- call path for the write, and the matrix is read by the permissions screen.
revoke execute on function public.set_member_capability(uuid, uuid, text, boolean) from public, anon;
revoke execute on function public.role_capability_matrix() from public, anon;

-- Rule 3: never trust the success response.
do $$
declare v_rows int; v_roles int; v_caps int;
begin
  select count(*), count(distinct role), count(distinct capability) into v_rows, v_roles, v_caps
    from public.role_capability_matrix();
  if v_roles <> 7 then raise exception 'matrix returned % roles, expected 7', v_roles; end if;
  if v_caps <> 10 then raise exception 'matrix returned % capabilities, expected 10', v_caps; end if;
  if v_rows <> 70 then raise exception 'matrix returned % rows, expected 70', v_rows; end if;
  if exists (
    select 1 from public.role_capability_matrix() m
    where m.allowed is distinct from (public.default_permissions_for_role(m.role) ->> m.capability)::boolean
  ) then raise exception 'matrix disagrees with default_permissions_for_role'; end if;
end $$;
