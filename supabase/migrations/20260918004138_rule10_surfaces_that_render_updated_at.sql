-- RULE 10 FOR THE TWO SURFACES THAT SHOW A PERSON "LAST CHANGED BY/AT". Track S · 2026-09-17. Ruling 3a.
-- Rollback: supabase/rollbacks/20260917_rule10_surfaces_that_render_updated_at_rollback.sql
--
-- CONTROLLER RULING (3a): `updated_at` is NOT provenance, and the 31 Class C functions are OUT OF SCOPE — unless
-- a surface renders it to a human as "last changed by/at". MEASURED in src/ at f7a8509: exactly TWO surfaces do.
--   · src/app/w/[orgId]/build/page.tsx:412 — "{changedBy} · {updated_at}" on roadmap_items (Jacob's Build module).
--     Class C writer: update_roadmap_fields().
--   · src/components/roadmap/RoadmapView.tsx:437 — "Last updated {updated_at}" on the client's roadmap page.
--     Class C writer: protect_roadmap_columns() (BEFORE UPDATE trigger on client_roadmaps; it stamps on EVERY update).
-- PROVED BEFORE (synthetic rows, rolled back, stamps seeded to 2020): update_roadmap_fields() with the values
-- already stored moved updated_by to the caller and updated_at to now; a no-op UPDATE of client_roadmaps
-- (status = status) moved "Last updated" to now. Whether any live row was moved by a no-op is UNANSWERABLE —
-- no before-values are kept (6 of 9 client roadmaps have updated_at <> created_at; the cause is not recorded).
-- The Build page's notes input already refuses to submit an unchanged value; the function did not.
-- The other 29 Class C functions stay OUT OF SCOPE by ruling. The sweep is closed.

create or replace function public.update_roadmap_fields(p_id uuid, p_patch jsonb)
 returns void language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_actor_id uuid;
  v_key text;
  v_allowed text[] := array['phase', 'section', 'feature', 'status', 'notes', 'sort_order'];
  v_new_phase text;
  v_new_status text;
  v_cur public.roadmap_items;
begin
  select * into v_cur from public.roadmap_items where id = p_id;
  v_org_id := v_cur.org_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'roadmap item not found or not accessible: %', p_id;
  end if;

  for v_key in select jsonb_object_keys(p_patch) loop
    if not (v_key = any(v_allowed)) then
      raise exception 'field not writable via patch: %', v_key;
    end if;
  end loop;

  if p_patch ? 'phase' then
    v_new_phase := p_patch ->> 'phase';
    if v_new_phase not in ('now', 'A', 'B', 'C', 'D', 'later') then
      raise exception 'invalid roadmap phase: %', v_new_phase;
    end if;
  end if;

  if p_patch ? 'status' then
    v_new_status := p_patch ->> 'status';
    if v_new_status not in ('shipped', 'in_progress', 'planned') then
      raise exception 'invalid roadmap status: %', v_new_status;
    end if;
  end if;

  -- RULE 10 (2026-09-17): a patch that changes no value does not change who changed it, or when. The Build page
  -- renders updated_by · updated_at as "last changed by/at".
  if (not (p_patch ? 'phase')      or v_new_phase is not distinct from v_cur.phase)
     and (not (p_patch ? 'section')    or (p_patch ->> 'section') is not distinct from v_cur.section)
     and (not (p_patch ? 'feature')    or (p_patch ->> 'feature') is not distinct from v_cur.feature)
     and (not (p_patch ? 'status')     or v_new_status is not distinct from v_cur.status)
     and (not (p_patch ? 'notes')      or (p_patch ->> 'notes') is not distinct from v_cur.notes)
     and (not (p_patch ? 'sort_order') or nullif(p_patch ->> 'sort_order', '')::int is not distinct from v_cur.sort_order)
  then
    return;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.roadmap_items
  set
    phase = case when p_patch ? 'phase' then v_new_phase else phase end,
    section = case when p_patch ? 'section' then p_patch ->> 'section' else section end,
    feature = case when p_patch ? 'feature' then p_patch ->> 'feature' else feature end,
    status = case when p_patch ? 'status' then v_new_status else status end,
    notes = case when p_patch ? 'notes' then p_patch ->> 'notes' else notes end,
    sort_order = case when p_patch ? 'sort_order' then nullif(p_patch ->> 'sort_order', '')::int else sort_order end,
    updated_by = coalesce(v_actor_id, updated_by),
    updated_at = now()
  where id = p_id;
end;
$function$;

create or replace function public.protect_roadmap_columns()
 returns trigger language plpgsql set search_path to 'public'
as $function$
begin
  if new.id <> old.id
     or new.token <> old.token
     or new.client_name <> old.client_name
     or new.company <> old.company
     or coalesce(new.trade,'') <> coalesce(old.trade,'')
     or coalesce(new.crew_size,0) <> coalesce(old.crew_size,0)
     or coalesce(new.score,0) <> coalesce(old.score,0)
     or coalesce(new.risk_level,'') <> coalesce(old.risk_level,'')
     or coalesce(new.revenue_leak_monthly,0) <> coalesce(old.revenue_leak_monthly,0)
     or new.created_at <> old.created_at then
    raise exception 'immutable columns';
  end if;
  -- RULE 10 (2026-09-17): the client's page shows this as "Last updated". Only a change to a value moves it.
  if (to_jsonb(new) - 'updated_at') is distinct from (to_jsonb(old) - 'updated_at') then
    new.updated_at := now();
  else
    new.updated_at := old.updated_at;
  end if;
  return new;
end $function$;
