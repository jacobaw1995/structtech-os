-- S-W1.1 · migration 1 of 2 · 2026-09-02 (America/New_York)
-- Closes six of the seven cross-tenant findings recorded in
-- docs/CROSS_TENANT_AUDIT_20260901.md §8: the five SECURITY DEFINER config
-- readers (finding 2) and the generate_roadmap_for_lead chain (finding 1).
--
-- WHY THE ENTRY POINTS SPLIT FROM THE CORES -- MEASURED, NOT ASSUMED.
-- The five config readers have ZERO application callers (repo-wide sweep of
-- src/ found only generated types and two comments) but SIX in-database
-- callers, every one of them SECURITY DEFINER. Four of the six --
-- create_deal, update_deal_stage, create_tracker_item, update_tracker_item --
-- already guard `v_org_id not in (select my_org_ids())` before they call, so
-- for those the guard added below is a re-check that always passes. The other
-- two are TRIGGERS and guard nothing:
--   auto_create_deal        AFTER INSERT ON audit_leads  -> crm_follow_up_cadence_days
--   deal_stage_side_effects BEFORE UPDATE ON deals       -> crm_stage_entry
-- audit_leads carries an `Allow anon insert` policy, so that first trigger is
-- THE PUBLIC LEAD FORM. Proved in a rolled-back transaction on 2026-09-02:
-- with auto_create_deal pointed at the GUARDED name, an anonymous lead-form
-- insert FAILS with `P0001 not a member of organization 034db6f4-...`,
-- because auth.uid() is NULL there and my_org_ids() is empty. Pointed at the
-- _internal core it succeeds, auto-creates the deal, and schedules both
-- follow-ups on StructTech's real configured [2, 5] cadence.
-- The guard therefore belongs at the API boundary, not inside a reader a
-- trigger also uses.
--
-- REFUSAL, NOT AN EMPTY RESULT, and the shape is not invented: it is the one
-- 18 of our 23 org-parameterised definers already use, taken verbatim from
-- create_deal / create_roadmap_project / create_tracker_item / list_org_members.
-- An empty result would have been actively WRONG for
-- crm_follow_up_cadence_days, whose coalesce returns array[2,5]: a denial
-- would have been indistinguishable from real configuration (rule 11 form 2).
--
-- The `p_org_id is null or` leg is CLAUDE.md rule 5: PL/pgSQL treats a NULL
-- `IF` condition as FALSE, so `p_org_id not in (...)` alone would ALLOW a NULL org.

-- ---------------------------------------------------------------------------
-- 1 · INTERNAL CORES -- no caller check, not reachable from outside the database
-- ---------------------------------------------------------------------------

