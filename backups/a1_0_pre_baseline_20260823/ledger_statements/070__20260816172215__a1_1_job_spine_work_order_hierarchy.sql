-- A1.1 — Job spine: jobs container + work order hierarchy
-- Directive §5.1 (Stage A1), decision D1.

alter table public.work_orders
  drop constraint if exists work_orders_estimate_id_key;

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

alter table public.work_orders
  alter column job_id set not null;

create unique index if not exists work_orders_one_master_per_job
  on public.work_orders (job_id)
  where kind = 'master';

comment on table public.jobs is
  'Job container (directive D1): one service address, one signed estimate. Parent of the master work order and its trade work orders.';
comment on column public.work_orders.kind is
  'master = carries production scope + homeowner sign-off; trade = issued to a crew, department, or external subcontractor.';
comment on column public.work_orders.predecessor_id is
  'A1.1 records the dependency as a field only. The sequencing engine is backlogged (§6.6).';
