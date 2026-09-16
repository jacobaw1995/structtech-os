-- MANAGER TIER ON THE MATRIX. Track S · 2026-09-15. Accepted from Track U.
-- Rollback: supabase/rollbacks/20260915_role_capability_matrix_manager_tier_rollback.sql
--
-- The manager list was reconciled to ONE source on 2026-09-14 (20260915005031: is_manager_role). The
-- permissions page still needed to know which roles are manager tier, and U asked for it as a column on
-- the rows it already reads once per request — so the grid, the role reference and the editor cannot
-- disagree. `manager_tier` comes from is_manager_role(), the one copy; no list is written here.
--
-- is_platform_admin() IS DELIBERATELY NOT PART OF THIS. Platform admin is the cross-tenant operator
-- (staff_users); manager tier is a role within one tenant. Same strings in places, different question.
--
-- A new column changes RETURNS TABLE, so the exact old signature is dropped first (rule 1). The deployed
-- page reads role/capability/allowed by name, so an added column breaks nothing already shipped (rule 5b).

drop function if exists public.role_capability_matrix();

create function public.role_capability_matrix()
returns table(role text, capability text, allowed boolean, manager_tier boolean)
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
         (public.default_permissions_for_role(r.role) ->> c.capability)::boolean as allowed,
         public.is_manager_role(r.role) as manager_tier
  from roles r cross join caps c
  order by r.role, c.capability;
$function$;

revoke execute on function public.role_capability_matrix() from public, anon;
grant execute on function public.role_capability_matrix() to authenticated;