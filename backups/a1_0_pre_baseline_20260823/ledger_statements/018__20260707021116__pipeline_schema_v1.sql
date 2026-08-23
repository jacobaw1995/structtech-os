
-- Sales pipeline (structtech-pipeline). New, standalone tables — does not touch deals/deal_notes/
-- deal_activity. Adapted from a reference lead-CRM schema; roofing-specific fields dropped,
-- a couple of milestone columns renamed to match the command-center's own stage keys
-- (site_visit_complete_at / scope_ordered_at) for internal consistency.

create type public.pipeline_user_role as enum ('salesman', 'manager');
create type public.lead_source as enum ('webhook', 'manual', 'referral');
create type public.lead_stage as enum ('lead_captured', 'qualified', 'proposal_sent', 'negotiating', 'closed');
create type public.lead_status as enum ('active', 'closed_won', 'closed_lost');
create type public.lead_activity_action as enum ('created', 'stage_changed', 'status_changed', 'reassigned', 'value_set', 'edited');

create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text not null,
  email       text not null,
  role        public.pipeline_user_role not null default 'salesman',
  created_at  timestamptz not null default now()
);

create table public.pipeline_invites (
  id           uuid primary key default gen_random_uuid(),
  token        text not null unique default encode(extensions.gen_random_bytes(12), 'hex'),
  email        text not null,
  role         public.pipeline_user_role not null default 'salesman',
  created_by   uuid references auth.users(id),
  accepted_at  timestamptz,
  created_at   timestamptz not null default now()
);

create table public.leads (
  id                        uuid primary key default gen_random_uuid(),
  first_name                text,
  last_name                 text,
  name                      text not null,
  company_name              text,
  phone                     text,
  cell_phone                text,
  secondary_phone           text,
  email                     text,
  street_address            text,
  city                      text,
  state                     text,
  zip                       text,
  service_street_address    text,
  service_city              text,
  service_state             text,
  service_zip               text,
  source                    public.lead_source not null default 'manual',
  referral_name             text,
  stage                     public.lead_stage not null default 'lead_captured',
  status                    public.lead_status not null default 'active',
  value                     numeric(12,2),
  owner_id                  uuid references public.profiles(id),
  claim_locked              boolean not null default false,
  lost_reason               text,
  intake_checklist          jsonb not null default '{}'::jsonb,
  site_visit_complete_at    timestamptz,
  scope_ordered_at          timestamptz,
  quote_presented_at        timestamptz,
  proposal_sent_at          timestamptz,
  last_contacted_at         timestamptz,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  closed_at                 timestamptz
);

create index leads_owner_idx on public.leads(owner_id);
create index leads_stage_idx on public.leads(stage);
create index leads_status_idx on public.leads(status);
create index leads_created_at_idx on public.leads(created_at);

create table public.lead_notes (
  id          uuid primary key default gen_random_uuid(),
  lead_id     uuid not null references public.leads(id) on delete cascade,
  author_id   uuid not null references public.profiles(id),
  content     text not null,
  created_at  timestamptz not null default now()
);
create index lead_notes_lead_idx on public.lead_notes(lead_id);

create table public.lead_activity (
  id          uuid primary key default gen_random_uuid(),
  lead_id     uuid not null references public.leads(id) on delete cascade,
  actor_id    uuid not null references public.profiles(id),
  action      public.lead_activity_action not null,
  from_value  text,
  to_value    text,
  created_at  timestamptz not null default now()
);
create index lead_activity_lead_idx on public.lead_activity(lead_id);

create table public.lead_appointments (
  id                 uuid primary key default gen_random_uuid(),
  lead_id            uuid not null references public.leads(id) on delete cascade,
  title              text,
  scheduled_at       timestamptz not null,
  duration_minutes   int not null default 60,
  status             text not null default 'scheduled' check (status = any (array['scheduled','completed','cancelled','no_show'])),
  notes              text,
  completed_at       timestamptz,
  cancelled_at       timestamptz,
  created_at         timestamptz not null default now()
);
create index lead_appointments_lead_idx on public.lead_appointments(lead_id);

create or replace function public.is_pipeline_user()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid())
$$;

create or replace function public.is_pipeline_manager()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'manager')
$$;

