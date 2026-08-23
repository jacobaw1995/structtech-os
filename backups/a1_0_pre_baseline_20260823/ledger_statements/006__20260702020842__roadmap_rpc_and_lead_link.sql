-- link roadmaps back to the scan that created them
alter table public.client_roadmaps add column if not exists lead_id uuid references public.audit_leads(id);

-- update the auto-trigger to record the link
create or replace function public.auto_create_roadmap()
returns trigger language plpgsql security definer as $$
declare
  worst record;
  lvls jsonb := '[]'::jsonb;
  pb jsonb;
  ms jsonb;
  li int := 0;
  mi int;
  built_ms jsonb;
begin
  for worst in
    select key as q, (value)::int as score
    from jsonb_each_text(coalesce(new.answers, '{}'::jsonb))
    where key ~ '^q([1-9]|10)$'
    order by (value)::int asc, substring(key from 2)::int asc
    limit 3
  loop
    pb := public.roadmap_playbook(worst.q);
    if pb is null then continue; end if;
    built_ms := '[]'::jsonb; mi := 0;
    for ms in select * from jsonb_array_elements(pb->'milestones') loop
      built_ms := built_ms || jsonb_build_array(jsonb_build_object(
        'id','l'||li||'m'||mi,'label',ms->>'label','owner',ms->>'owner','done',false,'done_at',null));
      mi := mi + 1;
    end loop;
    lvls := lvls || jsonb_build_array(jsonb_build_object(
      'title',pb->>'title','why',pb->>'why','area',worst.q,'milestones',built_ms));
    li := li + 1;
  end loop;

  if jsonb_array_length(lvls) > 0 then
    insert into public.client_roadmaps
      (lead_id, client_name, company, trade, crew_size, score, risk_level, revenue_leak_monthly, levels)
    values
      (new.id, coalesce(new.name,'—'), coalesce(new.company,'—'), new.trade, new.crew_size,
       new.score, new.risk_level, new.monthly_leak, lvls);
  end if;
  return new;
end $$;

-- RPC: generate (or regenerate) a roadmap for an existing lead
create or replace function public.generate_roadmap_for_lead(p_lead_id uuid)
returns text language plpgsql security definer as $$
declare
  lead record;
  worst record;
  lvls jsonb := '[]'::jsonb;
  pb jsonb; ms jsonb; li int := 0; mi int; built_ms jsonb;
  new_token text;
begin
  select * into lead from public.audit_leads where id = p_lead_id;
  if not found then raise exception 'lead not found'; end if;

  for worst in
    select key as q, (value)::int as score
    from jsonb_each_text(coalesce(lead.answers, '{}'::jsonb))
    where key ~ '^q([1-9]|10)$'
    order by (value)::int asc, substring(key from 2)::int asc
    limit 3
  loop
    pb := public.roadmap_playbook(worst.q);
    if pb is null then continue; end if;
    built_ms := '[]'::jsonb; mi := 0;
    for ms in select * from jsonb_array_elements(pb->'milestones') loop
      built_ms := built_ms || jsonb_build_array(jsonb_build_object(
        'id','l'||li||'m'||mi,'label',ms->>'label','owner',ms->>'owner','done',false,'done_at',null));
      mi := mi + 1;
    end loop;
    lvls := lvls || jsonb_build_array(jsonb_build_object(
      'title',pb->>'title','why',pb->>'why','area',worst.q,'milestones',built_ms));
    li := li + 1;
  end loop;

  insert into public.client_roadmaps
    (lead_id, client_name, company, trade, crew_size, score, risk_level, revenue_leak_monthly, levels)
  values
    (lead.id, coalesce(lead.name,'—'), coalesce(lead.company,'—'), lead.trade, lead.crew_size,
     lead.score, lead.risk_level, lead.monthly_leak, lvls)
  returning token into new_token;

  return new_token;
end $$;

grant execute on function public.generate_roadmap_for_lead(uuid) to anon;

-- portal needs to read audit_leads
drop policy if exists "anon read leads" on public.audit_leads;
create policy "anon read leads" on public.audit_leads for select to anon using (true);

-- portal can update contacted/notes on leads
drop policy if exists "anon update leads" on public.audit_leads;
create policy "anon update leads" on public.audit_leads for update to anon using (true) with check (true);
