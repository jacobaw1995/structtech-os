-- ============================================================
-- CLIENT PORTAL v1 — orgs, members, invites, tickets, systems, invoices
-- ============================================================

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  trade text,
  deal_id uuid references public.deals(id),
  created_at timestamptz not null default now()
);

create table if not exists public.org_members (
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','member')),
  full_name text,
  created_at timestamptz not null default now(),
  primary key (org_id, user_id)
);

create table if not exists public.org_invites (
  id uuid primary key default gen_random_uuid(),
  token text unique not null default encode(gen_random_bytes(12), 'hex'),
  org_id uuid not null references public.organizations(id) on delete cascade,
  email text not null,
  role text not null default 'member' check (role in ('owner','member')),
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.tickets (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  title text not null,
  status text not null default 'open' check (status in ('open','in_progress','waiting_client','resolved','closed')),
  priority text not null default 'normal' check (priority in ('low','normal','high')),
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.ticket_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.tickets(id) on delete cascade,
  author_name text not null,          -- 'StructTech' or client display name
  is_structtech boolean not null default false,
  content text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.org_systems (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  description text,
  status text not null default 'in_build' check (status in ('planned','in_build','training','live','maintenance')),
  url text,
  sort int default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.org_invoices (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  label text not null,                -- e.g. "Level 1 — Job Cost Tracking build"
  amount int not null,
  kind text not null default 'invoice' check (kind in ('invoice','upcoming')),
  status text not null default 'due' check (status in ('draft','due','paid','void')),
  due_date date,
  paid_at timestamptz,
  created_at timestamptz not null default now()
);

-- link roadmaps to orgs
alter table public.client_roadmaps add column if not exists org_id uuid references public.organizations(id);

-- ============================================================
-- AUTH HELPERS + RLS
-- ============================================================
create or replace function public.my_org_ids()
returns setof uuid language sql stable security definer as $$
  select org_id from public.org_members where user_id = auth.uid()
$$;

alter table public.organizations enable row level security;
alter table public.org_members enable row level security;
alter table public.org_invites enable row level security;
alter table public.tickets enable row level security;
alter table public.ticket_messages enable row level security;
alter table public.org_systems enable row level security;
alter table public.org_invoices enable row level security;

-- anon = StructTech admin portal (current model; tightens when OS gets auth)
create policy "anon all organizations" on public.organizations for all to anon using (true) with check (true);
create policy "anon all org_members" on public.org_members for all to anon using (true) with check (true);
create policy "anon all org_invites" on public.org_invites for all to anon using (true) with check (true);
create policy "anon all tickets" on public.tickets for all to anon using (true) with check (true);
create policy "anon all ticket_messages" on public.ticket_messages for all to anon using (true) with check (true);
create policy "anon all org_systems" on public.org_systems for all to anon using (true) with check (true);
create policy "anon all org_invoices" on public.org_invoices for all to anon using (true) with check (true);

-- authenticated clients: scoped to their orgs
create policy "member read own org" on public.organizations for select to authenticated
  using (id in (select public.my_org_ids()));
create policy "member read own members" on public.org_members for select to authenticated
  using (org_id in (select public.my_org_ids()));
create policy "member read own systems" on public.org_systems for select to authenticated
  using (org_id in (select public.my_org_ids()));
create policy "member read own invoices" on public.org_invoices for select to authenticated
  using (org_id in (select public.my_org_ids()));
create policy "member read own tickets" on public.tickets for select to authenticated
  using (org_id in (select public.my_org_ids()));
create policy "member create tickets" on public.tickets for insert to authenticated
  with check (org_id in (select public.my_org_ids()));
create policy "member read own ticket messages" on public.ticket_messages for select to authenticated
  using (ticket_id in (select id from public.tickets where org_id in (select public.my_org_ids())));
create policy "member post ticket messages" on public.ticket_messages for insert to authenticated
  with check (ticket_id in (select id from public.tickets where org_id in (select public.my_org_ids())));
create policy "member read own roadmaps" on public.client_roadmaps for select to authenticated
  using (org_id in (select public.my_org_ids()));
create policy "member update own roadmaps" on public.client_roadmaps for update to authenticated
  using (org_id in (select public.my_org_ids())) with check (true);

-- ============================================================
-- Invite acceptance (runs as the newly signed-in user)
-- ============================================================
create or replace function public.accept_invite(p_token text, p_full_name text default null)
returns uuid language plpgsql security definer as $$
declare inv record;
begin
  select * into inv from public.org_invites where token = p_token and accepted_at is null;
  if not found then raise exception 'invalid or used invite'; end if;
  if auth.uid() is null then raise exception 'not signed in'; end if;

  insert into public.org_members (org_id, user_id, role, full_name)
  values (inv.org_id, auth.uid(), inv.role, p_full_name)
  on conflict (org_id, user_id) do nothing;

  update public.org_invites set accepted_at = now() where id = inv.id;
  return inv.org_id;
end $$;

grant execute on function public.accept_invite(text, text) to authenticated;
grant execute on function public.my_org_ids() to authenticated;
