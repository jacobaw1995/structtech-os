-- 12_wh-team-members-roles.sql
-- Phase 1 Part B — WH admin roles (admin / assistant / driver), enforced in the DB.
--
-- Target project : ejlhrykcdfcyeooooodx (structtech)
-- WH org         : "Material Matrix"  1084baa8-0355-4298-9b98-b876a7581173 (tenant_type='supplier')
-- Helper in place : public.my_org_ids()  -> SETOF uuid, SECURITY DEFINER,
--                   body: select org_id from org_members where user_id = auth.uid()

begin;

-- ── 1. wh_team_members ────────────────────────────────────────────────────
create table if not exists public.wh_team_members (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null default '1084baa8-0355-4298-9b98-b876a7581173'
                  references public.organizations(id) on delete cascade,
  user_id       uuid references auth.users(id) on delete cascade,   -- null for login-less drivers
  name          text not null,
  email         text not null,
  phone         text,
  role          text not null default 'assistant'
                  check (role in ('admin','assistant','driver')),
  is_driver     boolean not null default false,
  driver_active boolean not null default false,
  status        text not null default 'active'
                  check (status in ('active','invited','disabled')),
  created_at    timestamptz not null default now()
);

-- One WH role row per (org, auth user); also the arbiter for the admin upsert seed.
create unique index if not exists wh_team_members_org_user_uk
  on public.wh_team_members (org_id, user_id)
  where user_id is not null;

-- One active driver per org (DATA-MODEL §4).
create unique index if not exists wh_team_members_one_active_driver
  on public.wh_team_members (org_id)
  where driver_active = true;

alter table public.wh_team_members enable row level security;

-- ── 2. my_wh_role() — the caller's WH role in their org ───────────────────
-- SECURITY DEFINER so it reads wh_team_members without tripping that table's own
-- RLS (same pattern as my_org_ids()). Prefers admin > assistant if several rows.
create or replace function public.my_wh_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role
  from public.wh_team_members
  where user_id = auth.uid()
    and status = 'active'
    and org_id in (select public.my_org_ids())
  order by (role = 'admin') desc, (role = 'assistant') desc
  limit 1
$$;

-- ── 3. wh_team_members RLS — org members read, admins write ───────────────
drop policy if exists "wh_team_members org read"   on public.wh_team_members;
drop policy if exists "wh_team_members admin write" on public.wh_team_members;

create policy "wh_team_members org read"
  on public.wh_team_members
  for select
  using (org_id in (select public.my_org_ids()));

create policy "wh_team_members admin write"
  on public.wh_team_members
  for all
  using      (org_id in (select public.my_org_ids()) and public.my_wh_role() = 'admin')
  with check (org_id in (select public.my_org_ids()) and public.my_wh_role() = 'admin');

-- ── 4. Tighten catalog writes: insert/update = admin|assistant, delete = admin ─
-- Replaces the single cmd=ALL "WH org write <t>" policy (which let ANY org member
-- delete). Shop anon-read and authenticated-read SELECT policies are left as-is.

-- wh_products ---------------------------------------------------------------
drop policy if exists "WH org write wh_products" on public.wh_products;

create policy "wh_products role insert" on public.wh_products
  for insert
  with check (org_id in (select public.my_org_ids())
              and public.my_wh_role() in ('admin','assistant'));

create policy "wh_products role update" on public.wh_products
  for update
  using      (org_id in (select public.my_org_ids())
              and public.my_wh_role() in ('admin','assistant'))
  with check (org_id in (select public.my_org_ids())
              and public.my_wh_role() in ('admin','assistant'));

create policy "wh_products admin delete" on public.wh_products
  for delete
  using (org_id in (select public.my_org_ids()) and public.my_wh_role() = 'admin');

-- wh_colors -----------------------------------------------------------------
drop policy if exists "WH org write wh_colors" on public.wh_colors;

create policy "wh_colors role insert" on public.wh_colors
  for insert
  with check (org_id in (select public.my_org_ids())
              and public.my_wh_role() in ('admin','assistant'));

create policy "wh_colors role update" on public.wh_colors
  for update
  using      (org_id in (select public.my_org_ids())
              and public.my_wh_role() in ('admin','assistant'))
  with check (org_id in (select public.my_org_ids())
              and public.my_wh_role() in ('admin','assistant'));

create policy "wh_colors admin delete" on public.wh_colors
  for delete
  using (org_id in (select public.my_org_ids()) and public.my_wh_role() = 'admin');

-- wh_categories -------------------------------------------------------------
drop policy if exists "WH org write wh_categories" on public.wh_categories;

create policy "wh_categories role insert" on public.wh_categories
  for insert
  with check (org_id in (select public.my_org_ids())
              and public.my_wh_role() in ('admin','assistant'));

create policy "wh_categories role update" on public.wh_categories
  for update
  using      (org_id in (select public.my_org_ids())
              and public.my_wh_role() in ('admin','assistant'))
  with check (org_id in (select public.my_org_ids())
              and public.my_wh_role() in ('admin','assistant'));

create policy "wh_categories admin delete" on public.wh_categories
  for delete
  using (org_id in (select public.my_org_ids()) and public.my_wh_role() = 'admin');

-- ── 5. Backfill drivers -> wh_team_members (wh_drivers KEPT INTACT) ────────
-- wh_drivers rows have no user_id, so backfilled rows are login-less (user_id
-- null). Idempotent via NOT EXISTS on (org_id, lower(email)).
-- NOTE: assumes at most one active driver per org (wh_drivers currently has 1
-- row). If an org had 2+ active drivers this would violate the one-active index.
insert into public.wh_team_members (org_id, name, email, phone, role, is_driver, driver_active, status)
select d.org_id, d.name, d.email, d.phone, 'driver', true, coalesce(d.active, false), 'active'
from public.wh_drivers d
where not exists (
  select 1 from public.wh_team_members t
  where t.org_id = d.org_id and lower(t.email) = lower(d.email)
);

-- ── 6. Seed jacob@structtek.com as admin (id looked up from auth.users) ───
insert into public.wh_team_members (org_id, user_id, name, email, role, status)
select '1084baa8-0355-4298-9b98-b876a7581173',
       u.id,
       coalesce(nullif(split_part(u.email, '@', 1), ''), 'Admin'),
       u.email,
       'admin',
       'active'
from auth.users u
where lower(u.email) = 'jacob@structtek.com'
on conflict (org_id, user_id) where user_id is not null
do update set role = 'admin', status = 'active';

commit;
