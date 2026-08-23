-- BMR internal field-issue tickets, filed from Telegram by Isaac and the crew.
--
-- Deliberately NOT the existing public.tickets tables: those are the StructTech
-- helpdesk (note ticket_messages.is_structtech and tickets.org_id), i.e. BMR raising
-- an issue with StructTech about the platform. This is the opposite direction —
-- BMR's own people reporting what went wrong on a job — so it gets its own schema
-- rather than overloading the meaning of those columns.
--
-- Same lockdown as the agenda tables: RLS on, no policies, service role only.

create table if not exists public.bmr_ticket (
  id             bigserial primary key,
  org_id         uuid not null references public.organizations(id),
  job_id         uuid references public.jobs(id),
  address_text   text,
  title          text not null,
  detail         text,
  category       text not null default 'field',
  severity       text not null default 'decision',
  status         text not null default 'open',
  phase          smallint,
  reporter_tg_id bigint not null,
  reporter_label text   not null,
  assigned_tg_id bigint,
  resolved_at    timestamptz,
  resolved_by    bigint,
  resolution     text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint bmr_ticket_severity_ck check (severity in ('blocking','decision','fyi')),
  constraint bmr_ticket_status_ck   check (status in ('open','ack','resolved','closed')),
  constraint bmr_ticket_phase_ck    check (phase is null or (phase between 1 and 14)),
  -- A ticket must point at something: a real job row, or a typed address.
  constraint bmr_ticket_where_ck    check (job_id is not null or address_text is not null)
);
comment on table public.bmr_ticket is
  'Field issues raised by BMR staff and crew from Telegram. job_id links to a real job when one exists; address_text is the fallback because a job row only appears after a signed estimate, and the crew hits problems before that. severity: blocking (work stopped) / decision (needs Isaac) / fyi.';
comment on column public.bmr_ticket.phase is
  'Optional 1-14 phase from the locked production spine, so tickets can be analysed the same way the gap register is.';

create table if not exists public.bmr_ticket_message (
  id             bigserial primary key,
  ticket_id      bigint not null references public.bmr_ticket(id) on delete cascade,
  author_tg_id   bigint not null,
  author_label   text   not null,
  body           text   not null,
  created_at     timestamptz not null default now()
);
comment on table public.bmr_ticket_message is
  'Thread on a ticket. Every update is appended here rather than overwriting the ticket, so the history of a callback survives.';

create table if not exists public.bmr_ticket_photo (
  id               bigserial primary key,
  ticket_id        bigint not null references public.bmr_ticket(id) on delete cascade,
  file_id          text not null,
  file_unique_id   text,
  width            int,
  height           int,
  added_by         bigint,
  created_at       timestamptz not null default now()
);
comment on table public.bmr_ticket_photo is
  'Telegram file_id references, not image bytes. CompanyCam stays the photo system of record — these are evidence attached to a decision, deliberately not a second photo archive.';

create table if not exists public.bmr_ticket_manager (
  tg_user_id  bigint primary key,
  label       text not null,
  added_by    bigint,
  created_at  timestamptz not null default now()
);
comment on table public.bmr_ticket_manager is
  'Who works the queue: gets notified of new tickets and may change status, assign, comment as staff, and close. Anyone who has started the bot may FILE a ticket; only these people may resolve one.';

create index if not exists bmr_ticket_status_idx   on public.bmr_ticket (status, created_at desc);
create index if not exists bmr_ticket_job_idx      on public.bmr_ticket (job_id);
create index if not exists bmr_ticket_reporter_idx on public.bmr_ticket (reporter_tg_id, created_at desc);
create index if not exists bmr_ticket_message_idx  on public.bmr_ticket_message (ticket_id, created_at);
create index if not exists bmr_ticket_photo_idx    on public.bmr_ticket_photo (ticket_id);

create or replace function public.bmr_ticket_touch() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists bmr_ticket_touch_trg on public.bmr_ticket;
create trigger bmr_ticket_touch_trg before update on public.bmr_ticket
  for each row execute function public.bmr_ticket_touch();

alter table public.bmr_ticket         enable row level security;
alter table public.bmr_ticket_message enable row level security;
alter table public.bmr_ticket_photo   enable row level security;
alter table public.bmr_ticket_manager enable row level security;

revoke all on public.bmr_ticket         from anon, authenticated;
revoke all on public.bmr_ticket_message from anon, authenticated;
revoke all on public.bmr_ticket_photo   from anon, authenticated;
revoke all on public.bmr_ticket_manager from anon, authenticated;

-- Seed the queue: Jacob is already known from the agenda bot. Isaac gets added the
-- moment he starts the bot (see the roster command), since Telegram will not let a
-- bot message anyone who has not messaged it first.
insert into public.bmr_ticket_manager (tg_user_id, label, added_by)
values (588808800, 'Jacob Walker', 588808800)
on conflict (tg_user_id) do nothing;
