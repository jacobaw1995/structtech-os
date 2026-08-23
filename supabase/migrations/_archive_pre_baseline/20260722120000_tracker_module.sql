-- StructTech OS — Tracker module v1: internal, multi-project work tracker.
--
-- NOT APPLIED. Author-only migration file — ask before applying to the live
-- Supabase project, same as every other migration in this repo.
--
-- Context: docs/reference/TRACKER_MODULE_SPEC.md (authoritative). Isaac goes
-- live Monday and will generate a burst of bug reports/feature requests in
-- week one; this replaces a throwaway single-user Claude artifact with a
-- real, durable, org-scoped tool. Internal tenants only (StructTech) — NOT
-- licensed to BMR in v1, though the model is kept generic enough (source /
-- reported_by_org_id / reported_by_profile_id hooks) that entitling a
-- contractor tenant later is a config act, not a rework.
--
-- Two tables (deliberately tight, per spec): tracker_projects, tracker_items.
-- Config-driven statuses/types in tenant_modules.config for module_key=
-- 'tracker' — same pattern as crm_stage_config (20260712130000). Security-
-- definer RPCs for all writes, actor stamping per the Stage 5 Track C2
-- pattern (`select id into v_actor_id from public.profiles where id =
-- auth.uid()`, NULL-safe). No append-only activity log — explicitly
-- deferred per spec (low audit value for a personal internal tracker,
-- cheap to add later).

-- ============================================================================
-- 1. tenant_modules.module_key — add 'tracker' to the allowed set.
-- ============================================================================
alter table public.tenant_modules
  drop constraint tenant_modules_module_key_check;

alter table public.tenant_modules
  add constraint tenant_modules_module_key_check
  check (module_key in ('crm', 'estimating', 'coordination', 'field', 'delivery', 'scan', 'roadmap', 'tracker'));

-- ============================================================================
-- 2. tracker_projects
-- ============================================================================
create table public.tracker_projects (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  description text,
  status text not null default 'active' check (status in ('active', 'paused', 'shipped', 'archived')),
  -- Nullable: a BMR-specific project attaches to BMR; Windy Hill has none.
  -- No RLS/entitlement implication — this is a display link, not a grant.
  linked_org_id uuid references public.organizations(id) on delete set null,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz
);

comment on table public.tracker_projects is
  'Tracker module: a fluid, org-scoped bucket of tracker_items. Internal tenants only (module entitlement gates the route).';

alter table public.tracker_projects enable row level security;

create policy "member read own tracker_projects"
  on public.tracker_projects for select
  using (org_id in (select my_org_ids()));

create policy "member insert own tracker_projects"
  on public.tracker_projects for insert
  with check (org_id in (select my_org_ids()));

create policy "member update own tracker_projects"
  on public.tracker_projects for update
  using (org_id in (select my_org_ids()))
  with check (org_id in (select my_org_ids()));

-- ============================================================================
-- 3. tracker_items
-- ============================================================================
create table public.tracker_items (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.tracker_projects(id) on delete cascade,
  type text not null default 'task' check (type in ('task', 'bug', 'feature', 'idea')),
  title text not null,
  description text,
  status text not null default 'inbox',
  priority text not null default 'normal' check (priority in ('low', 'normal', 'high', 'urgent')),
  assignee_id uuid references public.profiles(id),
  position int not null default 0,
  -- Client-intake hooks (spec: "model now, surface later"). source stays
  -- 'internal' for every write this migration's RPCs produce; a future
  -- client-facing "Report an issue" surface is the only thing that will
  -- ever set source='client' + the reported_by_* pair.
  source text not null default 'internal' check (source in ('internal', 'client')),
  reported_by_org_id uuid references public.organizations(id),
  reported_by_profile_id uuid references public.profiles(id),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,
  archived_at timestamptz
);

comment on table public.tracker_items is
  'Tracker module: tasks/bugs/features/ideas within a tracker_project. status/type sets are validated against tenant_modules.config->tracker at the RPC layer, not a DB check constraint (config-driven, per SCOPE.md 2.7/12F) — the check constraints above are only the outer bound (never violate the base vocabulary even if config is misconfigured).';

alter table public.tracker_items enable row level security;

