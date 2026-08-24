-- A2.0 — Capability reconciliation.
--
-- Two functions answered "can I see money" and disagreed in production: for a
-- crew-tier member with no permissions row, has_capability(org,'view_financials')
-- returned TRUE (its fallback array granted the capability the row omitted)
-- while can_view_financials(org) returned FALSE. This closes that.
--
-- ORDER IS LOAD-BEARING AND IS THE CONTROLLER'S: helper -> SEED -> flip.
-- The seed runs BEFORE the default closes so that no member's effective
-- capability set changes on the day of this migration.

-- ---------------------------------------------------------------------------
-- 1 · The default moves OFF the read path and ONTO the write path.
--
-- can_view_financials()/can_view_master_work_order() derived their default from
-- role INSIDE the authorization check. That is what made two answers possible.
-- The role default is still honoured — it is now materialised into
-- org_members.permissions at provisioning time instead, where it is one visible
-- row of data rather than a branch hidden in three function bodies.
-- ---------------------------------------------------------------------------
create or replace function public.default_permissions_for_role(p_role text)
returns jsonb
language sql
immutable
as $function$
  select case
    -- Manager tier. is_org_manager() already short-circuits these to true, so
    -- this seed is belt-and-braces: it makes the owner's access survive even a
    -- future change to the bypass, rather than depending on it.
    when p_role in ('owner', 'admin', 'agency_admin') then jsonb_build_object(
      'view_financials',        true,
      'view_estimates',         true,
      'view_field',             true,
      'add_notes',              true,
      'schedule',               true,
      'view_master_work_order', true,
      'edit_leads',             true,
      'create_estimates',       true
    )
    -- Crew tier. THIS IS WHERE THE DEFECT IS FIXED: view_financials and
    -- view_estimates go TRUE -> FALSE for field/client_portal_viewer, which is
    -- constraint 7 ("no dollars in the field") and is what can_view_financials()
    -- already said. view_field/add_notes/schedule stay TRUE because the old
    -- fallback array granted them and A2.0 is not a re-scope.
    when p_role in ('field', 'client_portal_viewer') then jsonb_build_object(
      'view_financials',        false,
      'view_estimates',         false,
      'view_field',             true,
      'add_notes',              true,
      'schedule',               true,
      'view_master_work_order', false,
      'edit_leads',             false,
      'create_estimates',       false
    )
    -- office, member, and any future non-manager role. Reproduces today's
    -- answers: the five in the old fallback array TRUE, view_master_work_order
    -- TRUE (can_view_master_work_order's role default — see the note in the
    -- close-out; has_capability said false for this key but nothing reads it),
    -- and edit_leads/create_estimates FALSE because they were never in the
    -- fallback array and have always failed closed.
    else jsonb_build_object(
      'view_financials',        true,
      'view_estimates',         true,
      'view_field',             true,
      'add_notes',              true,
      'schedule',               true,
      'view_master_work_order', true,
      'edit_leads',             false,
      'create_estimates',       false
    )
  end;
$function$;

revoke execute on function public.default_permissions_for_role(text) from public, anon;

-- ---------------------------------------------------------------------------
-- 2 · SEED, BEFORE THE FLIP.
--
-- `||` is right-biased, so an explicitly-set key already in the row WINS over
-- the role default and is preserved. Every member alive today carries '{}', so
-- every one of them takes the whole default.
-- ---------------------------------------------------------------------------
update public.org_members m
   set permissions = public.default_permissions_for_role(m.role) || m.permissions;

-- ---------------------------------------------------------------------------
-- 3 · THE FLIP. has_capability() is now the ONE authoritative implementation
-- and its default is CLOSED: absence of a key grants nothing.
--
-- Signature is byte-identical to the live one (taken from
-- pg_get_function_identity_arguments, not retyped), so this REPLACES rather
-- than overloads. Verified against pg_proc after apply.
-- ---------------------------------------------------------------------------
create or replace function public.has_capability(p_org_id uuid, p_capability text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(
    case
      when public.is_org_manager(p_org_id) then true
      else (
        select coalesce((m.permissions ->> p_capability)::boolean, false)
        from public.org_members m
        where m.org_id = p_org_id
          and m.user_id = auth.uid()
      )
    end,
    false
  );
$function$;

revoke execute on function public.has_capability(uuid, text) from public, anon;

-- ---------------------------------------------------------------------------
-- 4 · The other two become THIN WRAPPERS. They do not reimplement the rule —
-- they call it. That is why they cannot disagree with it: there is no second
-- body left to disagree from.
-- ---------------------------------------------------------------------------
create or replace function public.can_view_financials(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select public.has_capability(p_org_id, 'view_financials');
$function$;

revoke execute on function public.can_view_financials(uuid) from public, anon;

create or replace function public.can_view_master_work_order(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select public.has_capability(p_org_id, 'view_master_work_order');
$function$;

revoke execute on function public.can_view_master_work_order(uuid) from public, anon;

-- ---------------------------------------------------------------------------
-- 5 · PROVISIONING. Without this the flip is a live break, not a fix: both
-- insert paths default permissions to '{}', so under a closed default the NEXT
-- member provisioned — an office hire accepting an invite — would land in a
-- workspace with the estimating module invisible and every money field null,
-- and nothing in src/ writes permissions, so there would be no way to fix it
-- from the UI. Measured, not assumed: a grep of src/ for `permissions` returns
-- only database.types.ts.
--
-- Both signatures copied verbatim from pg_get_function_identity_arguments.
-- ---------------------------------------------------------------------------
create or replace function public.accept_invite(p_token text, p_full_name text default null::text)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare inv record;
begin
  select * into inv from public.org_invites where token = p_token and accepted_at is null;
  if not found then raise exception 'invalid or used invite'; end if;
  if auth.uid() is null then raise exception 'not signed in'; end if;

  insert into public.org_members (org_id, user_id, role, full_name, permissions)
  values (inv.org_id, auth.uid(), inv.role, p_full_name,
          public.default_permissions_for_role(inv.role))
  on conflict (org_id, user_id) do nothing;

  update public.org_invites set accepted_at = now() where id = inv.id;
  return inv.org_id;
end $function$;

revoke execute on function public.accept_invite(text, text) from public, anon;

create or replace function public.add_org_member(p_org_id uuid, p_user_id uuid, p_role text, p_full_name text default null::text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not is_platform_admin() then
    raise exception 'only a platform admin can add org members';
  end if;

  insert into public.org_members (org_id, user_id, role, full_name, permissions)
  values (p_org_id, p_user_id, p_role, p_full_name,
          public.default_permissions_for_role(p_role))
  on conflict (org_id, user_id) do update
    set role = excluded.role,
        full_name = excluded.full_name,
        -- A ROLE CHANGE RE-DERIVES. Without this branch a demotion
        -- owner -> field would keep the seeded all-true row and put money in
        -- the field — the exact thing constraint 7 forbids, reintroduced by
        -- the seed that was supposed to be safe. Same-role upserts preserve
        -- explicit grants.
        permissions = case
          when org_members.role is distinct from excluded.role
            then public.default_permissions_for_role(excluded.role)
          else org_members.permissions
        end;
end;
$function$;

revoke execute on function public.add_org_member(uuid, uuid, text, text) from public, anon;
