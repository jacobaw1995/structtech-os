-- A4.6 CREW MODEL — THE SPINE. Track S · 2026-09-15.
-- Rollback: supabase/rollbacks/20260915_crew_model_spine_rollback.sql
--
-- THE SHAPE IS THE MODULE'S OWN, read from roadmap_items 49f1764c ("Cross-job crew Gantt", Jacob 7/27):
-- "individuals now → people→crews → crews→work orders. Multiple work orders per JOB (different crews per
-- task: tear-off/install/gutters) — do NOT hard-wire 1 WO per estimate; a job groups work orders."
-- And 75d8a6e5 (this item): "No one has a vehicle is why crews cannot split. A scheduler that ignores this
-- produces impossible plans."
--
-- BEFORE-MEASUREMENT (live, 2026-09-15):
--   · org_members: 5 memberships, 3 distinct people, all 3 with an auth login (BMR: 2, both with logins).
--     ZERO crew people exist anywhere — there is no table for a person who is not a login.
--   · work_orders: 3 (2 master, 1 trade); assignee_type NULL on all 3, assignee_ref NULL on all 3.
--   · Crew is free text in two places: schedule_blocks.crew_name (1 row, "TRACK S · acceptance crew") and
--     check_ins.crew_name (0 rows). Neither is touched here; they are named for the next step.
--
-- THE CONDITIONS, AND HOW THIS MEETS THEM
--   1. A PERSON MAY OR MAY NOT HAVE A LOGIN. crew_people.user_id is nullable; when set it must be a member
--      of the SAME tenant (composite FK to org_members), and one login is one person per tenant.
--   2. LANGUAGE IS DATA. crew_people.preferred_language is a language tag the field surface can read
--      (en, es, pt-BR …), NULL when not recorded. Bilingual content (A3.4, November) reads it; nothing here
--      translates anything, and nothing needs rebuilding to add languages.
--   3. AVAILABILITY IS A STATE, NOT A BLOCK. Unavailability is recorded per person as date windows. The view
--      crew_assignment_states says, per crew on a work order and per scheduled block, how many of its people
--      are unavailable and whether the crew has transport. NOTHING REFUSES A SCHEDULE OR AN ASSIGNMENT.
--   4. REACHABLE FROM THE TABLE. Tenant consistency is composite foreign keys (a crew, a person and a
--      membership cannot straddle tenants); the work-order rule (a live trade in the same tenant) is a
--      trigger; date order and tag shape are CHECKs. None of it lives only in a function.
--   5. The before-measurement is above.
--
-- COLLAPSED STATE, DESIGNED OUT (9/12 sweep): has_vehicle and skills are NULLABLE — NULL is "not recorded",
-- false / '{}' is "recorded as none". A default of false would have told the scheduler "no vehicle" about
-- every person nobody had asked.
--
-- CONFLICT WITH §5 A4.6's "Done when", NOT RESOLVED HERE: it reads "the scheduler REFUSES to assign a crew
-- with no vehicle to a job requiring transport". Condition 3 (and SCOPE §2.8) say a state, not a block.
-- This spine records vehicle_state; it refuses nothing, and "a job requiring transport" is not modelled.
-- Needs a ruling: refusal as tenant-configured enforcement (default off, like enforce_stage_gating), or the
-- clause amended.

-- ---------------------------------------------------------------------------------------------
-- 1. People
-- ---------------------------------------------------------------------------------------------
create table public.crew_people (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  full_name text not null,
  user_id uuid null,
  phone text null,
  preferred_language text null,
  skills text[] null,
  has_vehicle boolean null,
  vehicle_note text null,
  archived_at timestamptz null,
  created_by uuid null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint crew_people_id_org_key unique (id, org_id),
  constraint crew_people_name_not_blank check (btrim(full_name) <> ''),
  constraint crew_people_language_tag check (preferred_language is null or preferred_language ~ '^[a-z]{2,3}(-[A-Z]{2})?$'),
  constraint crew_people_member_login foreign key (org_id, user_id)
    references public.org_members(org_id, user_id) on delete set null (user_id)
);
create unique index crew_people_one_person_per_login on public.crew_people (org_id, user_id) where user_id is not null;
create index crew_people_org_idx on public.crew_people (org_id);

comment on column public.crew_people.user_id is 'The login this person uses, if any. NULL = a crew member without an account. Must be a member of the same tenant.';
comment on column public.crew_people.preferred_language is 'Language tag the field surface reads (en, es, pt-BR). NULL = not recorded. Data, not a display preference.';
comment on column public.crew_people.has_vehicle is 'NULL = not recorded; false = recorded as no vehicle. Never defaulted.';
comment on column public.crew_people.skills is 'NULL = not recorded; {} = recorded as none. Free text per tenant, like work_orders.trade.';

