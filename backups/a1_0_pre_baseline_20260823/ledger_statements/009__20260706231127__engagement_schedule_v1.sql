
-- Buildout schedule feature: normalized engagement/level/milestone/check-in tables.
-- Materialized from client_roadmaps JSONB at closed_won (see create_engagement_from_roadmap RPC, next migration).

create table public.engagements (
  id                uuid primary key default gen_random_uuid(),
  deal_id           uuid not null references public.deals(id),
  roadmap_id        uuid references public.client_roadmaps(id),
  org_id            uuid references public.organizations(id),
  start_date        date,
  target_end_date   date,
  status            text not null default 'active' check (status = any (array['active','paused','complete'])),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (deal_id)
);

create table public.engagement_levels (
  id                    uuid primary key default gen_random_uuid(),
  engagement_id         uuid not null references public.engagements(id) on delete cascade,
  org_id                uuid references public.organizations(id),
  level_no              int not null,
  title                 text not null,
  why                   text,
  area                  text,
  sort_order            int not null default 0,
  depends_on_level_id   uuid references public.engagement_levels(id),
  planned_start         date,
  planned_end           date,
  actual_start          date,
  actual_end            date,
  status                text not null default 'not_started' check (status = any (array['not_started','in_progress','blocked','complete'])),
  created_at            timestamptz not null default now(),
  unique (engagement_id, level_no)
);

create table public.engagement_milestones (
  id                uuid primary key default gen_random_uuid(),
  level_id          uuid not null references public.engagement_levels(id) on delete cascade,
  org_id            uuid references public.organizations(id),
  owner             text not null check (owner = any (array['jacob','client'])),
  body              text not null,
  is_win_condition  boolean not null default false,
  sort_order        int not null default 0,
  status            text not null default 'open' check (status = any (array['open','complete'])),
  completed_at      timestamptz,
  created_at        timestamptz not null default now()
);

create table public.engagement_checkins (
  id             uuid primary key default gen_random_uuid(),
  engagement_id  uuid not null references public.engagements(id) on delete cascade,
  level_id       uuid references public.engagement_levels(id) on delete set null,
  org_id         uuid references public.organizations(id),
  title          text not null,
  scheduled_at   timestamptz not null,
  status         text not null default 'scheduled' check (status = any (array['scheduled','done','missed','rescheduled'])),
  notes          text,
  created_at     timestamptz not null default now()
);

create index engagements_org_id_idx on public.engagements(org_id);
create index engagement_levels_engagement_id_idx on public.engagement_levels(engagement_id);
create index engagement_levels_org_id_idx on public.engagement_levels(org_id);
create index engagement_milestones_level_id_idx on public.engagement_milestones(level_id);
create index engagement_milestones_org_id_idx on public.engagement_milestones(org_id);
create index engagement_checkins_engagement_id_idx on public.engagement_checkins(engagement_id);
create index engagement_checkins_org_id_idx on public.engagement_checkins(org_id);

alter table public.engagements enable row level security;
alter table public.engagement_levels enable row level security;
alter table public.engagement_milestones enable row level security;
alter table public.engagement_checkins enable row level security;

-- Admin (anon key + soft password gate) keeps full access, matching every other table in this schema today.
create policy "anon all engagements" on public.engagements for all to anon using (true) with check (true);
create policy "anon all engagement_levels" on public.engagement_levels for all to anon using (true) with check (true);
create policy "anon all engagement_milestones" on public.engagement_milestones for all to anon using (true) with check (true);
create policy "anon all engagement_checkins" on public.engagement_checkins for all to anon using (true) with check (true);

-- Client portal (real Supabase Auth): read-only view of their own org's engagement/schedule.
create policy "member read own engagements" on public.engagements for select to authenticated using (org_id in (select my_org_ids()));
create policy "member read own engagement_levels" on public.engagement_levels for select to authenticated using (org_id in (select my_org_ids()));
create policy "member read own engagement_milestones" on public.engagement_milestones for select to authenticated using (org_id in (select my_org_ids()));
create policy "member read own engagement_checkins" on public.engagement_checkins for select to authenticated using (org_id in (select my_org_ids()));

-- Client can self-report completion of their own milestones, same behavior as today's JSONB roadmap ticking.
create policy "member update own client milestones" on public.engagement_milestones for update to authenticated
  using (org_id in (select my_org_ids()) and owner = 'client')
  with check (org_id in (select my_org_ids()) and owner = 'client');
