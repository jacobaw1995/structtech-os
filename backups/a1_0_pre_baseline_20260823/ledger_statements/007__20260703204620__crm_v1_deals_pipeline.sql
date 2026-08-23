-- ============================================================
-- STRUCTTECH OS CRM v1 — internal sales pipeline
-- ============================================================

create table if not exists public.deals (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid references public.audit_leads(id),
  contact_name text not null,
  company text,
  email text,
  phone text,
  trade text,
  crew_size int,
  value int,                          -- proposal/deal value in dollars
  stage text not null default 'new_scan'
    check (stage in ('new_scan','contacted','call_booked','call_done','proposal_sent','negotiating','closed_won','closed_lost')),
  lost_reason text,
  source text default 'scan',         -- scan | referral | manual | network
  proposal_tier text,
  proposal_notes text,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.deal_notes (
  id uuid primary key default gen_random_uuid(),
  deal_id uuid not null references public.deals(id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.deal_activity (
  id uuid primary key default gen_random_uuid(),
  deal_id uuid not null references public.deals(id) on delete cascade,
  action text not null,               -- created | stage_changed | value_set | note_added | followup_scheduled | followup_cancelled
  from_value text,
  to_value text,
  created_at timestamptz not null default now()
);

create table if not exists public.follow_ups (
  id uuid primary key default gen_random_uuid(),
  deal_id uuid not null references public.deals(id) on delete cascade,
  send_at timestamptz not null,
  subject text not null,
  body text not null,
  to_email text not null,
  status text not null default 'pending' check (status in ('pending','sent','cancelled')),
  sent_at timestamptz,
  created_at timestamptz not null default now()
);

-- RLS (consistent with current anon model; tighten at Auth phase)
alter table public.deals enable row level security;
alter table public.deal_notes enable row level security;
alter table public.deal_activity enable row level security;
alter table public.follow_ups enable row level security;
create policy "anon all deals" on public.deals for all to anon using (true) with check (true);
create policy "anon all deal_notes" on public.deal_notes for all to anon using (true) with check (true);
create policy "anon all deal_activity" on public.deal_activity for all to anon using (true) with check (true);
create policy "anon all follow_ups" on public.follow_ups for all to anon using (true) with check (true);

-- ============================================================
-- Automation: scan -> deal + follow-up sequence
-- ============================================================
create or replace function public.auto_create_deal()
returns trigger language plpgsql security definer as $$
declare d_id uuid;
begin
  insert into public.deals (lead_id, contact_name, company, email, trade, crew_size, stage, source)
  values (new.id, coalesce(new.name,'—'), new.company, new.email, new.trade, new.crew_size, 'new_scan', 'scan')
  returning id into d_id;

  insert into public.deal_activity (deal_id, action, to_value) values (d_id, 'created', 'from scan');

  -- follow-up sequence (only if we have an email)
  if new.email is not null and new.email like '%@%' then
    insert into public.follow_ups (deal_id, send_at, to_email, subject, body) values
    (d_id, now() + interval '2 days', new.email,
     'Quick question about your Revenue Leak Report, ' || coalesce(split_part(new.name,' ',1),'') ,
     'Hey ' || coalesce(split_part(new.name,' ',1),'there') || E',\n\nJacob here from StructTech. Your scan flagged about $' || coalesce(new.monthly_leak,0) || E'/month leaking out of your operation — did the report line up with what you''re seeing day to day?\n\nIf you want to walk through it live, grab 30 minutes here: structtek.com/operational-audit\n\nNo pitch — just your numbers.\n\nJacob Walker\nStructTech LLC · 937.467.2660'),
    (d_id, now() + interval '5 days', new.email,
     'The ' || coalesce(new.trade,'contractor') || ' math on $' || coalesce(new.monthly_leak,0) || '/month',
     'Hey ' || coalesce(split_part(new.name,' ',1),'there') || E',\n\nLast note from me. That $' || coalesce(new.monthly_leak,0) || E'/month your scan surfaced doesn''t fix itself — it compounds. Most crews your size get the first system live inside 30 days.\n\nIf now''s not the time, no sweat. If it is: structtek.com/operational-audit\n\nJacob');
    insert into public.deal_activity (deal_id, action, to_value) values (d_id, 'followup_scheduled', 'day-2 + day-5');
  end if;

  return new;
end $$;

drop trigger if exists trg_auto_deal on public.audit_leads;
create trigger trg_auto_deal
  after insert on public.audit_leads
  for each row execute function public.auto_create_deal();

-- Cancel pending follow-ups when the prospect engages (stage advances past contacted)
create or replace function public.deal_stage_side_effects()
returns trigger language plpgsql security definer as $$
begin
  if new.stage <> old.stage then
    insert into public.deal_activity (deal_id, action, from_value, to_value)
    values (new.id, 'stage_changed', old.stage, new.stage);

    if new.stage in ('call_booked','call_done','proposal_sent','negotiating','closed_won','closed_lost') then
      update public.follow_ups set status = 'cancelled'
      where deal_id = new.id and status = 'pending';
    end if;

    if new.stage in ('closed_won','closed_lost') then
      new.closed_at := now();
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists trg_deal_stage on public.deals;
create trigger trg_deal_stage
  before update on public.deals
  for each row execute function public.deal_stage_side_effects();

-- ============================================================
-- Backfill: existing real leads become deals (skip tests)
-- ============================================================
insert into public.deals (lead_id, contact_name, company, email, trade, crew_size, stage, source, created_at)
select l.id, coalesce(l.name,'—'), l.company, l.email, l.trade, l.crew_size, 'new_scan', 'scan', l.created_at
from public.audit_leads l
where not exists (select 1 from public.deals d where d.lead_id = l.id);

-- Storage bucket for deal files
insert into storage.buckets (id, name, public)
values ('deal-files', 'deal-files', false)
on conflict (id) do nothing;

create policy "anon deal files all" on storage.objects
  for all to anon using (bucket_id = 'deal-files') with check (bucket_id = 'deal-files');