-- ---------------------------------------------------------------------------------------------
-- 2. Crews and membership
-- ---------------------------------------------------------------------------------------------
create table public.crews (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  name text not null,
  archived_at timestamptz null,
  created_by uuid null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint crews_id_org_key unique (id, org_id),
  constraint crews_name_not_blank check (btrim(name) <> '')
);
create unique index crews_live_name_per_org on public.crews (org_id, lower(btrim(name))) where archived_at is null;

create table public.crew_memberships (
  crew_id uuid not null,
  person_id uuid not null,
  org_id uuid not null,
  is_lead boolean not null default false,
  created_by uuid null,
  created_at timestamptz not null default now(),
  primary key (crew_id, person_id),
  constraint crew_memberships_crew foreign key (crew_id, org_id) references public.crews(id, org_id) on delete cascade,
  constraint crew_memberships_person foreign key (person_id, org_id) references public.crew_people(id, org_id) on delete cascade
);
create index crew_memberships_person_idx on public.crew_memberships (person_id);

-- ---------------------------------------------------------------------------------------------
-- 3. Availability — recorded windows, never a gate
-- ---------------------------------------------------------------------------------------------
create table public.crew_person_unavailability (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  person_id uuid not null,
  starts_on date not null,
  ends_on date not null,
  reason text null,
  created_by uuid null,
  created_at timestamptz not null default now(),
  constraint crew_person_unavailability_person foreign key (person_id, org_id) references public.crew_people(id, org_id) on delete cascade,
  constraint crew_person_unavailability_order check (ends_on >= starts_on)
);
create index crew_person_unavailability_person_idx on public.crew_person_unavailability (person_id, starts_on, ends_on);

-- ---------------------------------------------------------------------------------------------
-- 4. Crews onto trade work orders — many crews per work order, many work orders per job
-- ---------------------------------------------------------------------------------------------
create table public.work_order_crew_assignments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  crew_id uuid not null,
  task text null,
  created_by uuid null,
  created_at timestamptz not null default now(),
  constraint work_order_crew_assignments_crew foreign key (crew_id, org_id) references public.crews(id, org_id) on delete cascade,
  constraint work_order_crew_assignments_one_per_crew unique (work_order_id, crew_id)
);
create index work_order_crew_assignments_crew_idx on public.work_order_crew_assignments (crew_id);

comment on column public.work_order_crew_assignments.task is 'What this crew does on this work order (tear-off, install, gutters). Free text. NULL = not stated.';

create function public.work_order_crew_assignments_validate()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
declare v_org uuid; v_kind text; v_voided timestamptz;
begin
  -- RULE 8 / RULE 10: a write that moves neither the work order nor the crew is not re-validated.
  if tg_op = 'UPDATE' and new.work_order_id is not distinct from old.work_order_id
     and new.org_id is not distinct from old.org_id then
    return new;
  end if;
  select org_id, kind, voided_at into v_org, v_kind, v_voided from public.work_orders where id = new.work_order_id;
  if v_org is distinct from new.org_id then
    raise exception 'a crew can only be assigned to a work order in its own workspace';
  elsif v_kind <> 'trade' then
    raise exception 'crews are assigned to trade work orders, not to the master — open the trade this crew does';
  elsif v_voided is not null then
    raise exception 'that work order is voided — a crew cannot be assigned to it';
  end if;
  return new;
end;
$function$;

create trigger work_order_crew_assignments_validate
  before insert or update on public.work_order_crew_assignments
  for each row execute function public.work_order_crew_assignments_validate();

-- updated_at moves only when a value moved (rule 10), for the two tables that carry it. Named zz_ so it
-- fires AFTER the trim trigger (BEFORE triggers fire in name order): a re-sent untrimmed name is not a change.
create function public.crew_touch_updated_at()
returns trigger language plpgsql set search_path to 'public'
as $function$
begin
  if row(new.*) is distinct from row(old.*) and new.updated_at is not distinct from old.updated_at then
    new.updated_at := now();
  end if;
  return new;
end;
$function$;

create trigger crew_people_zz_touch before update on public.crew_people
  for each row execute function public.crew_touch_updated_at();
create trigger crews_zz_touch before update on public.crews
  for each row execute function public.crew_touch_updated_at();

-- Names are trimmed at the write, for every writer (the 9/11 material_items shape).
create function public.crew_trim_names()
returns trigger language plpgsql set search_path to 'public'
as $function$
begin
  if tg_table_name = 'crew_people' then
    new.full_name := btrim(new.full_name);
    new.phone := nullif(btrim(new.phone), '');
    new.vehicle_note := nullif(btrim(new.vehicle_note), '');
  elsif tg_table_name = 'crews' then
    new.name := btrim(new.name);
  end if;
  return new;