create or replace function public.crm_stage_config_internal(p_org_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(tm.config -> 'stages', '[]'::jsonb)
  from public.tenant_modules tm
  where tm.org_id = p_org_id
    and tm.module_key = 'crm'
  limit 1;
$$;

comment on function public.crm_stage_config_internal(uuid) is
  'Unguarded core of crm_stage_config. Called only from inside the database by SECURITY DEFINER paths. EXECUTE deliberately revoked from authenticated -- S-W1.1, 2026-09-02.';

create or replace function public.crm_stage_entry_internal(p_org_id uuid, p_stage_key text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select stage
  from jsonb_array_elements(public.crm_stage_config_internal(p_org_id)) as stage
  where stage ->> 'key' = p_stage_key
  limit 1;
$$;

comment on function public.crm_stage_entry_internal(uuid, text) is
  'Unguarded core of crm_stage_entry. Called only from deal_stage_side_effects. EXECUTE deliberately revoked from authenticated -- S-W1.1, 2026-09-02.';

create or replace function public.crm_follow_up_cadence_days_internal(p_org_id uuid)
returns integer[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select array_agg((x)::int order by ordinality)
      from jsonb_array_elements_text(
        (select tm.config -> 'follow_up_cadence_days'
         from public.tenant_modules tm
         where tm.org_id = p_org_id and tm.module_key = 'crm'
         limit 1)
      ) with ordinality as t(x, ordinality)
    ),
    array[2, 5]
  );
$$;

comment on function public.crm_follow_up_cadence_days_internal(uuid) is
  'Unguarded core of crm_follow_up_cadence_days. Called only from auto_create_deal, which is the ANONYMOUS lead-form path. EXECUTE deliberately revoked from authenticated -- S-W1.1, 2026-09-02.';

-- ---------------------------------------------------------------------------
-- 2 · THE FIVE GRANTED ENTRY POINTS -- now constrain on the org they are given
-- ---------------------------------------------------------------------------

create or replace function public.crm_stage_config(p_org_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_org_id is null or p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of organization %', p_org_id;
  end if;
  return public.crm_stage_config_internal(p_org_id);
end;
$$;

create or replace function public.crm_stage_entry(p_org_id uuid, p_stage_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_org_id is null or p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of organization %', p_org_id;
  end if;
  return public.crm_stage_entry_internal(p_org_id, p_stage_key);
end;
$$;

create or replace function public.crm_follow_up_cadence_days(p_org_id uuid)
returns integer[]
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_org_id is null or p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of organization %', p_org_id;
  end if;
  return public.crm_follow_up_cadence_days_internal(p_org_id);
end;
$$;

-- tracker_status_config and tracker_type_config get NO _internal twin: their
-- only in-database callers are create_tracker_item and update_tracker_item,
-- both of which already establish membership before calling.

create or replace function public.tracker_status_config(p_org_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_org_id is null or p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of organization %', p_org_id;
  end if;
  return (
    select coalesce(tm.config -> 'statuses', '[]'::jsonb)
    from public.tenant_modules tm
    where tm.org_id = p_org_id
      and tm.module_key = 'tracker'
    limit 1
  );
end;
$$;

create or replace function public.tracker_type_config(p_org_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_org_id is null or p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of organization %', p_org_id;
  end if;
  return (
    select coalesce(tm.config -> 'types', '[]'::jsonb)
    from public.tenant_modules tm
    where tm.org_id = p_org_id
      and tm.module_key = 'tracker'
    limit 1
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 3 · RE-POINT THE TWO TRIGGER PATHS AT THE CORES
--     Bodies are otherwise byte-identical to what was live on 2026-09-02.
-- ---------------------------------------------------------------------------

create or replace function public.auto_create_deal()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  d_id uuid;
  v_org_id uuid;
  v_cadence int[];
begin
  select id into v_org_id
  from public.organizations
  where tenant_type = 'internal'
  order by created_at asc
  limit 1;

  insert into public.deals (org_id, lead_id, contact_name, company, email, trade, crew_size, stage, source)
  values (v_org_id, new.id, coalesce(new.name,'—'), new.company, new.email, new.trade, new.crew_size, 'new_scan', 'scan')
  returning id into d_id;

  insert into public.deal_activity (deal_id, org_id, action, to_value) values (d_id, v_org_id, 'created', 'from scan');

  -- follow-up sequence (only if we have an email)
  if new.email is not null and new.email like '%@%' then
    -- S-W1.1: _internal core. This path is reached by ANONYMOUS lead-form
    -- inserts, where auth.uid() is NULL, so the guarded entry point refuses
    -- and aborts the submission. Proved by control, 2026-09-02.
    v_cadence := public.crm_follow_up_cadence_days_internal(v_org_id);
    if coalesce(array_length(v_cadence, 1), 0) < 2 then
      v_cadence := array[2, 5];
    end if;

    insert into public.follow_ups (deal_id, org_id, send_at, to_email, subject, body) values
    (d_id, v_org_id, now() + make_interval(days => v_cadence[1]), new.email,
     'Quick question about your Revenue Leak Report, ' || coalesce(split_part(new.name,' ',1),'') ,
     'Hey ' || coalesce(split_part(new.name,' ',1),'there') || E',\n\nJacob here from StructTech. Your scan flagged about $' || coalesce(new.monthly_leak,0) || E'/month leaking out of your operation — did the report line up with what you''re seeing day to day?\n\nIf you want to walk through it live, grab 30 minutes here: structtek.com/operational-audit\n\nNo pitch — just your numbers.\n\nJacob Walker\nStructTech LLC · 937.467.2660'),
    (d_id, v_org_id, now() + make_interval(days => v_cadence[2]), new.email,
     'The ' || coalesce(new.trade,'contractor') || ' math on $' || coalesce(new.monthly_leak,0) || '/month',
     'Hey ' || coalesce(split_part(new.name,' ',1),'there') || E',\n\nLast note from me. That $' || coalesce(new.monthly_leak,0) || E'/month your scan surfaced doesn''t fix itself — it compounds. Most crews your size get the first system live inside 30 days.\n\nIf now''s not the time, no sweat. If it is: structtek.com/operational-audit\n\nJacob');
    insert into public.deal_activity (deal_id, org_id, action, to_value)
    values (d_id, v_org_id, 'followup_scheduled', 'day-' || v_cadence[1] || ' + day-' || v_cadence[2]);
  end if;

  return new;
end $function$;

create or replace function public.deal_stage_side_effects()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_stage_entry jsonb;
  v_org_tenant_type text;
  v_actor_id uuid;
begin
  if new.stage <> old.stage then
    select id into v_actor_id from public.profiles where id = auth.uid();

    insert into public.deal_activity (deal_id, org_id, action, from_value, to_value, actor_id)
    values (new.id, new.org_id, 'stage_changed', old.stage, new.stage, v_actor_id);

    -- S-W1.1: _internal core. A trigger has no caller-supplied org to
    -- constrain on -- the row operation that fired it was already mediated
    -- by RLS.
    v_stage_entry := public.crm_stage_entry_internal(new.org_id, new.stage);

    if coalesce((v_stage_entry ->> 'cancel_pending_follow_ups')::boolean, false) then
      update public.follow_ups set status = 'cancelled'
      where deal_id = new.id and status = 'pending';
    end if;

    if (v_stage_entry ->> 'outcome') in ('won', 'lost') then
      new.closed_at := now();
    end if;

    if (v_stage_entry ->> 'outcome') = 'won' then
      select o.tenant_type into v_org_tenant_type
      from public.organizations o
      where o.id = new.org_id;

      if v_org_tenant_type = 'internal' then
        begin
          perform public.create_engagement_from_roadmap(new.id);
        exception when others then
          insert into public.deal_activity (deal_id, org_id, action, to_value, actor_id)
          values (new.id, new.org_id, 'engagement_materialize_failed', sqlerrm, v_actor_id);
        end;
      end if;
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4 · THE ROADMAP CHAIN -- finding 1
--
-- The missing check is "may this caller READ this lead". audit_leads answers
-- that with two policies: `staff all audit_leads` (is_staff()) and
-- `member read own audit_leads` (org_id in my_org_ids()).
--
-- STATED PLAINLY RATHER THAN GLOSSED: this RESTATES that predicate, it does
-- not delegate to it, and it cannot. `postgres` holds rolbypassrls (measured
-- 2026-09-02) and owns audit_leads, so NO read taken inside a SECURITY
-- DEFINER function owned by postgres is ever RLS-evaluated -- and the INSERT
-- into client_roadmaps needs the definer bit, because client_roadmaps has no
-- INSERT policy at all. The coupling is deliberate and is this function's
-- Rule 13 answer: it reopens if somebody widens audit_leads' read policies
-- without widening this predicate to match.
--
-- fetch_roadmap_by_token is deliberately NOT changed. It is the intended
-- anonymous client read path, it does not return token/lead_id/org_id, and
-- anon is still NOT granted EXECUTE on it.
-- ---------------------------------------------------------------------------

create or replace function public.generate_roadmap_for_lead(p_lead_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $function$
declare
  lead record; lvls jsonb; new_token text;
begin
  if not exists (
    select 1
    from public.audit_leads al
    where al.id = p_lead_id
      and (public.is_staff() or al.org_id in (select public.my_org_ids()))
  ) then
    raise exception 'lead not found or not accessible: %', p_lead_id;
  end if;

  select * into lead from public.audit_leads where id = p_lead_id;
  if not found then raise exception 'lead not found'; end if;
  lvls := public.build_roadmap_levels(lead.answers, lead.crew_size);
  insert into public.client_roadmaps
    (lead_id, client_name, company, trade, crew_size, score, risk_level, revenue_leak_monthly, levels)
  values
    (lead.id, coalesce(lead.name,'—'), coalesce(lead.company,'—'), lead.trade, lead.crew_size,
     lead.score, lead.risk_level, lead.monthly_leak, lvls)
  returning token into new_token;
  return new_token;
end $function$;

-- ---------------------------------------------------------------------------
-- 5 · CLOSING GRANT STATEMENTS -- CLAUDE.md rule 7.
-- Measured 2026-09-02: pg_default_acl (postgres -> public, objtype f) grants
-- {postgres, authenticated, service_role}. PUBLIC and anon are already absent
-- there, but the revoke is stated anyway. `authenticated` is revoked ONLY on
-- the three _internal cores, where rule 7's carve-out test -- "does anything
-- outside the database call this?" -- was answered per function and came back
-- NO. The five granted entry points KEEP their authenticated EXECUTE: that
-- grant is the intended call path once the UI wires them up, and the guard
-- above is what makes it safe.
-- ---------------------------------------------------------------------------

revoke execute on function public.crm_stage_config_internal(uuid) from public, anon, authenticated;
revoke execute on function public.crm_stage_entry_internal(uuid, text) from public, anon, authenticated;
revoke execute on function public.crm_follow_up_cadence_days_internal(uuid) from public, anon, authenticated;

revoke execute on function public.crm_stage_config(uuid) from public, anon;
revoke execute on function public.crm_stage_entry(uuid, text) from public, anon;
revoke execute on function public.crm_follow_up_cadence_days(uuid) from public, anon;
revoke execute on function public.tracker_status_config(uuid) from public, anon;
revoke execute on function public.tracker_type_config(uuid) from public, anon;
revoke execute on function public.generate_roadmap_for_lead(uuid) from public, anon;
revoke execute on function public.auto_create_deal() from public, anon;
revoke execute on function public.deal_stage_side_effects() from public, anon;