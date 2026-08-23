-- Telegram agenda-card bot. Self-contained, namespaced tg_agenda_*, and reachable
-- only by the service role: RLS is on with no policies, so anon/authenticated get
-- nothing. Nothing here touches the StructTech OS tables.

create table if not exists public.tg_agenda_session (
  chat_id     bigint primary key,
  tg_user_id  bigint not null,
  step        text   not null default 'idle',
  draft       jsonb  not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);
comment on table public.tg_agenda_session is
  'One in-flight agenda conversation per Telegram chat. step drives the question the bot asks next; draft accumulates the answers. Rows are disposable — clearing one just cancels the build.';

create table if not exists public.tg_agenda_sender (
  tg_user_id  bigint primary key,
  label       text,
  added_by    bigint,
  created_at  timestamptz not null default now()
);
comment on table public.tg_agenda_sender is
  'Send allowlist. Anyone may build and download a card; only these Telegram user ids may push one to the group or to contacts. Seeded with the first user to run /claim while the table is empty.';

create table if not exists public.tg_agenda_contact (
  id          bigserial primary key,
  tg_user_id  bigint unique,
  username    text,
  label       text not null,
  active      boolean not null default false,
  added_by    bigint,
  created_at  timestamptz not null default now()
);
comment on table public.tg_agenda_contact is
  'People who can be DMed an approved card. Telegram forbids a bot messaging anyone who has not started it, so rows are created when a person runs /start — they cannot be added by handle. active is flipped on by a sender via /contacts.';

create table if not exists public.tg_agenda_group (
  chat_id     bigint primary key,
  title       text,
  active      boolean not null default true,
  added_by    bigint,
  created_at  timestamptz not null default now()
);
comment on table public.tg_agenda_group is
  'Group chats the bot posts approved cards into. Populated when the bot is added to a group.';

create table if not exists public.tg_agenda_card (
  id           bigserial primary key,
  created_by   bigint,
  chat_id      bigint,
  payload      jsonb  not null,
  delivered_to jsonb  not null default '[]'::jsonb,
  created_at   timestamptz not null default now()
);
comment on table public.tg_agenda_card is
  'History of built cards. payload is the exact CardData used, so any card can be re-rendered or reused as a template.';

create table if not exists public.tg_agenda_update (
  update_id  bigint primary key,
  seen_at    timestamptz not null default now()
);
comment on table public.tg_agenda_update is
  'Idempotency guard. Telegram retries a webhook until it gets a 200, so every update_id is claimed once before any side effect runs.';

create index if not exists tg_agenda_session_updated_idx on public.tg_agenda_session (updated_at);
create index if not exists tg_agenda_card_created_idx    on public.tg_agenda_card (created_at desc);
create index if not exists tg_agenda_update_seen_idx     on public.tg_agenda_update (seen_at);

alter table public.tg_agenda_session enable row level security;
alter table public.tg_agenda_sender  enable row level security;
alter table public.tg_agenda_contact enable row level security;
alter table public.tg_agenda_group   enable row level security;
alter table public.tg_agenda_card    enable row level security;
alter table public.tg_agenda_update  enable row level security;

revoke all on public.tg_agenda_session from anon, authenticated;
revoke all on public.tg_agenda_sender  from anon, authenticated;
revoke all on public.tg_agenda_contact from anon, authenticated;
revoke all on public.tg_agenda_group   from anon, authenticated;
revoke all on public.tg_agenda_card    from anon, authenticated;
revoke all on public.tg_agenda_update  from anon, authenticated;
