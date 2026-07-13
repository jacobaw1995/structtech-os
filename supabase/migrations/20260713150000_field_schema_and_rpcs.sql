-- StructTech OS — Week 3 Stage 2: field schema (contractor-only)
--
-- NOT APPLIED. Author-only migration file — ask before applying, same as
-- every other migration in this repo. Depends on the coordination schema
-- (20260713120000_coordination_schema_and_rpcs.sql) already being applied —
-- check_ins and production_packets both hang off work_orders.
--
-- Standing rule as of today (SCOPE.md §2.6, confirmed 7/13): every entity
-- ships full CRUD — create, edit, AND delete/archive — from the UI, no
-- create-only. Every table below gets select/insert/update/delete RLS
-- policies and a matching RPC for each, not just create+read.
--
-- Three scope calls made here, flagged for review same as the coordination
-- migration's header:
--
--   1. check_ins.photos reuses the signatures.signature_data precedent —
--      base64 image data in a text[] column — instead of Cloudflare R2.
--      R2 file storage is still deferred (BACKLOG.md, owed from Week 2), and
--      building a photo-picker UI with nowhere real to put the files would
--      either silently drop them or need R2 wired up first — neither fits
--      this deadline. This is a genuinely functional stopgap (photos really
--      persist, crew can view them back), not a fake control. Revisit once
--      R2 lands (SCOPE.md §12E) — swap the column for R2 object keys.
--
--   2. production_packets has no photos column of its own. The wireframe's
--      packet is "built from work order + sign-off photos" — i.e. derived,
--      not re-keyed (SCOPE.md §6, no re-entry). The packet page pulls
--      photos live from that work order's check_ins at read time instead of
--      duplicating storage. Trim map / boot-vent placement layers are
--      explicitly deferred (needs an annotated-image layer over R2 photos +
--      pin coordinates — BACKLOG) and have no column here either.
--
--   3. production_packets.callouts is a jsonb array of {id, label, detail}
--      objects, not a child table. The standing CRUD rule still applies —
--      three RPCs below add/update/delete a callout by its id inside the
--      array — but a fourth table felt like more surface than a short
--      editable list needs. Flagging in case you'd rather have a real
--      child table (sortable, FK-constrained) instead.
--
-- No "crew" entity and no user-to-crew mapping exist yet (same gap
-- schedule_blocks.crew_name already has). check_ins.crew_name is free text
-- for the same reason — a crew member self-identifies at submission time,
-- same convention as scheduling.
--
-- Today's job list (the field UI's first screen) has no dedicated table —
-- it's a read derived from schedule_blocks + work_orders (today's date
-- falls in [start_date, end_date], or starts soon), same "derive, don't
-- duplicate" reasoning as note 2.