create policy "member read own tracker_items"
  on public.tracker_items for select
  using (org_id in (select my_org_ids()));

create policy "member insert own tracker_items"
  on public.tracker_items for insert
  with check (org_id in (select my_org_ids()));

create policy "member update own tracker_items"
  on public.tracker_items for update
  using (org_id in (select my_org_ids()))
  with check (org_id in (select my_org_ids()));

create index tracker_items_project_id_idx on public.tracker_items (project_id);
create index tracker_items_org_id_idx on public.tracker_items (org_id);

-- ============================================================================
-- 4. Config helpers — mirror crm_stage_config's shape (20260712130000).
-- tracker_status_config(org_id) / tracker_type_config(org_id) resolve the
-- org's configured status/type lists out of tenant_modules.config for
-- module_key='tracker'. No caller-membership guard for the same reason
-- crm_stage_config has none: these are internal helpers the RPCs below
-- call, exposing only label/key vocabulary, not sensitive data — org-scoped
-- RLS on tenant_modules itself already protects direct reads of that row.
-- ============================================================================
create or replace function public.tracker_status_config(p_org_id uuid)
returns jsonb
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(tm.config -> 'statuses', '[]'::jsonb)
  from public.tenant_modules tm
  where tm.org_id = p_org_id
    and tm.module_key = 'tracker'
  limit 1;
$$;

create or replace function public.tracker_type_config(p_org_id uuid)
returns jsonb
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(tm.config -> 'types', '[]'::jsonb)
  from public.tenant_modules tm
  where tm.org_id = p_org_id
    and tm.module_key = 'tracker'
  limit 1;
$$;

-- ============================================================================
-- 5. Seed: entitle StructTech (internal org only, per spec) to 'tracker'
-- with the default status/type config, then seed the 3 starter projects.
-- ============================================================================
do $$
begin
  if not exists (select 1 from public.organizations where tenant_type = 'internal') then
    raise exception 'tracker seed: no internal-type org found';
  end if;
end $$;

insert into public.tenant_modules (org_id, module_key, enabled, config)
select o.id, 'tracker', true, jsonb_build_object(
  'statuses', jsonb_build_array(
    jsonb_build_object('key', 'inbox',       'label', 'Inbox',       'terminal', false),
    jsonb_build_object('key', 'next',        'label', 'Next',        'terminal', false),
    jsonb_build_object('key', 'in_progress', 'label', 'In Progress', 'terminal', false),
    jsonb_build_object('key', 'blocked',     'label', 'Blocked',     'terminal', false),
    jsonb_build_object('key', 'done',        'label', 'Done',        'terminal', true)
  ),
  'types', jsonb_build_array(
    jsonb_build_object('key', 'task',    'label', 'Task'),
    jsonb_build_object('key', 'bug',     'label', 'Bug'),
    jsonb_build_object('key', 'feature', 'label', 'Feature'),
    jsonb_build_object('key', 'idea',    'label', 'Idea')
  )
)
from public.organizations o
where o.tenant_type = 'internal'
on conflict (org_id, module_key) do update
  set enabled = excluded.enabled,
      config = excluded.config,
      updated_at = now();

insert into public.tracker_projects (org_id, name, linked_org_id)
select o.id, v.name, v.linked_org_id
from public.organizations o
cross join (values
  ('StructTech OS', null::uuid),
  ('Windy Hill Shop', null::uuid),
  ('Brothers Metal Roofing', '9d32b5a9-e11e-401b-8fa7-969065b004ce'::uuid)
) as v(name, linked_org_id)
where o.tenant_type = 'internal'
  and not exists (
    select 1 from public.tracker_projects tp
    where tp.org_id = o.id and tp.name = v.name
  );

