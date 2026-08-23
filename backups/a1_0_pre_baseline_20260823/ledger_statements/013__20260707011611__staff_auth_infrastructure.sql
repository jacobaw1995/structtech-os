
-- Staff (admin) accounts, mirroring the org_members / org_invites / accept_invite pattern
-- already used for the client portal, so the same proven flow is reused for admin.

create table public.staff_users (
  user_id     uuid primary key references auth.users(id),
  role        text not null default 'admin' check (role = any (array['admin'])),
  full_name   text,
  created_at  timestamptz not null default now()
);

create table public.staff_invites (
  id           uuid primary key default gen_random_uuid(),
  token        text not null unique default encode(extensions.gen_random_bytes(12), 'hex'),
  email        text not null,
  role         text not null default 'admin' check (role = any (array['admin'])),
  created_by   uuid references auth.users(id),
  accepted_at  timestamptz,
  created_at   timestamptz not null default now()
);

alter table public.staff_users enable row level security;
alter table public.staff_invites enable row level security;

-- Staff can see the roster and their own invites; nobody else can touch these directly
-- (mutations go through accept_staff_invite / are managed by a service role).
create policy "staff read staff_users" on public.staff_users for select to authenticated
  using (exists (select 1 from public.staff_users su where su.user_id = auth.uid()));
create policy "staff read staff_invites" on public.staff_invites for select to authenticated
  using (exists (select 1 from public.staff_users su where su.user_id = auth.uid()));

create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select exists (select 1 from public.staff_users where user_id = auth.uid())
$function$;

create or replace function public.accept_staff_invite(p_token text, p_full_name text default null)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare inv record;
begin
  select * into inv from public.staff_invites where token = p_token and accepted_at is null;
  if not found then raise exception 'invalid or used invite'; end if;
  if auth.uid() is null then raise exception 'not signed in'; end if;

  insert into public.staff_users (user_id, role, full_name)
  values (auth.uid(), inv.role, p_full_name)
  on conflict (user_id) do nothing;

  update public.staff_invites set accepted_at = now() where id = inv.id;
end;
$function$;
