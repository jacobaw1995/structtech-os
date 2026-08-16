-- A1.1 — Job spine: jobs container + work order hierarchy
-- Directive §5.1 (Stage A1), decision D1.
--
-- APPLIED VIA MCP apply_migration. Never `supabase db push` / `db reset` on this
-- project until the A1.0 baseline reset is done — 46 stale local files would be
-- replayed against production (§4.7).
--
-- PRODUCTION NOTE — CLAUDE.md migration rule 5b (deployed-UI compatibility):
--   Setting work_orders.job_id NOT NULL breaks the currently-deployed RPC
--   create_work_order_from_estimate, which inserts (org_id, estimate_id) only.
--   A1.2 replaces it with create_job_from_estimate + create_trade_work_order.
--   Until A1.2 ships, work-order creation through the deployed UI will fail.
--   Accepted deliberately: A1.1's "Done when" requires job_id NOT NULL, and
--   coordination is at zero rows beyond the 2 existing work orders (§4.2).

-- 1 · Drop one-work-order-per-estimate. This is the blocking fact in §4.4 and
--     the first statement of the first Phase A migration.
alter table public.work_orders
  drop constraint if exists work_orders_estimate_id_key;

-- 2 · jobs — the container. D1: one service address, one signed estimate.
create table if not exists public.jobs (
  id                     uuid primary key default gen_random_uuid(),
  org_id                 uuid not null references public.organizations(id),
  deal_id                uuid not null references public.deals(id),
  estimate_id            uuid not null references public.estimates(id),
  service_address_street text,
  service_address_city   text,
  service_address_state  text,
  service_address_zip    text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create index if not exists jobs_org_id_idx      on public.jobs (org_id);
create index if not exists jobs_deal_id_idx     on public.jobs (deal_id);
create index if not exists jobs_estimate_id_idx on public.jobs (estimate_id);

alter table public.jobs enable row level security;

-- RLS mirrors work_orders exactly: org scoping via the my_org_ids() helper.
-- Never subquery org_members directly in a policy (infinite recursion).
drop policy if exists "member read own jobs"   on public.jobs;
drop policy if exists "member insert own jobs" on public.jobs;
drop policy if exists "member update own jobs" on public.jobs;

create policy "member read own jobs" on public.jobs
  for select using (org_id in (select my_org_ids()));

create policy "member insert own jobs" on public.jobs
  for insert with check (org_id in (select my_org_ids()));

create policy "member update own jobs" on public.jobs
  for update using (org_id in (select my_org_ids()))
          with check (org_id in (select my_org_ids()));

-- 3 · work_orders gains the hierarchy.
--     kind keeps DEFAULT 'master' on purpose: the deployed RPC does not supply
--     it, and today's one-work-order-per-estimate rows are conceptually masters.
alter table public.work_orders
  add column if not exists job_id         uuid references public.jobs(id),
  add column if not exists kind           text not null default 'master',
  add column if not exists trade          text,
  add column if not exists assignee_type  text,
  add column if not exists assignee_ref   text,
  add column if not exists predecessor_id uuid references public.work_orders(id);

alter table public.work_orders
  drop constraint if exists work_orders_kind_check;
alter table public.work_orders
  add constraint work_orders_kind_check
    check (kind in ('master', 'trade'));

alter table public.work_orders
  drop constraint if exists work_orders_assignee_type_check;
alter table public.work_orders
  add constraint work_orders_assignee_type_check
    check (assignee_type is null
           or assignee_type in ('crew', 'department', 'subcontractor'));

create index if not exists work_orders_job_id_idx
  on public.work_orders (job_id);
create index if not exists work_orders_predecessor_id_idx
  on public.work_orders (predecessor_id);

-- 4 · Backfill: derive one job per existing work order from its estimate.
--     Keyed on work_order id so it stays correct even if two work orders were
--     ever to share an estimate.
with derived as (
  select
    wo.id                        as wo_id,
    gen_random_uuid()            as new_job_id,
    wo.org_id                    as org_id,
    e.deal_id                    as deal_id,
    e.id                         as estimate_id,
    d.service_address_street     as street,
    d.service_address_city       as city,
    d.service_address_state      as state,
    d.service_address_zip        as zip
  from public.work_orders wo
  join public.estimates e on e.id = wo.estimate_id
  left join public.deals d on d.id = e.deal_id
  where wo.job_id is null
),
inserted as (
  insert into public.jobs (
    id, org_id, deal_id, estimate_id,
    service_address_street, service_address_city,
    service_address_state, service_address_zip
  )
  select new_job_id, org_id, deal_id, estimate_id, street, city, state, zip
  from derived
  returning id
)
update public.work_orders wo
set job_id = derived.new_job_id,
    kind   = 'master'
from derived
where wo.id = derived.wo_id;

-- 5 · Every work order now belongs to a job.
alter table public.work_orders
  alter column job_id set not null;

-- 6 · One master per job.
create unique index if not exists work_orders_one_master_per_job
  on public.work_orders (job_id)
  where kind = 'master';

comment on table public.jobs is
  'Job container (directive D1): one service address, one signed estimate. Parent of the master work order and its trade work orders.';
comment on column public.work_orders.kind is
  'master = carries production scope + homeowner sign-off; trade = issued to a crew, department, or external subcontractor.';
comment on column public.work_orders.predecessor_id is
  'A1.1 records the dependency as a field only. The sequencing engine is backlogged (§6.6).';