create or replace function public.accept_pipeline_invite(p_token text, p_full_name text default null)
returns void language plpgsql security definer set search_path = public as $function$
declare inv record; u_email text;
begin
  select * into inv from public.pipeline_invites where token = p_token and accepted_at is null;
  if not found then raise exception 'invalid or used invite'; end if;
  if auth.uid() is null then raise exception 'not signed in'; end if;

  select email into u_email from auth.users where id = auth.uid();

  insert into public.profiles (id, full_name, email, role)
  values (auth.uid(), coalesce(p_full_name, u_email), u_email, inv.role)
  on conflict (id) do nothing;

  update public.pipeline_invites set accepted_at = now() where id = inv.id;
end;
$function$;

create or replace function public.my_closes_this_month() returns integer
language sql security definer set search_path = public as $$
  select count(*)::int from public.leads
  where owner_id = auth.uid() and status = 'closed_won' and closed_at >= date_trunc('month', now());
$$;

create or replace function public.my_win_rate() returns numeric
language sql security definer set search_path = public as $$
  select case when total = 0 then 0 else round((won::numeric / total) * 100, 1) end
  from (
    select count(*) filter (where status = 'closed_won') as won,
           count(*) filter (where status in ('closed_won','closed_lost')) as total
    from public.leads where owner_id = auth.uid()
  ) t;
$$;

create or replace function public.my_avg_cycle_days() returns numeric
language sql security definer set search_path = public as $$
  select coalesce(round(avg(extract(epoch from (closed_at - created_at)) / 86400), 1), 0)
  from public.leads where owner_id = auth.uid() and status = 'closed_won' and closed_at is not null;
$$;

create or replace function public.my_open_pipeline_value() returns numeric
language sql security definer set search_path = public as $$
  select coalesce(sum(value), 0) from public.leads
  where owner_id = auth.uid() and status = 'active' and stage in ('proposal_sent','negotiating') and value is not null;
$$;

create or replace function public.my_active_lead_count() returns integer
language sql security definer set search_path = public as $$
  select count(*)::int from public.leads where owner_id = auth.uid() and status = 'active';
$$;

create or replace function public.touch_leads_updated_at() returns trigger
language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;
create trigger leads_touch_updated_at before update on public.leads
for each row execute function public.touch_leads_updated_at();

alter table public.profiles enable row level security;
alter table public.pipeline_invites enable row level security;
alter table public.leads enable row level security;
alter table public.lead_notes enable row level security;
alter table public.lead_activity enable row level security;
alter table public.lead_appointments enable row level security;

-- Gated through is_pipeline_user()/is_pipeline_manager() (not blanket "authenticated") because
-- auth.users is shared across every StructTech app — a client-portal login must not see sales data.
create policy "pipeline_profiles_select" on public.profiles for select to authenticated using (is_pipeline_user());
create policy "pipeline_profiles_update_own" on public.profiles for update to authenticated using (id = auth.uid());

create policy "pipeline_invites_manage" on public.pipeline_invites for all to authenticated
  using (is_pipeline_manager()) with check (is_pipeline_manager());

create policy "leads_select" on public.leads for select to authenticated using (is_pipeline_user());
create policy "leads_insert" on public.leads for insert to authenticated with check (is_pipeline_user());
create policy "leads_update_owner_or_manager" on public.leads for update to authenticated
  using (is_pipeline_user() and (owner_id = auth.uid() or is_pipeline_manager()));

create policy "lead_notes_select" on public.lead_notes for select to authenticated using (is_pipeline_user());
create policy "lead_notes_insert" on public.lead_notes for insert to authenticated
  with check (is_pipeline_user() and author_id = auth.uid());

create policy "lead_activity_select" on public.lead_activity for select to authenticated using (is_pipeline_user());
create policy "lead_activity_insert" on public.lead_activity for insert to authenticated
  with check (is_pipeline_user() and actor_id = auth.uid());

create policy "lead_appointments_select" on public.lead_appointments for select to authenticated using (is_pipeline_user());
create policy "lead_appointments_manage" on public.lead_appointments for all to authenticated
  using (is_pipeline_user()) with check (is_pipeline_user());
