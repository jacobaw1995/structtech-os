
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
  select id into eng_id from public.engagements where deal_id = p_deal_id;
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
