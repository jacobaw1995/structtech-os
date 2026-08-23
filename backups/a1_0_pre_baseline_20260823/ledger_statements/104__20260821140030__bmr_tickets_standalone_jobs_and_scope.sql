-- Scope note, deliberately recorded in the database itself.
comment on schema bmr_tickets is
  'TEMPORARY / TRANSITIONAL. Standalone BMR field-ticket system run entirely from its own Telegram bot, in place only until the StructTech OS ticketing module is ready. It reads and writes NOTHING outside this schema: no jobs, organizations, deals or any other public/StructTech OS table, and it never creates projects or rows in the BMR tenant account. Safe to drop wholesale with `drop schema bmr_tickets cascade` when the OS takes over.';

-- The bot keeps its own list of job sites rather than reading public.jobs. That is
-- what makes it genuinely standalone: no cross-schema reads, no coupling to the tenant
-- data, and nothing to untangle when the OS takes over. ticket.job_ref stays empty
-- until then and is the seam for backfilling real job ids later.
create table if not exists bmr_tickets.job (
  id         bigserial primary key,
  label      text not null,
  job_ref    text,
  active     boolean not null default true,
  added_by   bigint,
  created_at timestamptz not null default now()
);
comment on table bmr_tickets.job is
  'Job sites this bot knows about, typed in by a manager. Deliberately NOT a view over public.jobs — see the schema comment. job_ref is the future link to a real StructTech OS job id.';

create unique index if not exists job_label_uniq on bmr_tickets.job (lower(label));
create index if not exists job_active_idx on bmr_tickets.job (active, created_at desc);

-- ticket.job_label is denormalised on purpose: a ticket keeps the address it was filed
-- against even if the job list is later renamed or archived.
alter table bmr_tickets.ticket
  add column if not exists job_id bigint references bmr_tickets.job(id) on delete set null;

comment on column bmr_tickets.ticket.job_id is
  'Optional link to this schema''s own job list. Null when the reporter typed a one-off address.';
