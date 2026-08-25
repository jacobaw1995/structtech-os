-- A2.0b — close the demotion hole that A2.0's seed CREATED.
--
-- Before A2.0, a role change self-corrected: the default was evaluated on READ,
-- so demoting a manager to `field` immediately produced crew answers. A2.0 moved
-- that default onto the write path, which is the right architecture — and in
-- doing so it made a stale `permissions` row consequential. `org_members` carries
-- `ALL ... using (is_staff())`, so a role can be UPDATEd outside
-- add_org_member() entirely, bypassing its re-derive branch and leaving a
-- demoted member holding a seeded all-true row. That is money in the field,
-- reintroduced by the seed that was supposed to be safe.
--
-- A trigger closes it for EVERY path — the RPC, a direct UPDATE, and anything
-- written later that nobody has thought of yet. That is the point of putting it
-- here rather than in another RPC.

-- SECURITY DEFINER IS LOAD-BEARING, NOT BOILERPLATE, AND THIS WAS PROVED RATHER
-- THAN ASSUMED: A2.0a revoked EXECUTE on default_permissions_for_role() from
-- `authenticated`, so an INVOKER-rights version of this trigger fails the exact
-- path the task exists to close — a direct UPDATE by a staff user dies with
-- `42501 permission denied for function default_permissions_for_role`, measured
-- in a rolled-back transaction. Yesterday's hardening would have silently
-- disarmed today's fix.
create or replace function public.org_members_rederive_permissions_on_role_change()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  -- REPLACE, not merge. A merge would preserve exactly the elevated keys the
  -- demotion exists to remove: demote owner -> field and `view_financials: true`
  -- would survive as an "explicit grant" that nobody ever granted. The role
  -- default is the whole permission set for that role, not a floor under it.
  new.permissions := public.default_permissions_for_role(new.role);
  return new;
end;
$function$;

revoke execute on function public.org_members_rederive_permissions_on_role_change() from public, anon;

drop trigger if exists org_members_rederive_permissions on public.org_members;

-- ROLE CHANGE ONLY, and INSERT is deliberately not covered.
--
-- `when (old.role is distinct from new.role)` keeps a deliberate per-member
-- grant from being stomped by an unrelated write — renaming a member must not
-- silently reset their permissions.
--
-- No INSERT trigger: accept_invite() and add_org_member() already seed, so one
-- here would either double-apply or fight a deliberate provisioning payload.
-- Proved in the same rolled-back probe: an `office` row inserted with a custom
-- restricted payload comes out UNTOUCHED. The residual case — a direct INSERT
-- with permissions '{}' — is left failing CLOSED (that member gets nothing),
-- which is the safe direction and is the posture A2.0 established. Auto-seeding
-- it would be a grant nobody asked for.
create trigger org_members_rederive_permissions
  before update on public.org_members
  for each row
  when (old.role is distinct from new.role)
  execute function public.org_members_rederive_permissions_on_role_change();