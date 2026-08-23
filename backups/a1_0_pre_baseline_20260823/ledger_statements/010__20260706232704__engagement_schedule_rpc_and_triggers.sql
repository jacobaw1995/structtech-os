
-- Materializes an engagement + its levels/milestones from client_roadmaps JSONB.
-- Idempotent: returns the existing engagement id if this deal already has one, instead of erroring.
create or replace function public.create_engagement_from_roadmap(p_deal_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare
  d record;
  rm record;
  org_row record;
  eng_id uuid;
  prev_lvl_id uuid := null;
  lvl jsonb;
  ms jsonb;
  li int := 0;
  mi int;
  win_idx int;
  last_client_idx int;
  lvl_id uuid;
begin
  select id, lead_id into eng_id from public.engagements where deal_id = p_deal_id;
  if found then return eng_id; end if;

  select * into d from public.deals where id = p_deal_id;
  if not found then raise exception 'deal not found: %', p_deal_id; end if;

  select * into rm from public.client_roadmaps where lead_id = d.lead_id order by created_at desc limit 1;
  if not found then raise exception 'no roadmap found for deal %', p_deal_id; end if;

  select * into org_row from public.organizations where deal_id = p_deal_id limit 1;

  insert into public.engagements (deal_id, roadmap_id, org_id, start_date, status)
  values (p_deal_id, rm.id, org_row.id, current_date, 'active')
  returning id into eng_id;

  for lvl in select * from jsonb_array_elements(coalesce(rm.levels, '[]'::jsonb)) loop
    -- win condition: explicit `win:true` flag, else last milestone owned by 'client' — same rule the app uses.
    win_idx := null;
    mi := 0;
    for ms in select * from jsonb_array_elements(coalesce(lvl->'milestones', '[]'::jsonb)) loop
      if (ms->>'win')::boolean is true then win_idx := mi; end if;
      mi := mi + 1;
    end loop;
    if win_idx is null then
      last_client_idx := null;
      mi := 0;
      for ms in select * from jsonb_array_elements(coalesce(lvl->'milestones', '[]'::jsonb)) loop
        if ms->>'owner' = 'client' then last_client_idx := mi; end if;
        mi := mi + 1;
      end loop;
      win_idx := last_client_idx;
    end if;

    insert into public.engagement_levels
      (engagement_id, org_id, level_no, title, why, area, sort_order, depends_on_level_id, status)
    values
      (eng_id, org_row.id, li + 1, lvl->>'title', lvl->>'why', lvl->>'area', li, prev_lvl_id, 'not_started')
    returning id into lvl_id;

    mi := 0;
    for ms in select * from jsonb_array_elements(coalesce(lvl->'milestones', '[]'::jsonb)) loop
      insert into public.engagement_milestones
        (level_id, org_id, owner, body, is_win_condition, sort_order, status, completed_at)
      values
        (lvl_id, org_row.id, ms->>'owner', ms->>'label', (mi = win_idx), mi,
         case when (ms->>'done')::boolean is true then 'complete' else 'open' end,
         nullif(ms->>'done_at', '')::timestamptz);
      mi := mi + 1;
    end loop;

    prev_lvl_id := lvl_id;
    li := li + 1;
  end loop;

  return eng_id;
end;
$function$;

-- Keeps engagement_levels.status derived from milestone completion. 'blocked' is a manual admin
-- override and is sticky: this trigger will not auto-transition a level out of 'blocked'.
create or replace function public.derive_level_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  lvl record;
  win_done boolean;
  any_done boolean;
  new_status text;
begin
  select * into lvl from public.engagement_levels where id = coalesce(new.level_id, old.level_id);
  if not found or lvl.status = 'blocked' then
    return coalesce(new, old);
  end if;

  select bool_or(status = 'complete' and is_win_condition), bool_or(status = 'complete')
  into win_done, any_done
  from public.engagement_milestones where level_id = lvl.id;

  if win_done then new_status := 'complete';
  elsif any_done or lvl.actual_start is not null then new_status := 'in_progress';
  else new_status := 'not_started';
  end if;

  if new_status is distinct from lvl.status then
    update public.engagement_levels
    set status = new_status,
        actual_start = case when new_status <> 'not_started' then coalesce(actual_start, current_date) else actual_start end,
        actual_end = case when new_status = 'complete' then coalesce(actual_end, current_date) else actual_end end
    where id = lvl.id;
  end if;

  return coalesce(new, old);
end;
$function$;

create trigger trg_derive_level_status
after insert or update of status on public.engagement_milestones
for each row execute function public.derive_level_status();

-- Wire materialization into the existing stage-change trigger. Failure here must not block the
-- deal's stage change itself (roadmap-missing edge case) — log it to deal_activity instead.
create or replace function public.deal_stage_side_effects()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if new.stage <> old.stage then
    insert into public.deal_activity (deal_id, action, from_value, to_value)
    values (new.id, 'stage_changed', old.stage, new.stage);

    if new.stage in ('call_booked','call_done','proposal_sent','negotiating','closed_won','closed_lost') then
      update public.follow_ups set status = 'cancelled'
      where deal_id = new.id and status = 'pending';
    end if;

    if new.stage in ('closed_won','closed_lost') then
      new.closed_at := now();
    end if;

    if new.stage = 'closed_won' then
      begin
        perform public.create_engagement_from_roadmap(new.id);
      exception when others then
        insert into public.deal_activity (deal_id, action, to_value)
        values (new.id, 'engagement_materialize_failed', sqlerrm);
      end;
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$function$;
