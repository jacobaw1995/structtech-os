-- Hardening pass after an adversarial review of the bot.
--
-- 1. Sessions were keyed by chat_id alone. In a shared group chat that let one
--    person's draft replace another's between the preview and the approval tap,
--    so a sender could broadcast a card they never saw. Key by (chat_id, user).
alter table public.tg_agenda_session drop constraint if exists tg_agenda_session_pkey;
alter table public.tg_agenda_session
  add constraint tg_agenda_session_pkey primary key (chat_id, tg_user_id);
comment on table public.tg_agenda_session is
  'One in-flight agenda conversation per (chat, person). Keyed by both so two people building in the same group chat cannot overwrite each other, and so a callback can only ever act on its own author''s draft.';

-- 2. Being added to a group made it an immediate broadcast target, and re-adding
--    the bot silently re-enabled a group a sender had switched off. Groups now
--    arrive switched off and a sender turns them on with /groups.
alter table public.tg_agenda_group alter column active set default false;
comment on column public.tg_agenda_group.active is
  'Off until a sender enables it via /groups. Anyone can add the bot to a group; that must not be enough to start receiving cards.';

-- 3. Any sender could remove the person who added them. Mark the original claimer
--    so only they can remove other senders.
alter table public.tg_agenda_sender add column if not exists owner boolean not null default false;
comment on column public.tg_agenda_sender.owner is
  'True for the first person to /claim. Only the owner may remove other senders.';
