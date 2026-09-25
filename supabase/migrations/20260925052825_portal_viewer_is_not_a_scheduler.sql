-- 20260925011900 — A PORTAL VIEWER IS NOT A SCHEDULER.
-- Controller ruling, Jacob, 2026-09-25, on a hole Track S reported on 2026-09-17
-- and again on 2026-09-23 while waiting for this ruling.
--
-- THE HOLE. `default_permissions_for_role` put `field` and `client_portal_viewer`
-- in ONE branch, so a portal viewer — a homeowner, or a client's office watching
-- their own job — was seeded `schedule: true`. That key is not decoration: it is
-- the write gate on SIX tables (crews, crew_people, crew_memberships,
-- crew_person_unavailability, work_order_crew_assignments, schedule_blocks) across
-- EIGHTEEN policies, plus add_schedule_block / update_schedule_block /
-- delete_schedule_block and crew_assert_can_manage. A client portal login could
-- have created a crew in the contractor's own workspace.
--
-- BEFORE-MEASUREMENT, this session, not carried from a report: 0 of 8 live
-- org_members hold client_portal_viewer (owner 4, agency_admin 1, field 1,
-- member 1, office 1). Unchanged from 2026-09-22. So nothing is stripped from
-- anybody today and the fix is a closure, not a migration of live access.
--
-- CLOSED AT THE TABLE, NOT ONLY IN THE DERIVER, per the ruling. Three layers:
--   (1) the deriver stops handing it out,
--   (2) any row already holding it is corrected,
--   (3) a CHECK makes the combination impossible — so the closure survives
--       somebody granting it later through set_member_capability, a direct
--       UPDATE, or a path nobody has written yet.
-- Layer 3 is the point. Without it, rule 13 applies: the answer to "what would
-- have to change for this to reopen" would be "somebody grants it", which is an
-- absence standing in for a control. With it, the answer is "somebody drops this
-- constraint", which is a statement about the table, reviewable in the diff that
-- makes it.
--
-- `field` IS NOT TOUCHED. A crew member keeps `schedule: true`; that is a
-- separate question and this ruling did not ask it. Splitting the branch is the
-- whole change to the deriver — every other key for both roles is byte-identical.

-- ---------------------------------------------------------------------------
-- (1) THE DERIVER. Signature unchanged (p_role text), so CREATE OR REPLACE
--     replaces rather than overloading (rule 1), and the existing ACL is
--     preserved — this function is deliberately NOT executable by
--     `authenticated` (rule 7's carve-out: nothing outside the database calls
--     it; only accept_invite, add_org_member, set_member_capability,
--     role_capability_matrix and the role-change trigger do). Verified after.
-- ---------------------------------------------------------------------------
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
    -- `field` — the crew. UNCHANGED by this migration.
    when p_role = 'field' then jsonb_build_object(
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
    -- `client_portal_viewer` — SPLIT OUT of the field branch, 2026-09-25.
    -- Identical to `field` except `schedule`, which is now FALSE. A portal
    -- viewer reads their own job; they do not staff the contractor's crews.
    when p_role = 'client_portal_viewer' then jsonb_build_object(
      'view_financials',        false,
      'view_estimates',         false,
      'view_field',             true,
      'add_notes',              true,
      'schedule',               false,
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

-- ---------------------------------------------------------------------------
-- (2) CORRECT ANY ROW ALREADY HOLDING IT — before the constraint, because a
--     constraint added over a violating row aborts the migration (rule 4's
--     order, applied to an ADD rather than a value change).
--     SURGICAL, not a re-derive: overwriting the whole jsonb would also erase
--     a deliberate per-member grant on some other key, which this ruling did
--     not ask for. Only `schedule` moves.
--     Expected: 0 rows. The statement runs anyway, and the count is recorded.
-- ---------------------------------------------------------------------------
update public.org_members
   set permissions = coalesce(permissions, '{}'::jsonb) || jsonb_build_object('schedule', false)
 where role = 'client_portal_viewer'
   and coalesce((permissions ->> 'schedule')::boolean, false) is true;

-- ---------------------------------------------------------------------------
-- (3) THE FLOOR. Not NOT VALID: it validates the 8 existing rows now, and
--     0 of them are portal viewers, so validation is trivially satisfied and
--     the constraint is enforced from this statement forward.
-- ---------------------------------------------------------------------------
alter table public.org_members
  add constraint org_members_portal_viewer_never_schedules
  check (
    role <> 'client_portal_viewer'
    or coalesce((permissions ->> 'schedule')::boolean, false) = false
  );

-- ---------------------------------------------------------------------------
-- (4) THE SENTENCE. The constraint is the control; a 23514 reaching the
--     permissions editor is not a sentence anybody can act on, so
--     set_member_capability refuses first, and the refusal carries a NAMED code
--     in the hint (the 2026-09-23 ruling: a hint is a contract, a sentence is not).
--     ONE refusal is added. The five that were already here keep their exact
--     sentences and stay HINTLESS — extending the hint contract across this
--     surface is its own task, reported rather than smuggled into a security
--     closure. Signature unchanged -> replace, not overload; ACL preserved
--     (measured after, not assumed).
-- ---------------------------------------------------------------------------
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
$function$;

-- No new function and no new table: nothing to revoke here. Both functions were
-- REPLACED, which preserves proacl — measured before and after, not assumed
-- (rule 3). default_permissions_for_role stays without `authenticated`;
-- set_member_capability keeps it, because the permissions editor calls it.
