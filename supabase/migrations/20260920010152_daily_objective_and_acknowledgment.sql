-- A4.1 DAILY OBJECTIVE and A4.5 CREW ACKNOWLEDGMENT — the spine. Track S · 2026-09-19.
-- Rollback: supabase/rollbacks/20260919_daily_objective_and_acknowledgment_rollback.sql
--
-- BEFORE-MEASUREMENT (2026-09-19, whole database): 2 trade work orders · 0 with a crew assigned ·
-- 2 with a schedule block · 0 crews · 0 crew people · 0 objectives and 0 acknowledgments (new here).
--
-- A4.1 — WHAT THE CREW IS MEANT TO ACHIEVE TODAY, set by the office, per TRADE work order, per DAY.
-- One objective per work order per day (a second save edits that day's, it does not add another). The date is
-- NEW YORK's, never the session's (2026-09-16's defect, not repeated). Text only: no money column exists on
-- this table, and nothing it returns is joined to a priced table.
--
-- A4.5 — AN ACKNOWLEDGMENT IS A FACT ABOUT A PERSON, A TIME AND A VERSION, NOT A FLAG.
-- `work_order_version(work_order)` is a sha256 over exactly what the crew is shown: the trade's own fields,
-- its materials (name, quantity, unit, ready-by), its schedule blocks, and today's objective. NO MONEY IS IN
-- THE DOCUMENT — not blanked, absent. Each acknowledgment stores who, when, and the version acknowledged:
--   · acknowledging the SAME version again writes nothing (RULE 10 — it changes no value);
--   · a change to the scope produces a NEW version, so the old acknowledgment stands as the fact it was and
--     the state becomes `scope_changed_since` — a different state, not the same one.
-- Acknowledgment states: `not_acknowledged` · `acknowledged` · `scope_changed_since`.
--
-- WHO MAY DO WHAT. Reading: any member of the org who can see that work order — enforced BY THE FUNCTION
-- DECLINING (assert_work_order_level, which since 2026-09-19 answers "not found or not accessible" to anyone
-- the work_orders guard would have hidden it from). Writing an objective: the office tier.
--   ** view_master_work_order IS A PROXY for "office tier" here, the same proxy as org-files and check-in
--   delete, and it carries the same REPLACEMENT DATE: 2026-11-01. ** `schedule` cannot be used: `field` holds
--   it by default, and a crew must not write its own objective. Acknowledging is the crew's own act and needs
--   only that the work order is visible to them.
-- REACHABLE FROM THE TABLE: both tables carry RLS; writes are refused at the table for anyone the RPCs refuse,
-- so a direct insert cannot do what the function will not.

create table public.work_order_objectives (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  objective_date date not null default (now() at time zone 'America/New_York')::date,
  body text not null,
  published_by uuid references auth.users(id) on delete set null,
  published_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint work_order_objectives_body_not_blank check (btrim(body) <> ''),
  constraint work_order_objectives_one_per_day unique (work_order_id, objective_date)
);
create index work_order_objectives_org_date_idx on public.work_order_objectives (org_id, objective_date);

create table public.work_order_acknowledgments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  acknowledged_by uuid not null references auth.users(id) on delete cascade,
  acknowledged_at timestamptz not null default now(),
  work_order_version text not null,
  constraint work_order_acknowledgments_version_shape check (work_order_version ~ '^[0-9a-f]{64}$'),
  constraint work_order_acknowledgments_one_per_version unique (work_order_id, acknowledged_by, work_order_version)
);
create index work_order_acknowledgments_wo_idx on public.work_order_acknowledgments (work_order_id);

alter table public.work_order_objectives enable row level security;
alter table public.work_order_acknowledgments enable row level security;

-- House standard (CLAUDE.md rule 8, as amended): authenticated = SIUD exactly, anon = nothing.
revoke all on table public.work_order_objectives from anon;
revoke all on table public.work_order_acknowledgments from anon;
revoke truncate, references, trigger, maintain on table public.work_order_objectives from authenticated;
revoke truncate, references, trigger, maintain on table public.work_order_acknowledgments from authenticated;

create policy "member read own work_order_objectives" on public.work_order_objectives for select
  to authenticated using (org_id in (select my_org_ids()));
create policy "office writes work_order_objectives" on public.work_order_objectives for insert
  to authenticated with check (org_id in (select my_org_ids()) and coalesce(can_view_master_work_order(org_id), false));
create policy "office updates work_order_objectives" on public.work_order_objectives for update
  to authenticated using (org_id in (select my_org_ids()) and coalesce(can_view_master_work_order(org_id), false))
  with check (org_id in (select my_org_ids()) and coalesce(can_view_master_work_order(org_id), false));
create policy "office deletes work_order_objectives" on public.work_order_objectives for delete
  to authenticated using (org_id in (select my_org_ids()) and coalesce(can_view_master_work_order(org_id), false));

create policy "member read own work_order_acknowledgments" on public.work_order_acknowledgments for select
  to authenticated using (org_id in (select my_org_ids()));
-- A person acknowledges for THEMSELVES and only for a work order they can see. Nobody edits or deletes one:
-- it is a fact about a moment. (There is no UPDATE or DELETE policy, so both are refused at the table.)
create policy "member acknowledges for themselves" on public.work_order_acknowledgments for insert
  to authenticated with check (
    org_id in (select my_org_ids())
    and acknowledged_by = auth.uid()
    and exists (select 1 from public.work_orders w
                where w.id = work_order_id and w.org_id = work_order_acknowledgments.org_id
                  and (w.kind = 'trade' or coalesce(can_view_master_work_order(w.org_id), false))));

-- ---- the version: exactly what the crew is shown, and no money ---------------------------------------------
create function public.work_order_version(p_work_order_id uuid)
returns text language sql stable security definer set search_path to 'public'
as $function$
  select encode(sha256(convert_to(jsonb_build_object(
    'work_order', jsonb_build_object('id', w.id, 'kind', w.kind, 'trade', w.trade,
                                     'assignee_type', w.assignee_type, 'assignee_ref', w.assignee_ref,
                                     'voided_at', w.voided_at, 'sign_off_at', w.sign_off_at),
    'materials', coalesce((select jsonb_agg(jsonb_build_object('name', m.name, 'quantity', m.quantity,
                              'unit', m.unit, 'ready_by', m.ready_by) order by m.sort_order, m.id)
                           from public.material_items m where m.work_order_id = w.id), '[]'::jsonb),
    'schedule', coalesce((select jsonb_agg(jsonb_build_object('start_date', s.start_date, 'end_date', s.end_date,
                              'crew_name', s.crew_name, 'crew_id', s.crew_id) order by s.start_date, s.id)
                          from public.schedule_blocks s where s.work_order_id = w.id), '[]'::jsonb),
    'objective', coalesce((select o.body from public.work_order_objectives o
                           where o.work_order_id = w.id
                             and o.objective_date = (now() at time zone 'America/New_York')::date), '')
  )::text, 'UTF8')), 'hex')
  from public.work_orders w where w.id = p_work_order_id;
$function$;
revoke execute on function public.work_order_version(uuid) from public, anon;
grant execute on function public.work_order_version(uuid) to authenticated;

-- ---- the office publishes the objective ---------------------------------------------------------------------
create function public.set_work_order_objective(p_work_order_id uuid, p_body text, p_objective_date date default null)
returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare v_org uuid; v_date date; v_id uuid;
begin
  v_org := public.assert_work_order_level(p_work_order_id, 'trade');
  if not coalesce(public.can_view_master_work_order(v_org), false) then
    raise exception 'your role cannot publish the day''s objective in this workspace' using hint = 'not_office';
  end if;
  if nullif(btrim(p_body), '') is null then
    raise exception 'say what the crew is meant to achieve, or remove the objective' using hint = 'body_required';
  end if;
  v_date := coalesce(p_objective_date, (now() at time zone 'America/New_York')::date);

  insert into public.work_order_objectives (org_id, work_order_id, objective_date, body, published_by)
  values (v_org, p_work_order_id, v_date, btrim(p_body), auth.uid())
  on conflict (work_order_id, objective_date) do update
    set body = excluded.body, published_by = excluded.published_by, published_at = now(), updated_at = now()
    where work_order_objectives.body is distinct from excluded.body  -- RULE 10: re-publishing the same words changes nothing
  returning id into v_id;

  if v_id is null then
    select id into v_id from public.work_order_objectives
    where work_order_id = p_work_order_id and objective_date = v_date;
  end if;
  return v_id;
end;
$function$;
revoke execute on function public.set_work_order_objective(uuid, text, date) from public, anon;
grant execute on function public.set_work_order_objective(uuid, text, date) to authenticated;

create function public.clear_work_order_objective(p_work_order_id uuid, p_objective_date date default null)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare v_org uuid;
begin
  v_org := public.assert_work_order_level(p_work_order_id, 'trade');
  if not coalesce(public.can_view_master_work_order(v_org), false) then
    raise exception 'your role cannot change the day''s objective in this workspace' using hint = 'not_office';
  end if;
  delete from public.work_order_objectives
  where work_order_id = p_work_order_id
    and objective_date = coalesce(p_objective_date, (now() at time zone 'America/New_York')::date);
end;
$function$;
revoke execute on function public.clear_work_order_objective(uuid, date) from public, anon;
grant execute on function public.clear_work_order_objective(uuid, date) to authenticated;

-- ---- the crew acknowledges --------------------------------------------------------------------------------
create function public.acknowledge_work_order(p_work_order_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_org uuid; v_version text; v_at timestamptz;
begin
  -- Declines for anyone the work_orders guard would hide this from, and for a master.
  v_org := public.assert_work_order_level(p_work_order_id, 'trade');
  v_version := public.work_order_version(p_work_order_id);

  insert into public.work_order_acknowledgments (org_id, work_order_id, acknowledged_by, work_order_version)
  values (v_org, p_work_order_id, auth.uid(), v_version)
  on conflict (work_order_id, acknowledged_by, work_order_version) do nothing;  -- RULE 10

  select acknowledged_at into v_at from public.work_order_acknowledgments
  where work_order_id = p_work_order_id and acknowledged_by = auth.uid() and work_order_version = v_version;

  return jsonb_build_object('state', 'acknowledged', 'acknowledged_at', v_at, 'work_order_version', v_version);
end;
$function$;
revoke execute on function public.acknowledge_work_order(uuid) from public, anon;
grant execute on function public.acknowledge_work_order(uuid) to authenticated;

-- ---- one read for the screen: the objective, the version, and who has acknowledged which version ------------
-- No money is reachable from here: no column of any priced table is read, and the caller who cannot see the
-- work order gets the refusal from assert_work_order_level rather than a partial row.
create function public.fetch_work_order_brief(p_work_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare v_org uuid; v_version text; v_today date; v_mine public.work_order_acknowledgments; v_my jsonb;
begin
  v_org := public.assert_work_order_level(p_work_order_id, 'trade');
  v_version := public.work_order_version(p_work_order_id);
  v_today := (now() at time zone 'America/New_York')::date;

  select * into v_mine from public.work_order_acknowledgments a
  where a.work_order_id = p_work_order_id and a.acknowledged_by = auth.uid()
  order by a.acknowledged_at desc limit 1;

  v_my := case
    when v_mine.id is null then jsonb_build_object('state', 'not_acknowledged')
    when v_mine.work_order_version = v_version
      then jsonb_build_object('state', 'acknowledged', 'acknowledged_at', v_mine.acknowledged_at)
    else jsonb_build_object('state', 'scope_changed_since', 'acknowledged_at', v_mine.acknowledged_at)
  end;

  return jsonb_build_object(
    'work_order_id', p_work_order_id,
    'today', v_today,
    'work_order_version', v_version,
    'objective', (select jsonb_build_object('body', o.body, 'objective_date', o.objective_date,
                           'published_at', o.published_at,
                           'published_by_name', (select m.full_name from public.org_members m
                                                 where m.org_id = o.org_id and m.user_id = o.published_by))
                  from public.work_order_objectives o
                  where o.work_order_id = p_work_order_id and o.objective_date = v_today),
    'my_acknowledgment', v_my,
    'acknowledgments', coalesce((
      select jsonb_agg(jsonb_build_object(
               'person', coalesce((select m.full_name from public.org_members m
                                   where m.org_id = a.org_id and m.user_id = a.acknowledged_by), 'a member'),
               'acknowledged_at', a.acknowledged_at,
               'state', case when a.work_order_version = v_version then 'current' else 'scope_changed_since' end)
             order by a.acknowledged_at desc)
      from public.work_order_acknowledgments a where a.work_order_id = p_work_order_id), '[]'::jsonb));
end;
$function$;
revoke execute on function public.fetch_work_order_brief(uuid) from public, anon;
grant execute on function public.fetch_work_order_brief(uuid) to authenticated;
