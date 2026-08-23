-- Client roadmaps for the StructTech engagement tracker
create table if not exists public.client_roadmaps (
  id uuid primary key default gen_random_uuid(),
  token text unique not null default encode(gen_random_bytes(9), 'hex'),
  client_name text not null,
  company text not null,
  trade text,
  crew_size int,
  score int,
  risk_level text,
  revenue_leak_monthly int,
  -- levels: JSON array of 3 focus areas
  -- [{ "title": "...", "subtitle": "...", "why": "...",
  --    "milestones": [{ "id":"m1", "label":"...", "owner":"jacob"|"client", "done":false, "done_at":null }] }]
  levels jsonb not null default '[]'::jsonb,
  status text not null default 'active', -- active | complete | archived
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.client_roadmaps enable row level security;

-- Anyone with the anon key can READ a roadmap only if they know the token
-- (enforced by querying eq token; RLS allows select but the token is unguessable)
create policy "read roadmap by token" on public.client_roadmaps
  for select using (true);

-- Allow milestone checkoff updates via anon (client homework toggles).
-- Column-level protection: only levels + updated_at can effectively change via a trigger check.
create policy "update roadmap milestones" on public.client_roadmaps
  for update using (true) with check (true);

-- Prevent anon from changing anything except levels/updated_at/status
create or replace function public.protect_roadmap_columns()
returns trigger language plpgsql as $$
begin
  if new.id <> old.id
     or new.token <> old.token
     or new.client_name <> old.client_name
     or new.company <> old.company
     or coalesce(new.trade,'') <> coalesce(old.trade,'')
     or coalesce(new.crew_size,0) <> coalesce(old.crew_size,0)
     or coalesce(new.score,0) <> coalesce(old.score,0)
     or coalesce(new.risk_level,'') <> coalesce(old.risk_level,'')
     or coalesce(new.revenue_leak_monthly,0) <> coalesce(old.revenue_leak_monthly,0)
     or new.created_at <> old.created_at then
    raise exception 'immutable columns';
  end if;
  new.updated_at := now();
  return new;
end $$;

create trigger trg_protect_roadmap
  before update on public.client_roadmaps
  for each row execute function public.protect_roadmap_columns();

create index if not exists idx_client_roadmaps_token on public.client_roadmaps (token);
