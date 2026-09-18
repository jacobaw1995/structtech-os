-- ROLLBACK for 20260917 rule10_surfaces_that_render_updated_at: both bodies as they were (stamp on every write).
CREATE OR REPLACE FUNCTION public.update_roadmap_fields(p_id uuid, p_patch jsonb)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_actor_id uuid;
  v_key text;
  v_allowed text[] := array['phase', 'section', 'feature', 'status', 'notes', 'sort_order'];
  v_new_phase text;
  v_new_status text;
begin
  select org_id into v_org_id from public.roadmap_items where id = p_id;

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

CREATE OR REPLACE FUNCTION public.protect_roadmap_columns()
 RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
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
  new.updated_at := now();
  return new;
end $function$;