end;
$function$;

create trigger crew_people_trim before insert or update on public.crew_people
  for each row execute function public.crew_trim_names();
create trigger crews_trim before insert or update on public.crews
  for each row execute function public.crew_trim_names();

-- ---------------------------------------------------------------------------------------------
-- 5. Grants and RLS — rule 9: authenticated = SELECT, INSERT, UPDATE, DELETE; anon = nothing.
--    Read: any member of the tenant (a crew needs to see its crew). Write: the `schedule` capability.
-- ---------------------------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['crew_people','crews','crew_memberships','crew_person_unavailability','work_order_crew_assignments'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from anon', t);
    execute format('revoke truncate, references, trigger, maintain on table public.%I from authenticated', t);
    execute format('grant select, insert, update, delete on table public.%I to authenticated', t);
    execute format('create policy "member read own %1$s" on public.%1$I for select to authenticated using (org_id in (select my_org_ids()))', t);
    execute format('create policy "scheduler insert own %1$s" on public.%1$I for insert to authenticated with check (org_id in (select my_org_ids()) and has_capability(org_id, ''schedule''))', t);
    execute format('create policy "scheduler update own %1$s" on public.%1$I for update to authenticated using (org_id in (select my_org_ids()) and has_capability(org_id, ''schedule'')) with check (org_id in (select my_org_ids()) and has_capability(org_id, ''schedule''))', t);
    execute format('create policy "scheduler delete own %1$s" on public.%1$I for delete to authenticated using (org_id in (select my_org_ids()) and has_capability(org_id, ''schedule''))', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. The state the scheduler sees
-- ---------------------------------------------------------------------------------------------
create view public.crew_assignment_states with (security_invoker = true) as
with members as (
  select m.crew_id, p.id as person_id, p.has_vehicle
  from public.crew_memberships m
  join public.crew_people p on p.id = m.person_id and p.archived_at is null
), crew_facts as (
  select c.id as crew_id,
         count(mb.person_id) as members,
         count(mb.person_id) filter (where mb.has_vehicle) as with_vehicle,
         count(mb.person_id) filter (where mb.has_vehicle is null) as vehicle_not_recorded
  from public.crews c left join members mb on mb.crew_id = c.id
  group by c.id
)
select a.id as assignment_id, a.org_id, w.job_id, a.work_order_id, w.trade, a.crew_id, c.name as crew_name, a.task,
       sb.id as schedule_block_id, sb.start_date, sb.end_date,
       f.members,
       case when f.members = 0 then 'crew_has_no_members'
            when f.with_vehicle > 0 then 'has_vehicle'
            when f.vehicle_not_recorded > 0 then 'vehicle_not_recorded'
            else 'no_vehicle' end as vehicle_state,
       case when sb.id is null then null
            else (select count(distinct mb.person_id) from members mb
                  join public.crew_person_unavailability u on u.person_id = mb.person_id
                  where mb.crew_id = a.crew_id
                    and u.starts_on <= sb.end_date and u.ends_on >= sb.start_date) end as unavailable_members,
       case when f.members = 0 then 'crew_has_no_members'
            when sb.id is null then 'not_scheduled'
            when exists (select 1 from members mb
                         join public.crew_person_unavailability u on u.person_id = mb.person_id
                         where mb.crew_id = a.crew_id
                           and u.starts_on <= sb.end_date and u.ends_on >= sb.start_date) then 'some_unavailable'
            else 'all_available' end as availability_state
from public.work_order_crew_assignments a
join public.crews c on c.id = a.crew_id
join public.work_orders w on w.id = a.work_order_id
join crew_facts f on f.crew_id = a.crew_id
left join public.schedule_blocks sb on sb.work_order_id = a.work_order_id;

revoke all on table public.crew_assignment_states from anon;
revoke insert, update, delete, truncate, references, trigger, maintain on table public.crew_assignment_states from authenticated;
grant select on table public.crew_assignment_states to authenticated;

revoke execute on function public.work_order_crew_assignments_validate() from public, anon, authenticated;
revoke execute on function public.crew_touch_updated_at() from public, anon, authenticated;
revoke execute on function public.crew_trim_names() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['crew_people','crews','crew_memberships','crew_person_unavailability','work_order_crew_assignments'] loop
    if has_table_privilege('anon', ('public.' || t)::regclass, 'SELECT')
       or has_table_privilege('authenticated', ('public.' || t)::regclass, 'TRUNCATE')
       or has_table_privilege('authenticated', ('public.' || t)::regclass, 'MAINTAIN') then
      raise exception '% does not match the house grant standard', t;
    end if;
  end loop;
end $$;