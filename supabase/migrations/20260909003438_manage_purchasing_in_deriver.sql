-- `manage_purchasing` GETS A HOME IN THE DERIVER.
-- Track S · 2026-09-08. Gates G2 (Thursday 2026-09-10).
--
-- THE DEFECT: A2.3 shipped `manage_purchasing` on 2026-09-07 as an ENFORCED key
-- with no DERIVED home. Measured before this ran:
--   13 enforcement sites — 6 RPC bodies + 7 RLS policies
--   default_permissions_for_role('owner') ? 'manage_purchasing'  ->  FALSE
--   9 capabilities DERIVED · 10 ENFORCED — and the gap IS this key
-- Because has_capability() short-circuits on is_org_manager(), only manager
-- tier passed. AN `office` MEMBER COULD NOT CREATE A PURCHASE ORDER, which is
-- Friday's `manage_catalog` trap in a new key: a capability the product relies
-- on, resolved by a fallback rather than by a rule.
--
-- THE PROPERTY (controller, 2026-09-08), with the roles deliberately NOT named
-- in it: THE ROLE THAT MAINTAINS THE CATALOGUE IS THE ROLE THAT PURCHASES FROM
-- IT. A2.1c's recorded reason — "the person who builds estimates maintains the
-- item list" — extends without strain to ordering the materials.
--
-- THE MEMBERSHIP WAS DERIVED FROM THE LIVE FUNCTION, NOT ACCEPTED AS A LIST.
-- Evaluating default_permissions_for_role over every role in
-- org_members_role_check plus an unrecognised control gives manage_catalog:
--     TRUE  -> owner · admin · agency_admin · office
--     FALSE -> field · client_portal_viewer · member · (unrecognised)
-- manage_purchasing MIRRORS that set exactly, key for key. The derived set also
-- matches A2.1c's independently recorded intent ("manager tier TRUE, office
-- TRUE, everything else FALSE"), which is corroboration, not the source.
--
-- THE `else` BRANCH GETS FALSE, WHICH IS F5 HOLDING. An unrecognised role
-- receives no capability; adding a tenth key must not reopen what 2026-09-06
-- closed. Five branches, ten keys each, and the count is asserted below.
create or replace function public.default_permissions_for_role(p_role text)
returns jsonb
language sql
immutable
set search_path to 'public'
as $function$
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

comment on function public.default_permissions_for_role(text) is
  'Role -> capability defaults, evaluated on the WRITE path only (A2.0). TEN keys as of 2026-09-08.
   Seven roles have explicit branches, matching org_members_role_check exactly. An UNRECOGNISED role
   receives NOTHING (closed default, F5, 2026-09-06). manage_purchasing MIRRORS manage_catalog on every
   role: the role that maintains the catalogue is the role that purchases from it.';

-- ---------------------------------------------------------------------------
-- BACKFILL. A2.1c step 2's shape, and the guard is the point.
--
-- `where not (permissions ? 'manage_purchasing')` — a member who has been
-- EXPLICITLY DENIED the key must not be silently re-granted it. Today no row
-- carries the key at all (measured: 0 of 5), so this touches all five; the
-- guard is here for the next time it runs, when that will not be true.
-- The value comes from the deriver, so the seed and the default cannot drift —
-- A2.0's rule, and the reason no literal appears on the right-hand side.
-- ---------------------------------------------------------------------------
update public.org_members
   set permissions = permissions ||
       jsonb_build_object('manage_purchasing',
         (public.default_permissions_for_role(role) ->> 'manage_purchasing')::boolean)
 where not (permissions ? 'manage_purchasing');

-- Rule 7's carve-out, unchanged and re-asserted: nothing outside the database
-- calls this — accept_invite, add_org_member and the role-change trigger are
-- its only callers — so `authenticated` stays revoked alongside public and anon.
revoke execute on function public.default_permissions_for_role(text) from public, anon, authenticated;

-- Rule 3: never trust the success response. These raise if the migration lied.
do $$
declare v_keys int; v_branches int; v_true int;
begin
  select count(*) into v_keys from jsonb_object_keys(public.default_permissions_for_role('owner'));
  if v_keys <> 10 then raise exception 'expected 10 derived keys, got %', v_keys; end if;

  select count(distinct public.default_permissions_for_role(r)::text) into v_branches
    from unnest(array['owner','admin','agency_admin','office','field','client_portal_viewer','member','zzz_unrecognised']) r;
  if v_branches <> 5 then raise exception 'expected 5 distinct deriver answers, got %', v_branches; end if;

  -- THE MIRROR IS ASSERTED, NOT ASSUMED: every role must agree on both keys.
  select count(*) into v_true from unnest(array['owner','admin','agency_admin','office','field','client_portal_viewer','member','zzz_unrecognised']) r
   where (public.default_permissions_for_role(r) ->> 'manage_catalog')
      is distinct from (public.default_permissions_for_role(r) ->> 'manage_purchasing');
  if v_true <> 0 then raise exception 'manage_purchasing does not mirror manage_catalog on % role(s)', v_true; end if;
end $$;
