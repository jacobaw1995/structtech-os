-- ROLLBACK for 2026-09-15 role_capability_matrix_manager_tier. Body captured from pg_get_functiondef()
-- on the LIVE database 2026-09-15 before the change. The return type differs, so drop first (rule 1).
drop function if exists public.role_capability_matrix();
CREATE OR REPLACE FUNCTION public.role_capability_matrix()
 RETURNS TABLE(role text, capability text, allowed boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
revoke execute on function public.role_capability_matrix() from public, anon;
