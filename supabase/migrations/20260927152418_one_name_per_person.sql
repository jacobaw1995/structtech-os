-- A PERSON HAS ONE NAME, AND THE SCREEN READS THE WRONG COLUMN.
-- Track S · 2026-09-27, from golden path run 1.
--
-- WHAT JACOB SAW, and it is the run's biggest finding:
--   "Unknown changed a material after sign-off: Dumpster (qty 1) → …"   × 5
--   "Decided by a person whose name is not recorded on 2026-09-27."
--
-- THE DIAGNOSIS IN THE DIRECTIVE IS WRONG, AND THIS IS THE MEASUREMENT THAT SHOWS IT.
-- It reads "This is Class B provenance". It is not. THE WRITE PATH IS PERFECT:
--   · work_order_activity: 5 rows, 5 WITH an actor. 0 without.
--   · the sign-off change log specifically: 5 rows, 5 with an actor.
--   · take_off_decisions: 6 rows, 5 with decided_by; the 1 without is source='backfill'
--     from 2026-09-10, legitimately actor-less.
--   · every one of those actor_ids resolves to profiles.full_name = 'Jacob Walker'.
-- Class B is real and is owed — it is the NEXT migration — but it could not have
-- produced a single one of these sentences, and doing it would have left them on screen.
--
-- THE ACTUAL MECHANISM: A PERSON'S NAME IS STORED TWICE AND THE READ PATH PICKS THE
-- COLUMN THAT IS ALLOWED TO BE NULL.
--   · profiles.full_name      — set for every user by handle_new_user. 8 of 8 memberships.
--   · org_members.full_name   — NULLABLE per-membership override. 6 of 8. NULL for
--                               Jacob's membership in the synthetic tenant, and for
--                               Material Matrix's `member`.
-- list_org_members returns `om.full_name` with no fallback, so it handed the screen a
-- NULL and every surface rendered its own fallback word: "Unknown", "a person whose
-- name is not recorded", "a member".
--
-- THE OVERRIDE IS KEPT AND THE ORDER MATTERS. org_members.full_name is not redundant:
-- in this very database it holds "SYNTHETIC Crew" where profiles.full_name holds the
-- account's email address, because handle_new_user falls back to the email when the
-- signup carried no name. So the resolution is coalesce(MEMBERSHIP, PROFILE) — the
-- override wins when it is set, the profile catches it when it is not, and NULL is no
-- longer reachable while a profile exists.
--
-- THREE CALL SITES, SWEPT BY PROPERTY RATHER THAN BY MEMORY (`prosrc ~ 'org_members'`
-- AND `~ '\mfull_name\M'` → 5 hits; accept_invite and add_org_member WRITE the column
-- and are correctly untouched):
--   1. list_org_members     — feeds SIX surfaces: coordination, crm (the Lead Control
--                             Center's memberName → "Unknown"), build, permissions and
--                             both tracker pages.
--   2. fetch_work_order_brief — the CREW's screen: the daily objective's
--                             `published_by_name`, and each acknowledgment's `person`,
--                             which falls back to the literal 'a member'.
--   3. assign_deal_owner    — AND THIS ONE IS NOT A RENDER BUG. It reads the name and
--                             writes `coalesce(name,'Unassigned')` into the activity
--                             row's from_value/to_value, so a NULL is PERMANENTLY
--                             RECORDED as the word "Unassigned". A real assignment in
--                             the synthetic tenant would have been logged forever as
--                             "Unassigned → Unassigned". A false historical record, not
--                             a cosmetic one.
--
-- AND THAT LAST POINT ORDERS THE TWO MIGRATIONS. assign_deal_owner is also one of the
-- seven Class B functions, whose no-op guard is naturally "from is not distinct from
-- to". Had Class B gone first, both sides would still have been NULL→'Unassigned', the
-- guard would have read a REAL assignment as a no-op, and it would have suppressed the
-- row instead of writing it. Name resolution first, provenance second, deliberately.
--
-- NOT A BACKFILL. Copying profiles.full_name into org_members.full_name would create a
-- third copy that goes stale the day somebody changes their name — the mirror problem
-- this build has spent a month deleting. Resolved at read time, in one function.

-- ---------------------------------------------------------------------------
-- THE ONE RESOLVER. `authenticated` is deliberately NOT granted: rule 7's carve-out
-- test is "does anything outside the database call this?", answered per function, and
-- the answer here is NO — only the three functions below do. Same posture as
-- default_permissions_for_role and derive_catalog_price.
-- ---------------------------------------------------------------------------
create or replace function public.member_display_name(p_org_id uuid, p_user_id uuid)
returns text
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(
    (select om.full_name from public.org_members om
      where om.org_id = p_org_id and om.user_id = p_user_id),
    (select pr.full_name from public.profiles pr where pr.id = p_user_id)
  );
$function$;

revoke execute on function public.member_display_name(uuid, uuid) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.list_org_members(p_org_id uuid)
 RETURNS TABLE(user_id uuid, full_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of organization %', p_org_id;
  end if;

  return query
    select om.user_id, public.member_display_name(om.org_id, om.user_id)
    from public.org_members om
    where om.org_id = p_org_id
    order by public.member_display_name(om.org_id, om.user_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.fetch_work_order_brief(p_work_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_org uuid; v_version text; v_today date; v_mine public.work_order_acknowledgments; v_my jsonb;
begin
  v_org := public.assert_work_order_level(p_work_order_id, 'trade');
  v_version := public.work_order_version(p_work_order_id);
  v_today := (now() at time zone 'America/New_York')::date;

  select * into v_mine from public.work_order_acknowledgments a
  where a.work_order_id = p_work_order_id and a.acknowledged_by = auth.uid()
  order by a.acknowledged_at desc limit 1;

  v_my := case
    when v_mine.id is null then jsonb_build_object('state', 'not_acknowledged')
    when v_mine.work_order_version = v_version
      then jsonb_build_object('state', 'acknowledged', 'acknowledged_at', v_mine.acknowledged_at)
    else jsonb_build_object('state', 'scope_changed_since', 'acknowledged_at', v_mine.acknowledged_at)
  end;

  return jsonb_build_object(
    'work_order_id', p_work_order_id,
    'today', v_today,
    'work_order_version', v_version,
    'objective', (select jsonb_build_object('body', o.body, 'objective_date', o.objective_date,
                           'published_at', o.published_at,
                           'published_by_name', public.member_display_name(o.org_id, o.published_by))
                  from public.work_order_objectives o
                  where o.work_order_id = p_work_order_id and o.objective_date = v_today),
    'my_acknowledgment', v_my,
    'acknowledgments', coalesce((
      select jsonb_agg(jsonb_build_object(
               'person', coalesce(public.member_display_name(a.org_id, a.acknowledged_by), 'a member'),
               'acknowledged_at', a.acknowledged_at,
               'state', case when a.work_order_version = v_version then 'current' else 'scope_changed_since' end)
             order by a.acknowledged_at desc)
      from public.work_order_acknowledgments a where a.work_order_id = p_work_order_id), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION public.assign_deal_owner(p_deal_id uuid, p_owner_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_old_owner_id uuid;
  v_old_owner_name text;
  v_new_owner_name text;
  v_actor_id uuid;
begin
  select org_id, owner_id into v_org_id, v_old_owner_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (
    public.is_org_manager(v_org_id)
    or coalesce(v_old_owner_id is null and p_owner_id = auth.uid(), false)
  ) then
    raise exception 'not authorized: only an org manager can reassign; a rep may only claim an unowned lead to themselves';
  end if;

  if p_owner_id is not null and p_owner_id not in (
    select om.user_id from public.org_members om where om.org_id = v_org_id
  ) then
    raise exception 'owner % is not a member of organization %', p_owner_id, v_org_id;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  v_old_owner_name := public.member_display_name(v_org_id, v_old_owner_id);
  v_new_owner_name := public.member_display_name(v_org_id, p_owner_id);

  update public.deals
  set owner_id = p_owner_id,
      updated_at = now()
  where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, from_value, to_value, actor_id)
  values (
    p_deal_id, v_org_id, 'owner_assigned',
    coalesce(v_old_owner_name, 'Unassigned'),
    coalesce(v_new_owner_name, 'Unassigned'),
    v_actor_id
  );
end;
$function$;
-- Signatures, grants and refusals on the three rewritten functions are unchanged;
-- each was machine-rewritten from its live pg_get_functiondef, so nothing else moved.
