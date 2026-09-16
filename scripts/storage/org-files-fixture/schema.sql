-- Mirror of the live objects the org-files policies touch.  Track X, X-W1.15, 2026-09-15.
-- LOCAL THROWAWAY CLUSTER ONLY. Never run against Supabase.
--
-- Function bodies are copied verbatim from pg_get_functiondef() on the live project,
-- read 2026-09-15: my_org_ids, is_manager_role, is_org_manager, has_capability,
-- can_view_master_work_order, storage.foldername. The work_orders policies and the six
-- existing storage.objects policies are copied verbatim from pg_policy the same day.
-- Grants mirror has_table_privilege on live: anon and authenticated hold SELECT,
-- INSERT, UPDATE, DELETE (and TRUNCATE) on storage.objects, so RLS is the only barrier.
-- Where a live object is reduced to the columns a policy reads, that is said below.

-- Roles are cluster-wide; the runner loads this file into several databases.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;

create schema auth;
-- Supabase's auth.uid(): the JWT `sub` claim.
create function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid
$$;
grant usage on schema auth to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;

create schema storage;
grant usage on schema storage to anon, authenticated;
create table storage.buckets (id text primary key, name text, public boolean default false);
-- Reduced: live storage.objects has 15 columns; these are the ones a policy or a test reads.
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets(id),
  name text,
  owner uuid,
  created_at timestamptz default now(),
  unique (bucket_id, name)
);
alter table storage.objects enable row level security;
grant select, insert, update, delete, truncate on storage.objects to anon, authenticated;
grant select on storage.buckets to anon, authenticated;

CREATE OR REPLACE FUNCTION storage.foldername(name text)
 RETURNS text[]
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    _parts text[];
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Return everything except the last segment
    RETURN _parts[1 : array_length(_parts,1) - 1];
END
$function$;
grant execute on function storage.foldername(text) to anon, authenticated;

-- Reduced: org_members keeps the columns the helpers read. work_orders keeps the
-- columns the policies read.
create table public.org_members (org_id uuid, user_id uuid, role text, permissions jsonb);
create table public.work_orders (id uuid primary key, org_id uuid not null, kind text not null);
alter table public.work_orders enable row level security;
grant select, insert, update, delete on public.work_orders to authenticated;

CREATE OR REPLACE FUNCTION public.my_org_ids()
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select org_id from public.org_members where user_id = auth.uid()
$function$;

CREATE OR REPLACE FUNCTION public.is_manager_role(p_role text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  -- THE manager tier. The only place this list is written.
  select coalesce(p_role in ('owner', 'admin', 'agency_admin'), false);
$function$;

CREATE OR REPLACE FUNCTION public.is_org_manager(p_org_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.org_members
    where user_id = auth.uid()
      and org_id = p_org_id
      and public.is_manager_role(role)
  );
$function$;

CREATE OR REPLACE FUNCTION public.has_capability(p_org_id uuid, p_capability text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

CREATE OR REPLACE FUNCTION public.can_view_master_work_order(p_org_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.has_capability(p_org_id, 'view_master_work_order');
$function$;

-- Live ACLs: EXECUTE for postgres, authenticated, service_role; no PUBLIC entry.
revoke execute on function public.my_org_ids(), public.is_org_manager(uuid),
  public.has_capability(uuid, text), public.can_view_master_work_order(uuid) from public;
grant execute on function public.my_org_ids(), public.is_org_manager(uuid),
  public.has_capability(uuid, text), public.can_view_master_work_order(uuid) to authenticated;

-- work_orders policies, verbatim (live roles {} = PUBLIC).
create policy "crew cannot reach master work orders" on public.work_orders as restrictive for all
  using (((kind = 'trade'::text) OR can_view_master_work_order(org_id)))
  with check (((kind = 'trade'::text) OR can_view_master_work_order(org_id)));
create policy "member insert own work_orders" on public.work_orders for insert
  with check ((org_id IN ( SELECT my_org_ids() AS my_org_ids)));
create policy "member read own work_orders" on public.work_orders for select
  using ((org_id IN ( SELECT my_org_ids() AS my_org_ids)));
create policy "member update own work_orders" on public.work_orders for update
  using ((org_id IN ( SELECT my_org_ids() AS my_org_ids)))
  with check ((org_id IN ( SELECT my_org_ids() AS my_org_ids)));

-- The six existing storage.objects policies, verbatim: the CONTROL that must not move.
-- my_wh_role() is Material Matrix's; its live body was not read. It is stubbed to
-- NULL, which makes the three MM role policies deny, and the controls below read
-- only the public-read policy, which does not call it.
create function public.my_wh_role() returns text language sql stable as $$ select null::text $$;
grant execute on function public.my_wh_role() to anon, authenticated;
create policy "product-photos public read" on storage.objects for select
  using (((bucket_id = 'product-photos'::text) AND ((name ~~ 'catalog/%'::text) OR (name ~~ 'logos/%'::text) OR (name ~~ 'systems/%'::text))));
create policy "product-photos role delete" on storage.objects for delete to authenticated
  using (((bucket_id = 'product-photos'::text) AND (my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));
create policy "product-photos role insert" on storage.objects for insert to authenticated
  with check (((bucket_id = 'product-photos'::text) AND (my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));
create policy "product-photos role update" on storage.objects for update to authenticated
  using (((bucket_id = 'product-photos'::text) AND (my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))))
  with check (((bucket_id = 'product-photos'::text) AND (my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));
create policy "spec-files customer upload" on storage.objects for insert to authenticated, anon
  with check (((bucket_id = 'spec-files'::text) AND (name ~~ 'specs/%'::text)));
create policy "spec-files staff read" on storage.objects for select to authenticated
  using (((bucket_id = 'spec-files'::text) AND (my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));
