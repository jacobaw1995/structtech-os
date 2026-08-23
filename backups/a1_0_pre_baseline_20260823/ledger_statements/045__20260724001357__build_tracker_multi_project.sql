-- StructTech OS — Build Tracker: multi-project upgrade.
--
-- Context: Jacob's call — one Build Tracker instance covers StructTech OS +
-- Material Matrix + future internal builds. Config-driven: adding a project
-- is a row insert, not a migration. Builds on
-- 20260726120000_build_tracker_module.sql (roadmap_items, module_key='build').

-- ============================================================================
-- 1. roadmap_projects
-- ============================================================================
create table public.roadmap_projects (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  key text not null,
  name text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, key)
);

comment on table public.roadmap_projects is
  'Build Tracker: one row per tracked build (StructTech OS, Material Matrix, ...). Config-driven — adding a project is an insert, not a migration. Same org/entitlement boundary as roadmap_items (module_key=''build'', StructTech-internal).';

alter table public.roadmap_projects enable row level security;

create policy "member read own roadmap_projects"
  on public.roadmap_projects for select
  using (org_id in (select my_org_ids()));

create policy "member insert own roadmap_projects"
  on public.roadmap_projects for insert
  with check (org_id in (select my_org_ids()));

create policy "member update own roadmap_projects"
  on public.roadmap_projects for update
  using (org_id in (select my_org_ids()))
  with check (org_id in (select my_org_ids()));

-- ============================================================================
-- 2. roadmap_items.project_id — nullable first, backfilled, then locked NOT NULL.
-- ============================================================================
alter table public.roadmap_items
  add column project_id uuid references public.roadmap_projects(id) on delete cascade;

-- ============================================================================
-- 3. Seed the two known projects for StructTech (internal org only).
-- ============================================================================
insert into public.roadmap_projects (org_id, key, name, sort_order)
select o.id, v.key, v.name, v.sort_order
from public.organizations o
cross join (values
  ('structtech_os', 'StructTech OS', 0),
  ('material_matrix', 'Material Matrix', 1)
) as v(key, name, sort_order)
where o.tenant_type = 'internal'
on conflict (org_id, key) do nothing;

-- ============================================================================
-- 4. Backfill.
-- ============================================================================
update public.roadmap_items ri
set project_id = rp.id
from public.roadmap_projects rp
where ri.project_id is null
  and rp.org_id = ri.org_id
  and rp.key = 'structtech_os';

-- ============================================================================
-- 5. Lock it down.
-- ============================================================================
alter table public.roadmap_items
  alter column project_id set not null;

create index roadmap_items_org_project_section_sort_idx
  on public.roadmap_items (org_id, project_id, section, sort_order);

-- ============================================================================
-- 6. RPCs — roadmap_projects
-- ============================================================================
create or replace function public.create_roadmap_project(
  p_org_id uuid,
  p_key text,
  p_name text,
  p_sort_order int default 0
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_project_id uuid;
begin
  if p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of organization %', p_org_id;
  end if;

  insert into public.roadmap_projects (org_id, key, name, sort_order)
  values (p_org_id, p_key, p_name, p_sort_order)
  returning id into v_project_id;

  return v_project_id;
end;
$$;

comment on function public.create_roadmap_project(uuid, text, text, int) is
  'Build Tracker project insert RPC. Org-scoped from caller membership. Unique (org_id, key) enforces no duplicate project slugs.';

create or replace function public.update_roadmap_project(
  p_project_id uuid,
  p_name text default null,
  p_sort_order int default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.roadmap_projects where id = p_project_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'roadmap project not found or not accessible: %', p_project_id;
  end if;

  update public.roadmap_projects
  set name = coalesce(p_name, name),
      sort_order = coalesce(p_sort_order, sort_order),
      updated_at = now()
  where id = p_project_id;
end;
$$;

comment on function public.update_roadmap_project(uuid, text, int) is
  'Build Tracker project rename/reorder RPC. key is immutable by design (it is the stable slug items key off of) — delete and recreate if a project was truly misnamed at creation.';

create or replace function public.delete_roadmap_project(p_project_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_has_items boolean;
begin
  select org_id into v_org_id from public.roadmap_projects where id = p_project_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'roadmap project not found or not accessible: %', p_project_id;
  end if;

  select exists(select 1 from public.roadmap_items where project_id = p_project_id)
    into v_has_items;

  if v_has_items then
    raise exception 'roadmap project % has items and cannot be deleted — remove or reassign its items first', p_project_id;
  end if;

  delete from public.roadmap_projects where id = p_project_id;
end;
$$;

-- ============================================================================
-- 7. create_roadmap_item — signature change (gains p_project_id).
-- ============================================================================
drop function public.create_roadmap_item(p_org_id uuid, p_phase text, p_section text, p_feature text, p_status text, p_notes text, p_sort_order integer);

create or replace function public.create_roadmap_item(
  p_org_id uuid,
  p_project_id uuid,
  p_phase text,
  p_section text,
  p_feature text,
  p_status text default 'planned',
  p_notes text default null,
  p_sort_order int default 0
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item_id uuid;
  v_actor_id uuid;
  v_project_org_id uuid;
begin
  if p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of organization %', p_org_id;
  end if;

  select org_id into v_project_org_id from public.roadmap_projects where id = p_project_id;

  if v_project_org_id is null or v_project_org_id <> p_org_id then
    raise exception 'roadmap project % does not belong to organization %', p_project_id, p_org_id;
  end if;

  if p_phase not in ('now', 'A', 'B', 'C', 'D', 'later') then
    raise exception 'invalid roadmap phase: %', p_phase;
  end if;

  if p_status not in ('shipped', 'in_progress', 'planned') then
    raise exception 'invalid roadmap status: %', p_status;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  insert into public.roadmap_items (org_id, project_id, phase, section, feature, status, notes, sort_order, updated_by)
  values (p_org_id, p_project_id, p_phase, p_section, p_feature, p_status, p_notes, p_sort_order, v_actor_id)
  returning id into v_item_id;

  return v_item_id;
end;
$$;

comment on function public.create_roadmap_item(uuid, uuid, text, text, text, text, text, int) is
  'Build Tracker item insert RPC, v2 — adds p_project_id (validated to belong to p_org_id). Org-scoped from caller membership; stamps updated_by.';
