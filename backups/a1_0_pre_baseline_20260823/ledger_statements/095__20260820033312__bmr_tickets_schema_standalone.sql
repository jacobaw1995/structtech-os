-- BMR field tickets, standalone.
--
-- Lives in its own Postgres schema, deliberately NOT in `public` where StructTech OS
-- lives. Nothing here references a public table: the whole schema can be dropped with
-- `drop schema bmr_tickets cascade` without touching anything else.
--
-- Job linkage is denormalised on purpose. `job_label` (the address, always present) is
-- what people read; `job_ref` is an optional external id for when this is wired to the
-- BMR tenant data later. You cannot foreign-key across databases, and even in the same
-- database a hard FK would couple the two systems — this keeps the future connection a
-- config change rather than a migration.

create schema if not exists bmr_tickets;
comment on schema bmr_tickets is
  'Standalone BMR field-ticket system driven by its own Telegram bot. Isolated from public/StructTech OS by design; safe to drop wholesale.';

create table if not exists bmr_tickets.ticket (
  id             bigserial primary key,
  job_ref        text,
  job_label      text   not null,
  title          text   not null,
  severity       text   not null default 'decision',
  status         text   not null default 'open',
  phase          smallint,
  reporter_tg_id bigint not null,
  reporter_label text   not null,
  topic_id       bigint,
  resolution     text,
  resolved_at    timestamptz,
  resolved_by    bigint,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint ticket_severity_ck check (severity in ('blocking','decision','fyi')),
  constraint ticket_status_ck   check (status in ('open','ack','resolved')),
  constraint ticket_phase_ck    check (phase is null or (phase between 1 and 14))
);
comment on column bmr_tickets.ticket.topic_id is
  'message_thread_id of this ticket''s forum topic in the BMR Tickets group. Null if the topic could not be created (the bot still files the ticket).';
comment on column bmr_tickets.ticket.job_ref is
  'Optional external job id. Empty until the bot is wired to the BMR tenant data.';

create table if not exists bmr_tickets.comment (
  id           bigserial primary key,
  ticket_id    bigint not null references bmr_tickets.ticket(id) on delete cascade,
  author_tg_id bigint not null,
  author_label text   not null,
  body         text   not null,
  source       text   not null default 'topic',
  created_at   timestamptz not null default now()
);
comment on table bmr_tickets.comment is
  'Ticket thread. source=topic means somebody simply talked in the ticket''s forum topic and the bot recorded it — that is the primary way comments arrive.';

create table if not exists bmr_tickets.photo (
  id             bigserial primary key,
  ticket_id      bigint not null references bmr_tickets.ticket(id) on delete cascade,
  file_id        text not null,
  file_unique_id text,
  added_by       bigint,
  created_at     timestamptz not null default now()
);
comment on table bmr_tickets.photo is
  'Telegram file_id references, not image bytes. CompanyCam stays the photo system of record.';

create table if not exists bmr_tickets.person (
  tg_user_id bigint primary key,
  label      text not null,
  username   text,
  lang       text,
  is_manager boolean not null default false,
  created_at timestamptz not null default now()
);
comment on table bmr_tickets.person is
  'Anyone who has started the bot. is_manager = works the queue: notified, and may resolve. Telegram will not let a bot message someone who has not started it, so this fills up by people running /start.';

create table if not exists bmr_tickets.setting (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);
comment on table bmr_tickets.setting is
  'Singleton config. group_chat_id holds the BMR Tickets forum group the bot posts into.';

create table if not exists bmr_tickets.session (
  chat_id    bigint not null,
  tg_user_id bigint not null,
  step       text   not null,
  draft      jsonb  not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (chat_id, tg_user_id)
);
comment on table bmr_tickets.session is
  'One in-flight conversation per (chat, person) — keyed by both so two people in the same chat cannot overwrite each other. This lesson was learned the hard way on the agenda bot.';

create table if not exists bmr_tickets.seen_update (
  update_id bigint primary key,
  seen_at   timestamptz not null default now()
);

create index if not exists ticket_status_idx  on bmr_tickets.ticket (status, created_at desc);
create index if not exists ticket_topic_idx   on bmr_tickets.ticket (topic_id);
create index if not exists ticket_reporter_idx on bmr_tickets.ticket (reporter_tg_id, created_at desc);
create index if not exists comment_ticket_idx on bmr_tickets.comment (ticket_id, created_at);
create index if not exists photo_ticket_idx   on bmr_tickets.photo (ticket_id);

create or replace function bmr_tickets.touch() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists ticket_touch_trg on bmr_tickets.ticket;
create trigger ticket_touch_trg before update on bmr_tickets.ticket
  for each row execute function bmr_tickets.touch();

-- The schema is reached only by the edge function over a direct Postgres connection,
-- never through PostgREST, so the API surface of the project is unchanged.
revoke all on schema bmr_tickets from anon, authenticated;
revoke all on all tables in schema bmr_tickets from anon, authenticated;
