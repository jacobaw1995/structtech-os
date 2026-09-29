-- A HINT IS A CONTRACT, AND SIX REFUSALS ON THIS SURFACE STILL HAD NONE.
-- Track S · 2026-09-28. Carried since 2026-09-25 and re-printed as "still open" at the end of
-- four consecutive reports — which is the reason it is being closed rather than listed again.
--
-- WHY THIS ONE OF THE FOUR. Shortest path to closed, measured rather than guessed:
--   · signature unchanged, so CREATE OR REPLACE replaces rather than overloading (rule 1);
--   · return type `void` and unchanged, so rule 16's row-type reader sweep does not apply;
--   · NO new object, so no grant or revoke work (rule 7/8);
--   · and NOT ONE SENTENCE CHANGES. Every message below is byte-identical to what is live; the
--     only addition is the `using hint` clause, so there is no deployed-UI window to worry
--     about (rule 5b) — a caller reading `error.message` today reads exactly the same string
--     tomorrow, and a caller reading `error.hint` gets a code where it used to get NULL.
-- The other three carried items each need a decision first: the two signing helpers need the
-- right org test CHOSEN (they have seven in-database callers and no app path), and
-- fetch_field_jobs' UTC default is about to be reopened by the crew-scoping work — fixing it
-- today would mean touching that function twice in two days.
--
-- THE COUNT WAS WRONG AND IT WAS MINE. Every report since 2026-09-25 said "five hintless
-- refusals". Measured today: `set_member_capability` raises **SEVEN** exceptions, **ONE** of
-- which carries a hint (`portal_viewer_cannot_schedule`, added 2026-09-25). **Six** were
-- hintless, not five. The directive repeats the five because it is quoting my report.
--
-- The codes reuse the 2026-09-23 catalog where one fits (`workspace_not_accessible`) and add
-- five that are new to this surface. Nothing in `src/` reads `error.hint` on the permissions
-- page yet, so these are a contract offered before its first consumer — which is the right
-- order, because the alternative is U writing a prose matcher against these sentences and
-- then having to unpick it (the `classifyFieldError` prose-matching we replaced on 09-27).

CREATE OR REPLACE FUNCTION public.set_member_capability(p_org_id uuid, p_user_id uuid, p_capability text, p_value boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role text;
begin
  if p_org_id is null or p_org_id not in (select my_org_ids()) then
    raise exception 'organization not found or not accessible: %', p_org_id
      using hint = 'workspace_not_accessible';
  end if;

  if not public.is_org_manager(p_org_id) then
    raise exception 'only an owner or admin can change what a member can do in this workspace'
      using hint = 'needs_manager';
  end if;

  select role into v_role from public.org_members
   where org_id = p_org_id and user_id = p_user_id;
  if v_role is null then
    raise exception 'that person is not a member of this organization'
      using hint = 'member_not_found';
  end if;

  -- The capability must be one the model actually derives. A typo would
  -- otherwise create a phantom key that nothing reads and nothing reports.
  if not (public.default_permissions_for_role('owner') ? p_capability) then
    raise exception '% is not a capability in this system', p_capability
      using hint = 'capability_unknown';
  end if;

  if p_value is null then
    raise exception 'a capability is granted or denied, never null'
      using hint = 'capability_value_required';
  end if;

  -- THE REFUSAL. On manager tier this write is inert: has_capability short-circuits first.
  if public.is_manager_role(v_role) then
    raise exception 'this member is an % and already passes every capability check — setting % here would change the stored row and nothing else. Change their role instead.', v_role, p_capability
      using hint = 'manager_tier_capability_inert';
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
$function$;