-- ============================================================================
-- 6. RPCs — projects
-- ============================================================================
create or replace function public.create_tracker_project(
  p_org_id uuid,
  p_name text,
  p_description text default null,
  p_linked_org_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_project_id uuid;
  v_actor_id uuid;
begin
  if p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of organization %', p_org_id;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  insert into public.tracker_projects (org_id, name, description, linked_org_id, created_by)
  values (p_org_id, p_name, p_description, p_linked_org_id, v_actor_id)
  returning id into v_project_id;

  return v_project_id;
end;
$$;

comment on function public.create_tracker_project(uuid, text, text, uuid) is
  'Tracker project insert RPC. Org-scoped from caller membership.';

create or replace function public.fetch_tracker_project(p_project_id uuid)
returns setof public.tracker_projects
language sql
security definer
stable
set search_path = public
as $$
  select p.*
  from public.tracker_projects p
  where p.id = p_project_id
    and p.org_id in (select my_org_ids());
$$;

create or replace function public.update_tracker_project(
  p_project_id uuid,
  p_name text default null,
  p_description text default null,
  p_status text default null,
  p_linked_org_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.tracker_projects where id = p_project_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'tracker project not found or not accessible: %', p_project_id;
  end if;

  if p_status is not null and p_status not in ('active', 'paused', 'shipped', 'archived') then
    raise exception 'invalid tracker project status: %', p_status;
  end if;

  update public.tracker_projects
  set name = coalesce(p_name, name),
      description = coalesce(p_description, description),
      status = coalesce(p_status, status),
      linked_org_id = coalesce(p_linked_org_id, linked_org_id),
      updated_at = now()
  where id = p_project_id;
end;
$$;

create or replace function public.archive_tracker_project(p_project_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.tracker_projects where id = p_project_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'tracker project not found or not accessible: %', p_project_id;
  end if;

  update public.tracker_projects
  set status = 'archived', archived_at = now(), updated_at = now()
  where id = p_project_id;
end;
$$;

create or replace function public.restore_tracker_project(p_project_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.tracker_projects where id = p_project_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'tracker project not found or not accessible: %', p_project_id;
  end if;

  update public.tracker_projects
  set status = 'active', archived_at = null, updated_at = now()
  where id = p_project_id;
end;
$$;

-- Hard delete — guarded on having zero items, mirroring delete_estimate's
-- guard shape (management_controls_retrofit.sql): a project with real work
-- logged against it should be archived, not deleted out from under its items.
create or replace function public.delete_tracker_project(p_project_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_has_items boolean;
begin
  select org_id into v_org_id from public.tracker_projects where id = p_project_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'tracker project not found or not accessible: %', p_project_id;
  end if;

  select exists(select 1 from public.tracker_items where project_id = p_project_id)
    into v_has_items;

  if v_has_items then
    raise exception 'tracker project % has items and cannot be deleted — archive it instead', p_project_id;
  end if;

  delete from public.tracker_projects where id = p_project_id;
end;
$$;

-- ============================================================================
-- 7. RPCs — items
-- ============================================================================
create or replace function public.create_tracker_item(
  p_org_id uuid,
  p_project_id uuid,
  p_title text,
  p_type text default 'task',
  p_priority text default 'normal',
  p_description text default null,
  p_status text default null,
  p_assignee_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item_id uuid;
  v_actor_id uuid;
  v_status text;
  v_type_valid boolean;
begin
  if p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of organization %', p_org_id;
  end if;

  if not exists (
    select 1 from public.tracker_projects
    where id = p_project_id and org_id = p_org_id
  ) then
    raise exception 'tracker project % not found in organization %', p_project_id, p_org_id;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  select exists (
    select 1 from jsonb_array_elements(public.tracker_type_config(p_org_id)) as t
    where t ->> 'key' = p_type
  ) into v_type_valid;

  if not v_type_valid then
    raise exception 'type % is not configured for organization %', p_type, p_org_id;
  end if;

  if p_priority not in ('low', 'normal', 'high', 'urgent') then
    raise exception 'invalid tracker item priority: %', p_priority;
  end if;

  if p_status is not null then
    v_status := p_status;
  else
    select statuses -> 0 ->> 'key'
    into v_status
    from (select public.tracker_status_config(p_org_id) as statuses) s;
  end if;

  if v_status is null then
    raise exception 'organization % has no tracker status config', p_org_id;
  end if;

  insert into public.tracker_items
    (org_id, project_id, type, title, description, status, priority, assignee_id, created_by)
  values
    (p_org_id, p_project_id, p_type, p_title, p_description, v_status, p_priority, p_assignee_id, v_actor_id)
  returning id into v_item_id;

  return v_item_id;
end;
$$;

comment on function public.create_tracker_item(uuid, uuid, text, text, text, text, text, uuid) is
  'Tracker item insert RPC — the mobile quick-add path (title + type + priority). Status defaults to the org''s configured first status if not given.';

create or replace function public.fetch_tracker_item(p_item_id uuid)
returns setof public.tracker_items
language sql
security definer
stable
set search_path = public
as $$
  select i.*
  from public.tracker_items i
  where i.id = p_item_id
    and i.org_id in (select my_org_ids());
$$;

create or replace function public.update_tracker_item(
  p_item_id uuid,
  p_title text default null,
  p_description text default null,
  p_type text default null,
  p_status text default null,
  p_priority text default null,
  p_assignee_id uuid default null,
  p_clear_assignee boolean default false,
  p_position int default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_type_valid boolean;
  v_status_valid boolean;
  v_old_status text;
  v_old_terminal boolean;
  v_new_terminal boolean;
begin
  select org_id, status into v_org_id, v_old_status from public.tracker_items where id = p_item_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'tracker item not found or not accessible: %', p_item_id;
  end if;

  if p_type is not null then
    select exists (
      select 1 from jsonb_array_elements(public.tracker_type_config(v_org_id)) as t
      where t ->> 'key' = p_type
    ) into v_type_valid;

    if not v_type_valid then
      raise exception 'type % is not configured for organization %', p_type, v_org_id;
    end if;
  end if;

  if p_status is not null then
    select exists (
      select 1 from jsonb_array_elements(public.tracker_status_config(v_org_id)) as s
      where s ->> 'key' = p_status
    ) into v_status_valid;

    if not v_status_valid then
      raise exception 'status % is not configured for organization %', p_status, v_org_id;
    end if;

    -- Config-driven "terminal" flag (mirrors CRM's per-stage outcome field,
    -- crm_stage_config) rather than a hardcoded 'done' string — resolved_at
    -- follows whatever status entry the org's config marks terminal.
    select coalesce((s ->> 'terminal')::boolean, false) into v_new_terminal
    from jsonb_array_elements(public.tracker_status_config(v_org_id)) as s
    where s ->> 'key' = p_status;

    select coalesce((s ->> 'terminal')::boolean, false) into v_old_terminal
    from jsonb_array_elements(public.tracker_status_config(v_org_id)) as s
    where s ->> 'key' = v_old_status;
  end if;

  if p_priority is not null and p_priority not in ('low', 'normal', 'high', 'urgent') then
    raise exception 'invalid tracker item priority: %', p_priority;
  end if;

  update public.tracker_items
  set title = coalesce(p_title, title),
      description = coalesce(p_description, description),
      type = coalesce(p_type, type),
      status = coalesce(p_status, status),
      priority = coalesce(p_priority, priority),
      assignee_id = case when p_clear_assignee then null else coalesce(p_assignee_id, assignee_id) end,
      position = coalesce(p_position, position),
      resolved_at = case
        when p_status is not null and v_new_terminal and not coalesce(v_old_terminal, false) then now()
        when p_status is not null and not v_new_terminal then null
        else resolved_at
      end,
      updated_at = now()
  where id = p_item_id;
end;
$$;

comment on function public.update_tracker_item(uuid, text, text, text, text, text, uuid, boolean, int) is
  'Full-edit RPC: title/description/type/status/priority/assignee/position. p_clear_assignee is the explicit unassign path (coalesce alone cannot distinguish "not given" from "set to null").';

create or replace function public.archive_tracker_item(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.tracker_items where id = p_item_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'tracker item not found or not accessible: %', p_item_id;
  end if;

  update public.tracker_items
  set archived_at = now(), updated_at = now()
  where id = p_item_id;
end;
$$;

create or replace function public.restore_tracker_item(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.tracker_items where id = p_item_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'tracker item not found or not accessible: %', p_item_id;
  end if;

  update public.tracker_items
  set archived_at = null, updated_at = now()
  where id = p_item_id;
end;
$$;

create or replace function public.delete_tracker_item(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.tracker_items where id = p_item_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'tracker item not found or not accessible: %', p_item_id;
  end if;

  delete from public.tracker_items where id = p_item_id;
end;
$$;
