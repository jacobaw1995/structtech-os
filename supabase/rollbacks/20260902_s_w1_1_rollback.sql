-- ROLLBACK for S-W1.1 (2026-09-02)
--   20260902220001_s_w1_1_close_cross_tenant_config_readers_and_roadmap_chain
--   20260902220225_s_w1_1_pin_profiles_role_against_self_promotion
--
-- GENERATED BEFORE EITHER MIGRATION WAS APPLIED, from pg_get_functiondef()
-- and pg_policies on the live database. The md5 of each pre-change definition
-- is recorded beside it so a future reader can tell whether this file still
-- describes the state it was written against.
--
-- WARNING, and it is the point of the file rather than a footnote: running
-- this REOPENS all seven findings in docs/CROSS_TENANT_AUDIT_20260901.md §8.
-- The five config readers accept any p_org_id again, generate_roadmap_for_lead
-- performs no caller check again, and any authenticated user can self-promote
-- profiles.role to manager again. Do not run it to "clean up"; run it only to
-- recover from a defect in the migrations themselves.
--
-- Pre-change definition md5s (pg_get_functiondef), measured 2026-09-02:
--   auto_create_deal()                        8f2ac2b009c7c40ed9396b16bcb345a1  (2447 B)
--   crm_follow_up_cadence_days(uuid)          22b0095e390257425ee192b837c4c634  ( 549 B)
--   crm_stage_config(uuid)                    6366c76f319c4cfaea511f8dbf3ffe77  ( 330 B)
--   crm_stage_entry(uuid, text)               13a419fe8f0fd9d961f12876a9b108ce  ( 327 B)
--   deal_stage_side_effects()                 568d68cc6cc7117dbc6496933f5319a2  (1520 B)
--   generate_roadmap_for_lead(uuid)           a8cecbba09839abe72de2bf87dd765b3  ( 796 B)
--   tracker_status_config(uuid)               7aa8a99a1534b5d19b8bc5a3b8606616  ( 341 B)
--   tracker_type_config(uuid)                 6198fe92919947a61a7c1fed686e61d2  ( 336 B)
--
-- Pre-change policy, measured 2026-09-02:
--   pipeline_profiles_update_own on public.profiles
--     FOR UPDATE TO authenticated USING (id = auth.uid())   with_check: NULL

-- ---------------------------------------------------------------------------
-- 1 · restore the five config readers to their unguarded pre-S-W1.1 bodies
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.crm_stage_config(p_org_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(tm.config -> 'stages', '[]'::jsonb)
  from public.tenant_modules tm
  where tm.org_id = p_org_id
    and tm.module_key = 'crm'
  limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.crm_stage_entry(p_org_id uuid, p_stage_key text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select stage
  from jsonb_array_elements(public.crm_stage_config(p_org_id)) as stage
  where stage ->> 'key' = p_stage_key
  limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.crm_follow_up_cadence_days(p_org_id uuid)
 RETURNS integer[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.tracker_status_config(p_org_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(tm.config -> 'statuses', '[]'::jsonb)
  from public.tenant_modules tm
  where tm.org_id = p_org_id
    and tm.module_key = 'tracker'
  limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.tracker_type_config(p_org_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(tm.config -> 'types', '[]'::jsonb)
  from public.tenant_modules tm
  where tm.org_id = p_org_id
    and tm.module_key = 'tracker'
  limit 1;
$function$;

-- ---------------------------------------------------------------------------
-- 2 · restore generate_roadmap_for_lead (no caller check)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.generate_roadmap_for_lead(p_lead_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  lead record; lvls jsonb; new_token text;
begin
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
-- 3 · re-point the two triggers at the granted names
--     (must run AFTER section 1, or the triggers call guarded functions)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.auto_create_deal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    v_cadence := public.crm_follow_up_cadence_days(v_org_id);
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

CREATE OR REPLACE FUNCTION public.deal_stage_side_effects()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_stage_entry jsonb;
  v_org_tenant_type text;
  v_actor_id uuid;
begin
  if new.stage <> old.stage then
    select id into v_actor_id from public.profiles where id = auth.uid();

    insert into public.deal_activity (deal_id, org_id, action, from_value, to_value, actor_id)
    values (new.id, new.org_id, 'stage_changed', old.stage, new.stage, v_actor_id);

    v_stage_entry := public.crm_stage_entry(new.org_id, new.stage);

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
-- 4 · drop the three internal cores (nothing references them after section 3)
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.crm_stage_entry_internal(p_org_id uuid, p_stage_key text);
DROP FUNCTION IF EXISTS public.crm_stage_config_internal(p_org_id uuid);
DROP FUNCTION IF EXISTS public.crm_follow_up_cadence_days_internal(p_org_id uuid);
-- Signatures copied from pg_get_function_identity_arguments(). CLAUDE.md rule 2:
-- `DROP FUNCTION IF EXISTS` with a mistyped signature SILENTLY SUCCEEDS, so after
-- running this, re-query pg_proc and confirm all three are actually gone.

-- ---------------------------------------------------------------------------
-- 5 · restore the self-writable profiles UPDATE policy
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "pipeline_profiles_update_own" ON public.profiles;
CREATE POLICY "pipeline_profiles_update_own" ON public.profiles
  FOR UPDATE TO authenticated
  USING (id = auth.uid());

DROP FUNCTION IF EXISTS public.my_pipeline_role();
