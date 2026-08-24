-- A2.0a — follow-up to 20260824203156, caught by re-running the advisors
-- rather than by reasoning about the migration.
--
-- default_permissions_for_role() shipped WITHOUT `set search_path`, which added
-- a second `function_search_path_mutable` WARN (the only other one is
-- public.bmr_ticket_touch, dead residue from another project). The function is
-- not SECURITY DEFINER and references no schema-qualified object, so nothing was
-- exploitable — but the house rule is that every function in `public` pins its
-- search_path, and a WARN that gets normalised is how the next one hides.
alter function public.default_permissions_for_role(text) set search_path to 'public';

-- It is called ONLY from inside accept_invite() and add_org_member(), both
-- SECURITY DEFINER and therefore executing as postgres — so `authenticated`
-- never needs to call it. It inherited an EXECUTE grant from the schema's
-- default privileges on creation, which published it at /rest/v1/rpc/
-- for no reason. Withdrawn.
revoke execute on function public.default_permissions_for_role(text) from authenticated;