-- ============================================================================
-- 1. check_ins
-- ============================================================================
create table public.check_ins (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  schedule_block_id uuid references public.schedule_blocks(id) on delete set null,

  crew_name text not null,
  check_in_date date not null default current_date,
  hours numeric not null default 0,
  materials_used text,
  blockers text,

  -- Base64 data URIs — see migration header note 1.
  photos text[] not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index check_ins_org_id_idx on public.check_ins(org_id);
create index check_ins_work_order_id_idx on public.check_ins(work_order_id);

comment on column public.check_ins.photos is
  'Base64 data URIs, same stopgap as signatures.signature_data — not R2. See migration header note 1.';

alter table public.check_ins enable row level security;

create policy "member read own check_ins"
  on public.check_ins for select
  using (org_id in (select my_org_ids()));

create policy "member insert own check_ins"
  on public.check_ins for insert
  with check (org_id in (select my_org_ids()));

create policy "member update own check_ins"
  on public.check_ins for update
  using (org_id in (select my_org_ids()))
  with check (org_id in (select my_org_ids()));

create policy "member delete own check_ins"
  on public.check_ins for delete
  using (org_id in (select my_org_ids()));

-- ============================================================================
-- 2. production_packets
-- ============================================================================
create table public.production_packets (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  work_order_id uuid not null references public.work_orders(id) on delete cascade,

  notes text,

  -- Custom detail callouts — see migration header note 3.
  callouts jsonb not null default '[]'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- One packet per work order — get_or_create_production_packet() below is
  -- idempotent against this, same pattern as work_orders.estimate_id.
  unique (work_order_id)
);

create index production_packets_org_id_idx on public.production_packets(org_id);

comment on table public.production_packets is
  'Built from work order + check-in photos (derived, not duplicated — SCOPE.md §6 no re-entry). Trim map / boot-vent layers deferred. See migration header notes 2/3.';
comment on column public.production_packets.callouts is
  'jsonb array of {id, label, detail} — CRUD via add/update/delete_production_packet_callout RPCs, not a child table. See migration header note 3.';

alter table public.production_packets enable row level security;

create policy "member read own production_packets"
  on public.production_packets for select
  using (org_id in (select my_org_ids()));

create policy "member insert own production_packets"
  on public.production_packets for insert
  with check (org_id in (select my_org_ids()));

create policy "member update own production_packets"
  on public.production_packets for update
  using (org_id in (select my_org_ids()))
  with check (org_id in (select my_org_ids()));

create policy "member delete own production_packets"
  on public.production_packets for delete
  using (org_id in (select my_org_ids()));

-- ============================================================================
-- 3. RPCs — all security-definer, org-scoped from the caller's own
-- membership, per the pattern established in Week 2/3.
-- ============================================================================

-- 3a. Check-in CRUD.
create or replace function public.create_check_in(
  p_work_order_id uuid,
  p_crew_name text,
  p_schedule_block_id uuid default null,
  p_check_in_date date default current_date,
  p_hours numeric default 0,
  p_materials_used text default null,
  p_blockers text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_check_in_id uuid;
begin
  select org_id into v_org_id
  from public.work_orders where id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  insert into public.check_ins
    (org_id, work_order_id, schedule_block_id, crew_name, check_in_date, hours, materials_used, blockers)
  values
    (v_org_id, p_work_order_id, p_schedule_block_id, p_crew_name, coalesce(p_check_in_date, current_date), coalesce(p_hours, 0), p_materials_used, p_blockers)
  returning id into v_check_in_id;

  return v_check_in_id;
end;
$$;

-- 3b. fetch_check_in — single-record fetch RPC (CLAUDE.md rule 4).
create or replace function public.fetch_check_in(p_check_in_id uuid)
returns setof public.check_ins
language sql
security definer
stable
set search_path = public
as $$
  select c.*
  from public.check_ins c
  where c.id = p_check_in_id
    and c.org_id in (select my_org_ids());
$$;

create or replace function public.update_check_in(
  p_check_in_id uuid,
  p_crew_name text default null,
  p_check_in_date date default null,
  p_hours numeric default null,
  p_materials_used text default null,
  p_blockers text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id
  from public.check_ins where id = p_check_in_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  update public.check_ins
  set crew_name = coalesce(p_crew_name, crew_name),
      check_in_date = coalesce(p_check_in_date, check_in_date),
      hours = coalesce(p_hours, hours),
      materials_used = coalesce(p_materials_used, materials_used),
      blockers = coalesce(p_blockers, blockers),
      updated_at = now()
  where id = p_check_in_id;
end;
$$;

-- 3c. delete_check_in — a crew member fixing a check-in they got wrong
-- (SCOPE.md §2.6 / today's standing rule), not just future edits.
create or replace function public.delete_check_in(p_check_in_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id
  from public.check_ins where id = p_check_in_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  delete from public.check_ins where id = p_check_in_id;
end;
$$;

create or replace function public.add_check_in_photo(
  p_check_in_id uuid,
  p_photo_data_url text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id
  from public.check_ins where id = p_check_in_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  update public.check_ins
  set photos = array_append(photos, p_photo_data_url),
      updated_at = now()
  where id = p_check_in_id;
end;
$$;

create or replace function public.remove_check_in_photo(
  p_check_in_id uuid,
  p_photo_data_url text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id
  from public.check_ins where id = p_check_in_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  update public.check_ins
  set photos = array_remove(photos, p_photo_data_url),
      updated_at = now()
  where id = p_check_in_id;
end;
$$;

-- 3d. Production packet CRUD. get_or_create is idempotent — the Packet tab
-- calls this on load, same pattern as create_work_order_from_estimate.
create or replace function public.get_or_create_production_packet(p_work_order_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_packet_id uuid;
begin
  select org_id into v_org_id
  from public.work_orders where id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  select id into v_packet_id
  from public.production_packets
  where work_order_id = p_work_order_id;

  if v_packet_id is not null then
    return v_packet_id;
  end if;

  insert into public.production_packets (org_id, work_order_id)
  values (v_org_id, p_work_order_id)
  returning id into v_packet_id;

  return v_packet_id;
end;
$$;

-- 3e. fetch_production_packet — single-record fetch RPC (CLAUDE.md rule 4).
create or replace function public.fetch_production_packet(p_production_packet_id uuid)
returns setof public.production_packets
language sql
security definer
stable
set search_path = public
as $$
  select p.*
  from public.production_packets p
  where p.id = p_production_packet_id
    and p.org_id in (select my_org_ids());
$$;

create or replace function public.update_production_packet_notes(
  p_production_packet_id uuid,
  p_notes text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id
  from public.production_packets where id = p_production_packet_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  update public.production_packets
  set notes = p_notes,
      updated_at = now()
  where id = p_production_packet_id;
end;
$$;

-- 3f. delete_production_packet — "archive/reset" per the standing CRUD
-- rule. get_or_create_production_packet() regenerates a fresh empty one on
-- the next Packet tab visit, so this is a real, safe undo.
create or replace function public.delete_production_packet(p_production_packet_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id
  from public.production_packets where id = p_production_packet_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  delete from public.production_packets where id = p_production_packet_id;
end;
$$;

-- 3g. Callout CRUD — jsonb array manipulation keyed by each callout's own
-- id (see migration header note 3).
create or replace function public.add_production_packet_callout(
  p_production_packet_id uuid,
  p_label text,
  p_detail text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_callout_id uuid := gen_random_uuid();
begin
  select org_id into v_org_id
  from public.production_packets where id = p_production_packet_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  update public.production_packets
  set callouts = callouts || jsonb_build_array(
        jsonb_build_object('id', v_callout_id, 'label', p_label, 'detail', p_detail)
      ),
      updated_at = now()
  where id = p_production_packet_id;

  return v_callout_id;
end;
$$;

create or replace function public.update_production_packet_callout(
  p_production_packet_id uuid,
  p_callout_id uuid,
  p_label text default null,
  p_detail text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id
  from public.production_packets where id = p_production_packet_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  update public.production_packets
  set callouts = (
        select coalesce(jsonb_agg(
          case when (elem->>'id')::uuid = p_callout_id
            then jsonb_build_object(
              'id', elem->>'id',
              'label', coalesce(p_label, elem->>'label'),
              'detail', coalesce(p_detail, elem->>'detail')
            )
            else elem
          end
        ), '[]'::jsonb)
        from jsonb_array_elements(callouts) as elem
      ),
      updated_at = now()
  where id = p_production_packet_id;
end;
$$;

create or replace function public.delete_production_packet_callout(
  p_production_packet_id uuid,
  p_callout_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id
  from public.production_packets where id = p_production_packet_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  update public.production_packets
  set callouts = (
        select coalesce(jsonb_agg(elem), '[]'::jsonb)
        from jsonb_array_elements(callouts) as elem
        where (elem->>'id')::uuid <> p_callout_id
      ),
      updated_at = now()
  where id = p_production_packet_id;
end;
$$;
