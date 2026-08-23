-- STRUCTTECH OS — SCHEMA BASELINE. Taken 2026-08-23 by task A1.0.
--
-- This file is the repo's starting point for schema. Everything before it lives in
-- _archive_pre_baseline/ (superseded, not deleted) and in the ledger's own
-- `statements` column, archived at backups/a1_0_pre_baseline_20260823/.
--
-- HOW IT WAS TAKEN, and why not `supabase db pull`:
--   pg_dump --schema-only --schema=public --schema=archive, over the session pooler
--   via --db-url. WITH privileges and owners (no --no-owner, no --no-privileges):
--   483 GRANT and 117 REVOKE statements are load-bearing here — A1.5's anon sweep
--   and the §6.9 hardening ARE those statements, and a baseline without them would
--   silently reproduce a database where that work never happened.
--   Supabase-managed schemas (auth, storage, realtime, vault, graphql,
--   graphql_public, pgbouncer, extensions) and supabase_migrations itself are
--   EXCLUDED. A baseline that recreates auth.users or the migration ledger is not
--   a baseline.
--   `supabase db pull` was NOT used: it can write to supabase_migrations, and
--   pg_dump physically cannot. On a task whose purpose is protecting that table,
--   the instrument that cannot touch it is the correct one.
--   The project was never linked; every read went through --db-url.
--
-- VERIFIED BY RESTORE AND CENSUS, NOT BY READING — restored into local
-- PostgreSQL 17.11 and compared to production on four axes:
--   1. counts      77 tables / 310 functions / 189 policies / 20 archive tables — EXACT
--   2. policies    full list incl. qual and with_check, 211 lines — ZERO-LINE DIFF
--   3. privileges  688 ACL entries over our own objects — ZERO-LINE DIFF
--                  (188 btree_gist extension-member ACLs are absent by design:
--                   pg_dump does not dump extension members. Zero of our own 122
--                   functions differ. `archive` schema ACL differs in
--                   representation only — anon/authenticated USAGE and SELECT
--                   both read false on production AND on the restore.)
--   4. objects     950 relations/functions/types/constraints/triggers/RLS flags,
--                  ZERO present in one and not the other
--
-- NOT a record of history. It is a snapshot of state on the date above. History is
-- evidence and lives elsewhere; this file is where discipline starts.

--
-- PostgreSQL database dump
--

\restrict v65cSZxwHh7NPmbCQZP8bi13kGeUWfazdJdYsLdQFKqPobjBam6dSRfCeYx85Ia

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.3

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: archive; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA archive;


ALTER SCHEMA archive OWNER TO postgres;

--
-- Name: SCHEMA archive; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON SCHEMA archive IS 'Point-in-time data snapshots kept out of the API surface. Not exposed to anon/authenticated. Safe to prune once a change is verified in production.';


--
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--

CREATE SCHEMA public;


ALTER SCHEMA public OWNER TO pg_database_owner;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: lead_activity_action; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.lead_activity_action AS ENUM (
    'created',
    'stage_changed',
    'status_changed',
    'reassigned',
    'value_set',
    'edited'
);


ALTER TYPE public.lead_activity_action OWNER TO postgres;

--
-- Name: lead_source; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.lead_source AS ENUM (
    'webhook',
    'manual',
    'referral'
);


ALTER TYPE public.lead_source OWNER TO postgres;

--
-- Name: lead_stage; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.lead_stage AS ENUM (
    'lead_captured',
    'qualified',
    'proposal_sent',
    'negotiating',
    'closed'
);


ALTER TYPE public.lead_stage OWNER TO postgres;

--
-- Name: lead_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.lead_status AS ENUM (
    'active',
    'closed_won',
    'closed_lost'
);


ALTER TYPE public.lead_status OWNER TO postgres;

--
-- Name: membership_context; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.membership_context AS (
	org_id uuid,
	org_name text,
	tenant_type text,
	role text,
	entitled_modules text[]
);


ALTER TYPE public.membership_context OWNER TO postgres;

--
-- Name: pipeline_user_role; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.pipeline_user_role AS ENUM (
    'salesman',
    'manager'
);


ALTER TYPE public.pipeline_user_role OWNER TO postgres;

--
-- Name: accept_invite(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.accept_invite(p_token text, p_full_name text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare inv record;
begin
  select * into inv from public.org_invites where token = p_token and accepted_at is null;
  if not found then raise exception 'invalid or used invite'; end if;
  if auth.uid() is null then raise exception 'not signed in'; end if;

  insert into public.org_members (org_id, user_id, role, full_name)
  values (inv.org_id, auth.uid(), inv.role, p_full_name)
  on conflict (org_id, user_id) do nothing;

  update public.org_invites set accepted_at = now() where id = inv.id;
  return inv.org_id;
end $$;


ALTER FUNCTION public.accept_invite(p_token text, p_full_name text) OWNER TO postgres;

--
-- Name: accept_pipeline_invite(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.accept_pipeline_invite(p_token text, p_full_name text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare inv record; u_email text;
begin
  select * into inv from public.pipeline_invites where token = p_token and accepted_at is null;
  if not found then raise exception 'invalid or used invite'; end if;
  if auth.uid() is null then raise exception 'not signed in'; end if;

  select email into u_email from auth.users where id = auth.uid();

  insert into public.profiles (id, full_name, email, role)
  values (auth.uid(), coalesce(p_full_name, u_email), u_email, inv.role)
  on conflict (id) do nothing;

  update public.pipeline_invites set accepted_at = now() where id = inv.id;
end;
$$;


ALTER FUNCTION public.accept_pipeline_invite(p_token text, p_full_name text) OWNER TO postgres;

--
-- Name: accept_staff_invite(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.accept_staff_invite(p_token text, p_full_name text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare inv record; u_email text;
begin
  select * into inv from public.staff_invites where token = p_token and accepted_at is null;
  if not found then raise exception 'invalid or used invite'; end if;
  if auth.uid() is null then raise exception 'not signed in'; end if;

  select email into u_email from auth.users where id = auth.uid();

  insert into public.staff_users (user_id, role, full_name, email)
  values (auth.uid(), inv.role, p_full_name, u_email)
  on conflict (user_id) do nothing;

  update public.staff_invites set accepted_at = now() where id = inv.id;
end;
$$;


ALTER FUNCTION public.accept_staff_invite(p_token text, p_full_name text) OWNER TO postgres;

--
-- Name: add_check_in_photo(uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_check_in_photo(p_check_in_id uuid, p_photo_data_url text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.check_ins where id = p_check_in_id;

  if v_org_id is null then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  update public.check_ins
  set photos = array_append(photos, p_photo_data_url),
      updated_at = now()
  where id = p_check_in_id;
end;
$$;


ALTER FUNCTION public.add_check_in_photo(p_check_in_id uuid, p_photo_data_url text) OWNER TO postgres;

--
-- Name: add_deal_note(uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_deal_note(p_deal_id uuid, p_content text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_note_id uuid;
  v_created_by uuid;
begin
  select org_id into v_org_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not public.has_capability(v_org_id, 'add_notes') then
    raise exception 'not authorized: add_notes capability required to add a note';
  end if;

  select id into v_created_by from public.profiles where id = auth.uid();

  insert into public.deal_notes (deal_id, org_id, content, created_by)
  values (p_deal_id, v_org_id, p_content, v_created_by)
  returning id into v_note_id;

  insert into public.deal_activity (deal_id, org_id, action, to_value, actor_id)
  values (p_deal_id, v_org_id, 'note_added', left(p_content, 140), v_created_by);

  return v_note_id;
end;
$$;


ALTER FUNCTION public.add_deal_note(p_deal_id uuid, p_content text) OWNER TO postgres;

--
-- Name: add_estimate_line_item(uuid, text, numeric, numeric, uuid, integer, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_estimate_line_item(p_estimate_id uuid, p_description text, p_quantity numeric DEFAULT 1, p_unit_price numeric DEFAULT 0, p_product_id uuid DEFAULT NULL::uuid, p_sort_order integer DEFAULT 0, p_unit text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_status text;
  v_line_id uuid;
begin
  select org_id, status into v_org_id, v_status
  from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  if v_status in ('signed', 'void') then
    raise exception 'estimate % is locked (status: %) — line items can only change before signing', p_estimate_id, v_status;
  end if;

  insert into public.estimate_line_items
    (org_id, estimate_id, product_id, description, quantity, unit_price, sort_order, unit)
  values
    (v_org_id, p_estimate_id, p_product_id, p_description, p_quantity, p_unit_price, p_sort_order, p_unit)
  returning id into v_line_id;

  return v_line_id;
end;
$$;


ALTER FUNCTION public.add_estimate_line_item(p_estimate_id uuid, p_description text, p_quantity numeric, p_unit_price numeric, p_product_id uuid, p_sort_order integer, p_unit text) OWNER TO postgres;

--
-- Name: add_material_item(uuid, text, numeric, date, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_material_item(p_work_order_id uuid, p_name text, p_quantity numeric DEFAULT 1, p_ready_by date DEFAULT NULL::date, p_sort_order integer DEFAULT 0) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_master_id uuid;
  v_sign_off_at timestamptz;
  v_trade text;
  v_item_id uuid;
  v_actor_id uuid;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');

  select w.trade into v_trade from public.work_orders w where w.id = p_work_order_id;
  select s.master_id, s.sign_off_at into v_master_id, v_sign_off_at
  from public.job_master_sign_off(p_work_order_id) s;

  insert into public.material_items (org_id, work_order_id, name, quantity, ready_by, sort_order)
  values (v_org_id, p_work_order_id, p_name, p_quantity, p_ready_by, p_sort_order)
  returning id into v_item_id;

  if v_sign_off_at is not null then
    select id into v_actor_id from public.profiles where id = auth.uid();
    insert into public.work_order_activity (work_order_id, org_id, action, to_value, actor_id)
    values (v_master_id, v_org_id, 'material_added_after_signoff',
            format('%s (%s)', p_name, coalesce(v_trade, 'trade')), v_actor_id);
  end if;

  return v_item_id;
end;
$$;


ALTER FUNCTION public.add_material_item(p_work_order_id uuid, p_name text, p_quantity numeric, p_ready_by date, p_sort_order integer) OWNER TO postgres;

--
-- Name: add_org_member(uuid, uuid, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_org_member(p_org_id uuid, p_user_id uuid, p_role text, p_full_name text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not is_platform_admin() then
    raise exception 'only a platform admin can add org members';
  end if;

  insert into public.org_members (org_id, user_id, role, full_name)
  values (p_org_id, p_user_id, p_role, p_full_name)
  on conflict (org_id, user_id) do update
    set role = excluded.role,
        full_name = excluded.full_name;
end;
$$;


ALTER FUNCTION public.add_org_member(p_org_id uuid, p_user_id uuid, p_role text, p_full_name text) OWNER TO postgres;

--
-- Name: add_production_packet_callout(uuid, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_production_packet_callout(p_production_packet_id uuid, p_label text, p_detail text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_work_order_id uuid;
  v_callout_id uuid := gen_random_uuid();
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.production_packets where id = p_production_packet_id;

  if v_org_id is null then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  update public.production_packets
  set callouts = callouts || jsonb_build_array(
        jsonb_build_object('id', v_callout_id, 'label', p_label, 'detail', p_detail)
      ),
      updated_at = now()
  where id = p_production_packet_id;

  return v_callout_id;
end;
$$;


ALTER FUNCTION public.add_production_packet_callout(p_production_packet_id uuid, p_label text, p_detail text) OWNER TO postgres;

--
-- Name: add_schedule_block(uuid, text, date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_schedule_block(p_work_order_id uuid, p_crew_name text, p_start_date date, p_end_date date) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_block_id uuid;
  v_blocking_name text;
  v_blocking_ready_by date;
  v_blocked boolean;
  v_reason text;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');

  select name, ready_by into v_blocking_name, v_blocking_ready_by
  from public.material_items
  where work_order_id = p_work_order_id and ready_by is not null
  order by ready_by desc
  limit 1;

  v_blocked := v_blocking_ready_by is not null and p_start_date < v_blocking_ready_by;
  v_reason := case when v_blocked
    then format('blocked on %s (ready %s)', v_blocking_name, v_blocking_ready_by)
    else null
  end;

  insert into public.schedule_blocks
    (org_id, work_order_id, crew_name, start_date, end_date, blocked, blocked_reason)
  values
    (v_org_id, p_work_order_id, p_crew_name, p_start_date, p_end_date, v_blocked, v_reason)
  returning id into v_block_id;

  return v_block_id;
end;
$$;


ALTER FUNCTION public.add_schedule_block(p_work_order_id uuid, p_crew_name text, p_start_date date, p_end_date date) OWNER TO postgres;

--
-- Name: archive_deal(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.archive_deal(p_deal_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_owner_id uuid;
  v_actor_id uuid;
begin
  select org_id, owner_id into v_org_id, v_owner_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (
    public.is_org_manager(v_org_id)
    or coalesce(v_owner_id = auth.uid(), false)
    or public.has_capability(v_org_id, 'edit_leads')
  ) then
    raise exception 'not authorized: only the deal owner, an org manager, or a caller with edit_leads can archive this deal';
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals set archived_at = now() where id = p_deal_id;

  update public.follow_ups set status = 'cancelled'
  where deal_id = p_deal_id and status = 'pending';

  insert into public.deal_activity (deal_id, org_id, action, actor_id)
  values (p_deal_id, v_org_id, 'archived', v_actor_id);
end;
$$;


ALTER FUNCTION public.archive_deal(p_deal_id uuid) OWNER TO postgres;

--
-- Name: archive_tracker_item(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.archive_tracker_item(p_item_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


ALTER FUNCTION public.archive_tracker_item(p_item_id uuid) OWNER TO postgres;

--
-- Name: archive_tracker_project(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.archive_tracker_project(p_project_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


ALTER FUNCTION public.archive_tracker_project(p_project_id uuid) OWNER TO postgres;

--
-- Name: assert_work_order_level(uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.assert_work_order_level(p_work_order_id uuid, p_expected_kind text) RETURNS uuid
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_kind   text;
begin
  select w.org_id, w.kind into v_org_id, v_kind
  from public.work_orders w
  where w.id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  if coalesce(v_kind, '') <> p_expected_kind then
    raise exception 'work order % is kind=% — this action requires a % work order (%)',
      p_work_order_id,
      coalesce(v_kind, '(null)'),
      p_expected_kind,
      case p_expected_kind
        when 'trade'  then 'materials, schedule blocks, check-ins and production packets attach to trades, not to the master'
        when 'master' then 'sign-off and agreements are recorded once on the master, not per trade'
        else 'unexpected level'
      end;
  end if;

  return v_org_id;
end;
$$;


ALTER FUNCTION public.assert_work_order_level(p_work_order_id uuid, p_expected_kind text) OWNER TO postgres;

--
-- Name: assign_deal_owner(uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.assign_deal_owner(p_deal_id uuid, p_owner_id uuid DEFAULT NULL::uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_old_owner_id uuid;
  v_old_owner_name text;
  v_new_owner_name text;
  v_actor_id uuid;
begin
  select org_id, owner_id into v_org_id, v_old_owner_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (
    public.is_org_manager(v_org_id)
    or coalesce(v_old_owner_id is null and p_owner_id = auth.uid(), false)
  ) then
    raise exception 'not authorized: only an org manager can reassign; a rep may only claim an unowned lead to themselves';
  end if;

  if p_owner_id is not null and p_owner_id not in (
    select om.user_id from public.org_members om where om.org_id = v_org_id
  ) then
    raise exception 'owner % is not a member of organization %', p_owner_id, v_org_id;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  select full_name into v_old_owner_name from public.org_members
    where org_id = v_org_id and user_id = v_old_owner_id;
  select full_name into v_new_owner_name from public.org_members
    where org_id = v_org_id and user_id = p_owner_id;

  update public.deals
  set owner_id = p_owner_id,
      updated_at = now()
  where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, from_value, to_value, actor_id)
  values (
    p_deal_id, v_org_id, 'owner_assigned',
    coalesce(v_old_owner_name, 'Unassigned'),
    coalesce(v_new_owner_name, 'Unassigned'),
    v_actor_id
  );
end;
$$;


ALTER FUNCTION public.assign_deal_owner(p_deal_id uuid, p_owner_id uuid) OWNER TO postgres;

--
-- Name: auto_create_deal(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.auto_create_deal() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
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
end $_$;


ALTER FUNCTION public.auto_create_deal() OWNER TO postgres;

--
-- Name: auto_create_roadmap(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.auto_create_roadmap() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare lvls jsonb;
begin
  lvls := public.build_roadmap_levels(new.answers, new.crew_size);
  if jsonb_array_length(lvls) > 0 then
    insert into public.client_roadmaps
      (lead_id, client_name, company, trade, crew_size, score, risk_level, revenue_leak_monthly, levels)
    values
      (new.id, coalesce(new.name,'—'), coalesce(new.company,'—'), new.trade, new.crew_size,
       new.score, new.risk_level, new.monthly_leak, lvls);
  end if;
  return new;
end $$;


ALTER FUNCTION public.auto_create_roadmap() OWNER TO postgres;

--
-- Name: bmr_ticket_touch(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.bmr_ticket_touch() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at := now();
  return new;
end $$;


ALTER FUNCTION public.bmr_ticket_touch() OWNER TO postgres;

--
-- Name: build_roadmap_levels(jsonb, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.build_roadmap_levels(p_answers jsonb, p_crew integer) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $_$
declare
  w text; j text;
  areas text[] := '{}';
  worst record;
  q1s int := coalesce((p_answers->>'q1')::int, 10);
  q2s int := coalesce((p_answers->>'q2')::int, 10);
  lvls jsonb := '[]'::jsonb;
  pb jsonb; ms jsonb; li int := 0; mi int; built_ms jsonb;
  a text;
begin
  -- PROVE calibration by crew size
  if coalesce(p_crew,5) <= 4 then      w := 'One week';   j := 'Three';
  elsif coalesce(p_crew,5) <= 9 then   w := 'Two weeks';  j := 'Five';
  else                                 w := 'Three weeks'; j := 'Eight';
  end if;

  -- Sales merge: both q1 and q2 at 2 or below -> one combined level
  if q1s <= 2 and q2s <= 2 then
    areas := array['sales'];
    for worst in
      select key as q from jsonb_each_text(coalesce(p_answers,'{}'::jsonb))
      where key ~ '^q([1-9]|1[01])$' and key not in ('q1','q2')
      order by (value)::int asc, substring(key from 2)::int asc limit 2
    loop
      areas := areas || worst.q;
    end loop;
  else
    for worst in
      select key as q from jsonb_each_text(coalesce(p_answers,'{}'::jsonb))
      where key ~ '^q([1-9]|1[01])$'
      order by (value)::int asc, substring(key from 2)::int asc limit 3
    loop
      areas := areas || worst.q;
    end loop;
  end if;

  foreach a in array areas loop
    pb := public.roadmap_playbook(a);
    if pb is null then continue; end if;
    pb := replace(replace(pb::text, '{{W}}', w), '{{J}}', j)::jsonb;
    built_ms := '[]'::jsonb; mi := 0;
    for ms in select * from jsonb_array_elements(pb->'milestones') loop
      built_ms := built_ms || jsonb_build_array(jsonb_build_object(
        'id','l'||li||'m'||mi,'label',ms->>'label','owner',ms->>'owner','done',false,'done_at',null));
      mi := mi + 1;
    end loop;
    lvls := lvls || jsonb_build_array(jsonb_build_object(
      'title',pb->>'title','why',pb->>'why','area',a,'milestones',built_ms));
    li := li + 1;
  end loop;

  return lvls;
end $_$;


ALTER FUNCTION public.build_roadmap_levels(p_answers jsonb, p_crew integer) OWNER TO postgres;

--
-- Name: can_view_financials(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.can_view_financials(p_org_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce(
    case
      when public.is_org_manager(p_org_id) then true
      else (
        select coalesce(
          (m.permissions ->> 'view_financials')::boolean,
          m.role not in ('field', 'client_portal_viewer')
        )
        from public.org_members m
        where m.org_id = p_org_id and m.user_id = auth.uid()
      )
    end,
    false
  );
$$;


ALTER FUNCTION public.can_view_financials(p_org_id uuid) OWNER TO postgres;

--
-- Name: FUNCTION can_view_financials(p_org_id uuid); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.can_view_financials(p_org_id uuid) IS 'A1.5, constraint 7. True when the caller may see money in this org. Reads the SAME org_members.permissions->>''view_financials'' key as has_capability(), but its default is role-derived and closed for field/client_portal_viewer instead of has_capability()''s fails-open global array. The two disagree for a crew-tier member with no permissions row, which is the point; reconciling them is A2 work (§6.9).';


--
-- Name: can_view_master_work_order(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.can_view_master_work_order(p_org_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce(
    case
      when public.is_org_manager(p_org_id) then true
      else (
        select coalesce(
          (m.permissions ->> 'view_master_work_order')::boolean,
          m.role not in ('field', 'client_portal_viewer')
        )
        from public.org_members m
        where m.org_id = p_org_id and m.user_id = auth.uid()
      )
    end,
    false
  );
$$;


ALTER FUNCTION public.can_view_master_work_order(p_org_id uuid) OWNER TO postgres;

--
-- Name: FUNCTION can_view_master_work_order(p_org_id uuid); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.can_view_master_work_order(p_org_id uuid) IS 'A1.5. True when the caller may see MASTER work orders and master-level documents in this org. Manager roles always may; any member may be granted it explicitly via org_members.permissions->>''view_master_work_order''; otherwise field and client_portal_viewer may not and everyone else may. Deliberately separate from has_capability(), whose global fallback array fails open (§6.9).';


--
-- Name: complete_site_survey(uuid, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.complete_site_survey(p_deal_id uuid, p_completed_at timestamp with time zone DEFAULT now()) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_owner_id uuid;
  v_actor_id uuid;
begin
  select org_id, owner_id into v_org_id, v_owner_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (public.is_org_manager(v_org_id) or coalesce(v_owner_id = auth.uid(), false)) then
    raise exception 'not authorized: only the deal owner or an org manager can complete the site visit';
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals
  set site_survey_complete_at = p_completed_at,
      updated_at = now()
  where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, to_value, actor_id)
  values (p_deal_id, v_org_id, 'site_survey_completed', coalesce(p_completed_at::text, 'cleared'), v_actor_id);
end;
$$;


ALTER FUNCTION public.complete_site_survey(p_deal_id uuid, p_completed_at timestamp with time zone) OWNER TO postgres;

--
-- Name: FUNCTION complete_site_survey(p_deal_id uuid, p_completed_at timestamp with time zone); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.complete_site_survey(p_deal_id uuid, p_completed_at timestamp with time zone) IS 'Sets/clears deals.site_survey_complete_at. Explicit null param clears it; omitted param defaults to now(). No completion gating — see migration header.';


--
-- Name: create_check_in(uuid, text, uuid, date, numeric, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_check_in(p_work_order_id uuid, p_crew_name text, p_schedule_block_id uuid DEFAULT NULL::uuid, p_check_in_date date DEFAULT CURRENT_DATE, p_hours numeric DEFAULT 0, p_materials_used text DEFAULT NULL::text, p_blockers text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_check_in_id uuid;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');

  insert into public.check_ins
    (org_id, work_order_id, schedule_block_id, crew_name, check_in_date, hours, materials_used, blockers)
  values
    (v_org_id, p_work_order_id, p_schedule_block_id, p_crew_name, coalesce(p_check_in_date, current_date), coalesce(p_hours, 0), p_materials_used, p_blockers)
  returning id into v_check_in_id;

  return v_check_in_id;
end;
$$;


ALTER FUNCTION public.create_check_in(p_work_order_id uuid, p_crew_name text, p_schedule_block_id uuid, p_check_in_date date, p_hours numeric, p_materials_used text, p_blockers text) OWNER TO postgres;

--
-- Name: create_deal(uuid, text, text, text, text, numeric, text, integer, text, text, text, text, text, text, text, text, text[], text[], text, text, text, text, text, uuid, text[]); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_deal(p_org_id uuid, p_contact_name text DEFAULT NULL::text, p_company text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_value numeric DEFAULT NULL::numeric, p_trade text DEFAULT NULL::text, p_crew_size integer DEFAULT NULL::integer, p_source text DEFAULT 'manual'::text, p_lead_type text DEFAULT NULL::text, p_project_address text DEFAULT NULL::text, p_billing_address text DEFAULT NULL::text, p_first_name text DEFAULT NULL::text, p_last_name text DEFAULT NULL::text, p_secondary_phone text DEFAULT NULL::text, p_remodel_or_new_construction text DEFAULT NULL::text, p_existing_roof_type text[] DEFAULT NULL::text[], p_roof_type_requested text[] DEFAULT NULL::text[], p_service_address_street text DEFAULT NULL::text, p_service_address_city text DEFAULT NULL::text, p_service_address_state text DEFAULT NULL::text, p_service_address_zip text DEFAULT NULL::text, p_referral_name text DEFAULT NULL::text, p_owner_id uuid DEFAULT NULL::uuid, p_tags text[] DEFAULT NULL::text[]) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_deal_id uuid;
  v_first_stage text;
  v_cadence int[];
  v_contact_name text;
  v_actor_id uuid;
begin
  if p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of organization %', p_org_id;
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  v_contact_name := coalesce(
    nullif(trim(p_contact_name), ''),
    nullif(trim(concat_ws(' ', p_first_name, p_last_name)), '')
  );

  if v_contact_name is null then
    raise exception 'create_deal requires p_contact_name or p_first_name/p_last_name';
  end if;

  select stages -> 0 ->> 'key'
  into v_first_stage
  from (select public.crm_stage_config(p_org_id) as stages) s;

  if v_first_stage is null then
    raise exception 'organization % has no crm stage config', p_org_id;
  end if;

  insert into public.deals
    (org_id, contact_name, company, email, phone, value, trade, crew_size, stage, source,
     lead_type, project_address, billing_address,
     first_name, last_name, secondary_phone, remodel_or_new_construction,
     existing_roof_type, roof_type_requested,
     service_address_street, service_address_city, service_address_state, service_address_zip,
     referral_name, owner_id, tags)
  values
    (p_org_id, v_contact_name, p_company, p_email, p_phone, p_value, p_trade, p_crew_size, v_first_stage, p_source,
     p_lead_type, p_project_address, p_billing_address,
     p_first_name, p_last_name, p_secondary_phone, p_remodel_or_new_construction,
     p_existing_roof_type, p_roof_type_requested,
     p_service_address_street, p_service_address_city, p_service_address_state, p_service_address_zip,
     p_referral_name, p_owner_id, p_tags)
  returning id into v_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, to_value, actor_id)
  values (v_deal_id, p_org_id, 'created', p_source, v_actor_id);

  if p_email is not null and p_email like '%@%' then
    v_cadence := public.crm_follow_up_cadence_days(p_org_id);
    if coalesce(array_length(v_cadence, 1), 0) < 2 then
      v_cadence := array[2, 5];
    end if;

    insert into public.follow_ups (deal_id, org_id, send_at, to_email, subject, body) values
    (v_deal_id, p_org_id, now() + make_interval(days => v_cadence[1]), p_email,
     'Following up, ' || coalesce(split_part(v_contact_name,' ',1), ''),
     'Hey ' || coalesce(split_part(v_contact_name,' ',1),'there') || E',\n\nJust checking in on where things stand — happy to answer any questions.\n\n— StructTech'),
    (v_deal_id, p_org_id, now() + make_interval(days => v_cadence[2]), p_email,
     'Still here if you need anything',
     'Hey ' || coalesce(split_part(v_contact_name,' ',1),'there') || E',\n\nLast check-in from me for now — reach out whenever works.\n\n— StructTech');

    insert into public.deal_activity (deal_id, org_id, action, to_value, actor_id)
    values (v_deal_id, p_org_id, 'followup_scheduled', 'day-' || v_cadence[1] || ' + day-' || v_cadence[2], v_actor_id);
  end if;

  return v_deal_id;
end;
$$;


ALTER FUNCTION public.create_deal(p_org_id uuid, p_contact_name text, p_company text, p_email text, p_phone text, p_value numeric, p_trade text, p_crew_size integer, p_source text, p_lead_type text, p_project_address text, p_billing_address text, p_first_name text, p_last_name text, p_secondary_phone text, p_remodel_or_new_construction text, p_existing_roof_type text[], p_roof_type_requested text[], p_service_address_street text, p_service_address_city text, p_service_address_state text, p_service_address_zip text, p_referral_name text, p_owner_id uuid, p_tags text[]) OWNER TO postgres;

--
-- Name: FUNCTION create_deal(p_org_id uuid, p_contact_name text, p_company text, p_email text, p_phone text, p_value numeric, p_trade text, p_crew_size integer, p_source text, p_lead_type text, p_project_address text, p_billing_address text, p_first_name text, p_last_name text, p_secondary_phone text, p_remodel_or_new_construction text, p_existing_roof_type text[], p_roof_type_requested text[], p_service_address_street text, p_service_address_city text, p_service_address_state text, p_service_address_zip text, p_referral_name text, p_owner_id uuid, p_tags text[]); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.create_deal(p_org_id uuid, p_contact_name text, p_company text, p_email text, p_phone text, p_value numeric, p_trade text, p_crew_size integer, p_source text, p_lead_type text, p_project_address text, p_billing_address text, p_first_name text, p_last_name text, p_secondary_phone text, p_remodel_or_new_construction text, p_existing_roof_type text[], p_roof_type_requested text[], p_service_address_street text, p_service_address_city text, p_service_address_state text, p_service_address_zip text, p_referral_name text, p_owner_id uuid, p_tags text[]) IS 'Pipeline insert RPC. p_contact_name is now optional (falls back to first_name+last_name; one of the two is required — the column is NOT NULL). Extended CRM Depth Stage 2 with the full lead data model minus intake_checklist/milestones (Stage 3''s job).';


--
-- Name: create_engagement_from_roadmap(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_engagement_from_roadmap(p_deal_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


ALTER FUNCTION public.create_engagement_from_roadmap(p_deal_id uuid) OWNER TO postgres;

--
-- Name: create_estimate_from_deal(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_estimate_from_deal(p_deal_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_contact_name text;
  v_company text;
  v_phone text;
  v_email text;
  v_project_address text;
  v_service_address_street text;
  v_service_address_city text;
  v_service_address_state text;
  v_service_address_zip text;
  v_site_address text;
  v_next_number int;
  v_estimate_number text;
  v_estimate_id uuid;
begin
  select org_id, contact_name, company, phone, email, project_address,
         service_address_street, service_address_city, service_address_state, service_address_zip
  into v_org_id, v_contact_name, v_company, v_phone, v_email, v_project_address,
       v_service_address_street, v_service_address_city, v_service_address_state, v_service_address_zip
  from public.deals
  where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  -- Phase A capability gate (Interaction 2). Checked before touching the
  -- estimate_number_counters row lock below — a rejected caller should
  -- never claim a number.
  if not public.has_capability(v_org_id, 'create_estimates') then
    raise exception 'not authorized: create_estimates capability required to create an estimate';
  end if;

  v_site_address := coalesce(
    nullif(trim(concat_ws(', ',
      nullif(v_service_address_street, ''),
      nullif(v_service_address_city, ''),
      nullif(v_service_address_state, ''),
      nullif(v_service_address_zip, '')
    )), ''),
    v_project_address
  );

  insert into public.estimate_number_counters (org_id, next_number)
  values (v_org_id, 2)
  on conflict (org_id) do update set next_number = estimate_number_counters.next_number + 1
  returning next_number - 1 into v_next_number;

  v_estimate_number := 'EST-' || v_next_number;

  insert into public.estimates
    (org_id, deal_id, contact_name, company, phone, email, site_address, estimate_number, estimate_date)
  values
    (v_org_id, p_deal_id, v_contact_name, v_company, v_phone, v_email, v_site_address, v_estimate_number, current_date)
  returning id into v_estimate_id;

  return v_estimate_id;
end;
$$;


ALTER FUNCTION public.create_estimate_from_deal(p_deal_id uuid) OWNER TO postgres;

--
-- Name: create_job_from_estimate(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_job_from_estimate(p_estimate_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id    uuid;
  v_deal_id   uuid;
  v_status    text;
  v_job_id    uuid;
  v_master_id uuid;
begin
  select e.org_id, e.deal_id, e.status
    into v_org_id, v_deal_id, v_status
  from public.estimates e
  where e.id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  -- coalesce, not a bare <> : a null status makes the comparison null, and
  -- PL/pgSQL reads a null IF as false — which would let an unsigned estimate
  -- through (CLAUDE.md rule 5).
  if coalesce(v_status, '') <> 'signed' then
    raise exception 'estimate % must be signed before a job can be created (current status: %)',
      p_estimate_id, coalesce(v_status, '(null)');
  end if;

  if v_deal_id is null then
    raise exception 'estimate % has no deal — a job needs a service address', p_estimate_id;
  end if;

  select id into v_job_id
  from public.jobs
  where estimate_id = p_estimate_id;

  if v_job_id is null then
    insert into public.jobs (
      org_id, deal_id, estimate_id,
      service_address_street, service_address_city,
      service_address_state, service_address_zip
    )
    select v_org_id, v_deal_id, p_estimate_id,
           d.service_address_street, d.service_address_city,
           d.service_address_state, d.service_address_zip
    from public.deals d
    where d.id = v_deal_id
    returning id into v_job_id;

    -- insert … select inserts zero rows if the deal is gone, which would leave
    -- v_job_id null and surface as a confusing NOT NULL failure two statements
    -- later. Say what actually happened.
    if v_job_id is null then
      raise exception 'deal % for estimate % not found', v_deal_id, p_estimate_id;
    end if;
  end if;

  select id into v_master_id
  from public.work_orders
  where job_id = v_job_id
    and kind = 'master';

  if v_master_id is null then
    insert into public.work_orders (org_id, estimate_id, job_id, kind)
    values (v_org_id, p_estimate_id, v_job_id, 'master')
    returning id into v_master_id;
  end if;

  return jsonb_build_object(
    'job_id', v_job_id,
    'master_work_order_id', v_master_id
  );
end;
$$;


ALTER FUNCTION public.create_job_from_estimate(p_estimate_id uuid) OWNER TO postgres;

--
-- Name: FUNCTION create_job_from_estimate(p_estimate_id uuid); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.create_job_from_estimate(p_estimate_id uuid) IS 'A1.2 · Creates (or returns) the job for a signed estimate and its one master work order. Returns {job_id, master_work_order_id}. Idempotent.';


--
-- Name: create_organization(text, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_organization(p_name text, p_tenant_type text, p_trade text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
begin
  if not is_platform_admin() then
    raise exception 'only a platform admin can create organizations';
  end if;

  insert into public.organizations (name, tenant_type, trade)
  values (p_name, p_tenant_type, p_trade)
  returning id into v_org_id;

  return v_org_id;
end;
$$;


ALTER FUNCTION public.create_organization(p_name text, p_tenant_type text, p_trade text) OWNER TO postgres;

--
-- Name: create_roadmap_item(uuid, uuid, text, text, text, text, text, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_roadmap_item(p_org_id uuid, p_project_id uuid, p_phase text, p_section text, p_feature text, p_status text DEFAULT 'planned'::text, p_notes text DEFAULT NULL::text, p_sort_order integer DEFAULT 0) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


ALTER FUNCTION public.create_roadmap_item(p_org_id uuid, p_project_id uuid, p_phase text, p_section text, p_feature text, p_status text, p_notes text, p_sort_order integer) OWNER TO postgres;

--
-- Name: FUNCTION create_roadmap_item(p_org_id uuid, p_project_id uuid, p_phase text, p_section text, p_feature text, p_status text, p_notes text, p_sort_order integer); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.create_roadmap_item(p_org_id uuid, p_project_id uuid, p_phase text, p_section text, p_feature text, p_status text, p_notes text, p_sort_order integer) IS 'Build Tracker item insert RPC, v2 — adds p_project_id (validated to belong to p_org_id). Org-scoped from caller membership; stamps updated_by.';


--
-- Name: create_roadmap_project(uuid, text, text, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_roadmap_project(p_org_id uuid, p_key text, p_name text, p_sort_order integer DEFAULT 0) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


ALTER FUNCTION public.create_roadmap_project(p_org_id uuid, p_key text, p_name text, p_sort_order integer) OWNER TO postgres;

--
-- Name: FUNCTION create_roadmap_project(p_org_id uuid, p_key text, p_name text, p_sort_order integer); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.create_roadmap_project(p_org_id uuid, p_key text, p_name text, p_sort_order integer) IS 'Build Tracker project insert RPC. Org-scoped from caller membership. Unique (org_id, key) enforces no duplicate project slugs.';


--
-- Name: create_tracker_item(uuid, uuid, text, text, text, text, text, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_tracker_item(p_org_id uuid, p_project_id uuid, p_title text, p_type text DEFAULT 'task'::text, p_priority text DEFAULT 'normal'::text, p_description text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_assignee_id uuid DEFAULT NULL::uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


ALTER FUNCTION public.create_tracker_item(p_org_id uuid, p_project_id uuid, p_title text, p_type text, p_priority text, p_description text, p_status text, p_assignee_id uuid) OWNER TO postgres;

--
-- Name: FUNCTION create_tracker_item(p_org_id uuid, p_project_id uuid, p_title text, p_type text, p_priority text, p_description text, p_status text, p_assignee_id uuid); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.create_tracker_item(p_org_id uuid, p_project_id uuid, p_title text, p_type text, p_priority text, p_description text, p_status text, p_assignee_id uuid) IS 'Tracker item insert RPC — the mobile quick-add path (title + type + priority). Status defaults to the org''s configured first status if not given.';


--
-- Name: create_tracker_project(uuid, text, text, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_tracker_project(p_org_id uuid, p_name text, p_description text DEFAULT NULL::text, p_linked_org_id uuid DEFAULT NULL::uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


ALTER FUNCTION public.create_tracker_project(p_org_id uuid, p_name text, p_description text, p_linked_org_id uuid) OWNER TO postgres;

--
-- Name: FUNCTION create_tracker_project(p_org_id uuid, p_name text, p_description text, p_linked_org_id uuid); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.create_tracker_project(p_org_id uuid, p_name text, p_description text, p_linked_org_id uuid) IS 'Tracker project insert RPC. Org-scoped from caller membership.';


--
-- Name: create_trade_work_order(uuid, text, text, text, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_trade_work_order(p_master_work_order_id uuid, p_trade text, p_assignee_type text DEFAULT NULL::text, p_assignee_ref text DEFAULT NULL::text, p_predecessor_id uuid DEFAULT NULL::uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id        uuid;
  v_estimate_id   uuid;
  v_job_id        uuid;
  v_kind          text;
  v_voided_at     timestamptz;
  v_trade         text;
  v_assignee_type text;
  v_assignee_ref  text;
  v_existing_id   uuid;
  v_trade_id      uuid;
begin
  select w.org_id, w.estimate_id, w.job_id, w.kind, w.voided_at
    into v_org_id, v_estimate_id, v_job_id, v_kind, v_voided_at
  from public.work_orders w
  where w.id = p_master_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_master_work_order_id;
  end if;

  if coalesce(v_kind, '') <> 'master' then
    raise exception 'work order % is kind=% — a trade work order must be created under a master',
      p_master_work_order_id, coalesce(v_kind, '(null)');
  end if;

  if v_voided_at is not null then
    raise exception 'master work order % is voided — cannot add a trade work order to it',
      p_master_work_order_id;
  end if;

  v_trade := nullif(btrim(coalesce(p_trade, '')), '');
  if v_trade is null then
    raise exception 'trade is required on a trade work order';
  end if;

  v_assignee_type := nullif(btrim(coalesce(p_assignee_type, '')), '');
  v_assignee_ref  := nullif(btrim(coalesce(p_assignee_ref,  '')), '');

  if (v_assignee_type is null) <> (v_assignee_ref is null) then
    raise exception 'assignee_type and assignee_ref must be supplied together (type=%, ref=%)',
      coalesce(v_assignee_type, '(null)'), coalesce(v_assignee_ref, '(null)');
  end if;

  -- Mirrors work_orders_assignee_type_check so the caller gets a readable error
  -- instead of a constraint violation. D1: an external subcontractor is a
  -- first-class assignee, not an exception — the tenant is frequently somebody
  -- else's sub.
  if v_assignee_type is not null
     and v_assignee_type not in ('crew', 'department', 'subcontractor') then
    raise exception 'assignee_type % is not valid — expected crew, department or subcontractor',
      v_assignee_type;
  end if;

  if p_predecessor_id is not null then
    if p_predecessor_id = p_master_work_order_id then
      raise exception 'predecessor cannot be the master work order';
    end if;

    perform 1
    from public.work_orders w
    where w.id = p_predecessor_id
      and w.job_id = v_job_id
      and w.kind = 'trade';

    if not found then
      raise exception 'predecessor % is not a trade work order on job %', p_predecessor_id, v_job_id;
    end if;
  end if;

  -- Double-submit guard, the trade-level equivalent of A1.1's master idempotency.
  -- Two crews legitimately split one trade, so this keys on the assignee too: the
  -- same trade issued to a different assignee is allowed, the identical row is not.
  -- Refuse rather than silently return, because unlike the master a trade carries
  -- caller-supplied detail and a silent no-op would hide a real mistake.
  select w.id into v_existing_id
  from public.work_orders w
  where w.job_id = v_job_id
    and w.kind = 'trade'
    and w.voided_at is null
    and lower(w.trade) = lower(v_trade)
    and coalesce(w.assignee_type, '') = coalesce(v_assignee_type, '')
    and coalesce(w.assignee_ref,  '') = coalesce(v_assignee_ref,  '')
  limit 1;

  if v_existing_id is not null then
    raise exception 'an active % trade work order with the same assignee already exists on this job (%)',
      v_trade, v_existing_id;
  end if;

  insert into public.work_orders (
    org_id, estimate_id, job_id, kind,
    trade, assignee_type, assignee_ref, predecessor_id
  )
  values (
    v_org_id, v_estimate_id, v_job_id, 'trade',
    v_trade, v_assignee_type, v_assignee_ref, p_predecessor_id
  )
  returning id into v_trade_id;

  return v_trade_id;
end;
$$;


ALTER FUNCTION public.create_trade_work_order(p_master_work_order_id uuid, p_trade text, p_assignee_type text, p_assignee_ref text, p_predecessor_id uuid) OWNER TO postgres;

--
-- Name: FUNCTION create_trade_work_order(p_master_work_order_id uuid, p_trade text, p_assignee_type text, p_assignee_ref text, p_predecessor_id uuid); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.create_trade_work_order(p_master_work_order_id uuid, p_trade text, p_assignee_type text, p_assignee_ref text, p_predecessor_id uuid) IS 'A1.2 · Creates one trade work order under a master. Inherits org/estimate/job from the master. Assignee is optional but never half-specified; subcontractor is a valid assignee per D1.';


--
-- Name: create_wh_order(jsonb, jsonb, jsonb, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_wh_order(p_order jsonb, p_line_items jsonb DEFAULT '[]'::jsonb, p_spec_files jsonb DEFAULT '[]'::jsonb, p_org_id uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_supplier     uuid := '1084baa8-0355-4298-9b98-b876a7581173';
  v_uid          uuid := auth.uid();
  v_org          uuid;
  v_order_id     uuid;
  v_order_num    text;
  v_driver_email text;
  v_item         jsonb;
  v_attempt      int;
BEGIN
  IF v_uid IS NULL THEN
    v_org := v_supplier;
  ELSE
    IF p_org_id IS NOT NULL AND p_org_id IN (SELECT my_org_ids()) THEN
      v_org := p_org_id;
    ELSE
      v_org := COALESCE((SELECT org_id FROM org_members WHERE user_id = v_uid LIMIT 1), v_supplier);
    END IF;
  END IF;

  v_driver_email := (SELECT value FROM public.wh_settings
                      WHERE org_id = v_org AND key = 'driver_email');

  -- Authoritative order_number allocation. The client's order_number is ignored
  -- entirely. Retry on unique_violation (23505) by re-allocating from the sequence.
  <<alloc>>
  FOR v_attempt IN 1..20 LOOP
    v_order_num := nextval('public.wh_order_number_seq')::text;
    BEGIN
      INSERT INTO public.wh_orders (
        org_id, order_number, system, customer_id, customer_name, customer_phone,
        customer_email, job_name, fulfillment, order_notes, order_total,
        status, driver_email, webhook_fired, webhook_payload
      ) VALUES (
        v_org, v_order_num, p_order->>'system', v_uid,
        p_order->>'customer_name', p_order->>'customer_phone', p_order->>'customer_email',
        p_order->>'job_name', p_order->>'fulfillment', p_order->>'order_notes',
        NULLIF(p_order->>'order_total','')::numeric,
        COALESCE(NULLIF(p_order->>'status',''), 'pending'),
        v_driver_email, false, p_order->'webhook_payload'
      )
      RETURNING id INTO v_order_id;
      EXIT alloc;  -- inserted cleanly with a unique number
    EXCEPTION WHEN unique_violation THEN
      IF v_attempt >= 20 THEN
        RAISE EXCEPTION 'create_wh_order: could not allocate a unique order_number after % attempts', v_attempt;
      END IF;
      -- fall through: next loop iteration re-allocates via nextval()
    END;
  END LOOP;

  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_line_items, '[]'::jsonb))
  LOOP
    INSERT INTO public.wh_order_line_items (
      org_id, order_id, category, description, specs, amount, display_order
    ) VALUES (
      v_org, v_order_id, v_item->>'category', v_item->>'description', v_item->>'specs',
      NULLIF(v_item->>'amount','')::numeric,
      COALESCE(NULLIF(v_item->>'display_order','')::int, 0)
    );
  END LOOP;

  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_spec_files, '[]'::jsonb))
  LOOP
    INSERT INTO public.wh_spec_files (
      org_id, order_id, filename, storage_url, description
    ) VALUES (
      v_org, v_order_id, v_item->>'filename',
      COALESCE(v_item->>'storage_url', v_item->>'url'), v_item->>'description'
    );
  END LOOP;

  RETURN jsonb_build_object('order_id', v_order_id, 'order_number', v_order_num);
END $$;


ALTER FUNCTION public.create_wh_order(p_order jsonb, p_line_items jsonb, p_spec_files jsonb, p_org_id uuid) OWNER TO postgres;

--
-- Name: create_work_order_agreement(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_work_order_agreement(p_work_order_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_job_id uuid;
  v_existing_id uuid;
  v_snapshot jsonb;
  v_agreement_id uuid;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'master');

  select job_id into v_job_id from public.work_orders where id = p_work_order_id;

  select id into v_existing_id
  from public.work_order_agreements
  where work_order_id = p_work_order_id and status <> 'voided';

  if v_existing_id is not null then
    return v_existing_id;
  end if;

  select jsonb_build_object(
    'work_order', jsonb_build_object(
      'id', wo.id,
      'sign_off_notes', wo.sign_off_notes
    ),
    'estimate', jsonb_build_object(
      'id', e.id,
      'estimate_number', e.estimate_number,
      'contact_name', e.contact_name,
      'company', e.company,
      'phone', e.phone,
      'email', e.email,
      'site_address', e.site_address,
      'squares', e.squares,
      'pitch', e.pitch
    ),
    'materials', coalesce((
      select jsonb_agg(
        jsonb_build_object('trade', t.trade, 'name', mi.name, 'quantity', mi.quantity, 'ready_by', mi.ready_by)
        order by t.trade, mi.sort_order
      )
      from public.material_items mi
      join public.work_orders t on t.id = mi.work_order_id
      where t.job_id = v_job_id and t.kind = 'trade' and t.voided_at is null
    ), '[]'::jsonb),
    'schedule', coalesce((
      select jsonb_agg(
        jsonb_build_object('trade', t.trade, 'crew_name', sb.crew_name, 'start_date', sb.start_date, 'end_date', sb.end_date)
        order by sb.start_date
      )
      from public.schedule_blocks sb
      join public.work_orders t on t.id = sb.work_order_id
      where t.job_id = v_job_id and t.kind = 'trade' and t.voided_at is null
    ), '[]'::jsonb)
  )
  into v_snapshot
  from public.work_orders wo
  join public.estimates e on e.id = wo.estimate_id
  where wo.id = p_work_order_id;

  insert into public.work_order_agreements (org_id, work_order_id, snapshot)
  values (v_org_id, p_work_order_id, v_snapshot)
  returning id into v_agreement_id;

  return v_agreement_id;
end;
$$;


ALTER FUNCTION public.create_work_order_agreement(p_work_order_id uuid) OWNER TO postgres;

--
-- Name: FUNCTION create_work_order_agreement(p_work_order_id uuid); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.create_work_order_agreement(p_work_order_id uuid) IS 'Creates the pending sign-off agreement for a work order, snapshotting the current work order/estimate/materials/schedule. Idempotent — returns the existing active agreement if one already exists rather than erroring on the partial unique index.';


--
-- Name: crm_follow_up_cadence_days(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.crm_follow_up_cadence_days(p_org_id uuid) RETURNS integer[]
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


ALTER FUNCTION public.crm_follow_up_cadence_days(p_org_id uuid) OWNER TO postgres;

--
-- Name: crm_stage_config(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.crm_stage_config(p_org_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce(tm.config -> 'stages', '[]'::jsonb)
  from public.tenant_modules tm
  where tm.org_id = p_org_id
    and tm.module_key = 'crm'
  limit 1;
$$;


ALTER FUNCTION public.crm_stage_config(p_org_id uuid) OWNER TO postgres;

--
-- Name: FUNCTION crm_stage_config(p_org_id uuid); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.crm_stage_config(p_org_id uuid) IS 'The org''s configured CRM stage list (tenant_modules.config->stages), or [] if unset. Internal helper — see header comment for why it has no auth guard.';


--
-- Name: crm_stage_entry(uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.crm_stage_entry(p_org_id uuid, p_stage_key text) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select stage
  from jsonb_array_elements(public.crm_stage_config(p_org_id)) as stage
  where stage ->> 'key' = p_stage_key
  limit 1;
$$;


ALTER FUNCTION public.crm_stage_entry(p_org_id uuid, p_stage_key text) OWNER TO postgres;

--
-- Name: deal_stage_side_effects(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.deal_stage_side_effects() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


ALTER FUNCTION public.deal_stage_side_effects() OWNER TO postgres;

--
-- Name: delete_check_in(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_check_in(p_check_in_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.check_ins where id = p_check_in_id;

  if v_org_id is null then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  delete from public.check_ins where id = p_check_in_id;
end;
$$;


ALTER FUNCTION public.delete_check_in(p_check_in_id uuid) OWNER TO postgres;

--
-- Name: delete_estimate(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_estimate(p_estimate_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_has_signature boolean;
  v_has_work_order boolean;
begin
  select org_id into v_org_id from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  select exists(select 1 from public.signatures where estimate_id = p_estimate_id)
    into v_has_signature;
  select exists(select 1 from public.work_orders where estimate_id = p_estimate_id)
    into v_has_work_order;

  if v_has_signature or v_has_work_order then
    raise exception 'estimate % has a signature or work order and cannot be deleted — void it instead', p_estimate_id;
  end if;

  delete from public.estimates where id = p_estimate_id;
end;
$$;


ALTER FUNCTION public.delete_estimate(p_estimate_id uuid) OWNER TO postgres;

--
-- Name: delete_estimate_line_item(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_estimate_line_item(p_line_item_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_estimate_id uuid;
  v_status text;
begin
  select li.org_id, li.estimate_id into v_org_id, v_estimate_id
  from public.estimate_line_items li
  where li.id = p_line_item_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'line item not found or not accessible: %', p_line_item_id;
  end if;

  select status into v_status from public.estimates where id = v_estimate_id;

  if v_status in ('signed', 'void') then
    raise exception 'estimate is locked (status: %) — line items can only change before signing', v_status;
  end if;

  delete from public.estimate_line_items where id = p_line_item_id;
end;
$$;


ALTER FUNCTION public.delete_estimate_line_item(p_line_item_id uuid) OWNER TO postgres;

--
-- Name: delete_material_item(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_material_item(p_material_item_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_work_order_id uuid;
  v_trade text;
  v_master_id uuid;
  v_sign_off_at timestamptz;
  v_name text;
  v_actor_id uuid;
begin
  select mi.org_id, mi.work_order_id, mi.name
  into v_org_id, v_work_order_id, v_name
  from public.material_items mi
  where mi.id = p_material_item_id;

  if v_org_id is null then
    raise exception 'material item not found or not accessible: %', p_material_item_id;
  end if;

  -- A1.3b checked org against the parent; A1.4 adds the level. Split from the
  -- null check on purpose: PL/pgSQL does not guarantee short-circuit
  -- evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'material item not found or not accessible: %', p_material_item_id;
  end if;

  select w.trade into v_trade from public.work_orders w where w.id = v_work_order_id;

  select s.master_id, s.sign_off_at into v_master_id, v_sign_off_at
  from public.job_master_sign_off(v_work_order_id) s;

  delete from public.material_items where id = p_material_item_id;

  if v_sign_off_at is not null then
    select id into v_actor_id from public.profiles where id = auth.uid();
    insert into public.work_order_activity (work_order_id, org_id, action, from_value, actor_id)
    values (coalesce(v_master_id, v_work_order_id), v_org_id, 'material_deleted_after_signoff',
            format('%s (%s)', v_name, coalesce(v_trade, 'trade')), v_actor_id);
  end if;
end;
$$;


ALTER FUNCTION public.delete_material_item(p_material_item_id uuid) OWNER TO postgres;

--
-- Name: delete_production_packet(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_production_packet(p_production_packet_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.production_packets where id = p_production_packet_id;

  if v_org_id is null then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  delete from public.production_packets where id = p_production_packet_id;
end;
$$;


ALTER FUNCTION public.delete_production_packet(p_production_packet_id uuid) OWNER TO postgres;

--
-- Name: delete_production_packet_callout(uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_production_packet_callout(p_production_packet_id uuid, p_callout_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.production_packets where id = p_production_packet_id;

  if v_org_id is null then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  update public.production_packets
  set callouts = (
        select coalesce(jsonb_agg(elem), '[]'::jsonb)
        from jsonb_array_elements(callouts) as elem
        where (elem->>'id')::uuid <> p_callout_id
      ),
      updated_at = now()
  where id = p_production_packet_id;
end;
$$;


ALTER FUNCTION public.delete_production_packet_callout(p_production_packet_id uuid, p_callout_id uuid) OWNER TO postgres;

--
-- Name: delete_roadmap_item(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_roadmap_item(p_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.roadmap_items where id = p_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'roadmap item not found or not accessible: %', p_id;
  end if;

  delete from public.roadmap_items where id = p_id;
end;
$$;


ALTER FUNCTION public.delete_roadmap_item(p_id uuid) OWNER TO postgres;

--
-- Name: FUNCTION delete_roadmap_item(p_id uuid); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.delete_roadmap_item(p_id uuid) IS 'Build Tracker hard-delete RPC. No archive tier — a matrix row can just be deleted outright (unlike tracker_projects, nothing else references a roadmap_item).';


--
-- Name: delete_roadmap_project(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_roadmap_project(p_project_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


ALTER FUNCTION public.delete_roadmap_project(p_project_id uuid) OWNER TO postgres;

--
-- Name: delete_schedule_block(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_schedule_block(p_schedule_block_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.schedule_blocks where id = p_schedule_block_id;

  if v_org_id is null then
    raise exception 'schedule block not found or not accessible: %', p_schedule_block_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'schedule block not found or not accessible: %', p_schedule_block_id;
  end if;

  delete from public.schedule_blocks where id = p_schedule_block_id;
end;
$$;


ALTER FUNCTION public.delete_schedule_block(p_schedule_block_id uuid) OWNER TO postgres;

--
-- Name: delete_tracker_item(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_tracker_item(p_item_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


ALTER FUNCTION public.delete_tracker_item(p_item_id uuid) OWNER TO postgres;

--
-- Name: delete_tracker_project(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_tracker_project(p_project_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


ALTER FUNCTION public.delete_tracker_project(p_project_id uuid) OWNER TO postgres;

--
-- Name: delete_work_order(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_work_order(p_work_order_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_kind text;
  v_job_id uuid;
  v_trade_count int;
  v_successor_count int;
  v_has_children boolean;
begin
  select org_id, kind, job_id
  into v_org_id, v_kind, v_job_id
  from public.work_orders where id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  if v_kind = 'master' then
    select count(*) into v_trade_count
    from public.work_orders
    where job_id = v_job_id and kind = 'trade';

    if v_trade_count > 0 then
      raise exception 'work order % is a master with % trade work order(s) under it and cannot be deleted — that would destroy the whole job''s production record and cannot be undone. Void it instead: voiding a master voids its live trades and can be restored.',
        p_work_order_id, v_trade_count;
    end if;
  end if;

  -- Without this the FK on predecessor_id raises a raw constraint error at the
  -- user. Same refuse-and-explain shape as the master case.
  select count(*) into v_successor_count
  from public.work_orders
  where predecessor_id = p_work_order_id;

  if v_successor_count > 0 then
    raise exception 'work order % is the predecessor of % other trade work order(s) — clear that dependency first, or void this work order instead',
      p_work_order_id, v_successor_count;
  end if;

  select
    exists(select 1 from public.material_items where work_order_id = p_work_order_id)
    or exists(select 1 from public.schedule_blocks where work_order_id = p_work_order_id)
    or exists(select 1 from public.check_ins where work_order_id = p_work_order_id)
    or exists(select 1 from public.production_packets where work_order_id = p_work_order_id)
  into v_has_children;

  if v_has_children then
    raise exception 'work order % has materials, a schedule, check-ins, or a production packet and cannot be deleted — void it instead', p_work_order_id;
  end if;

  delete from public.work_orders where id = p_work_order_id;
end;
$$;


ALTER FUNCTION public.delete_work_order(p_work_order_id uuid) OWNER TO postgres;

--
-- Name: derive_level_status(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.derive_level_status() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


ALTER FUNCTION public.derive_level_status() OWNER TO postgres;

--
-- Name: estimate_line_items_sync_subtotal(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.estimate_line_items_sync_subtotal() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_estimate_id uuid;
begin
  v_estimate_id := coalesce(new.estimate_id, old.estimate_id);

  update public.estimates
  set subtotal = coalesce(
        (select sum(line_total) from public.estimate_line_items where estimate_id = v_estimate_id),
        0
      ),
      updated_at = now()
  where id = v_estimate_id;

  return coalesce(new, old);
end;
$$;


ALTER FUNCTION public.estimate_line_items_sync_subtotal() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: check_ins; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.check_ins (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    work_order_id uuid NOT NULL,
    schedule_block_id uuid,
    crew_name text NOT NULL,
    check_in_date date DEFAULT CURRENT_DATE NOT NULL,
    hours numeric DEFAULT 0 NOT NULL,
    materials_used text,
    blockers text,
    photos text[] DEFAULT '{}'::text[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.check_ins OWNER TO postgres;

--
-- Name: COLUMN check_ins.photos; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.check_ins.photos IS 'Base64 data URIs, same stopgap as signatures.signature_data — not R2. See migration header note 1.';


--
-- Name: fetch_check_in(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fetch_check_in(p_check_in_id uuid) RETURNS SETOF public.check_ins
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select c.*
  from public.check_ins c
  join public.work_orders w on w.id = c.work_order_id
  where c.id = p_check_in_id
    and w.kind = 'trade'
    and w.org_id = c.org_id
    and w.org_id in (select my_org_ids());
$$;


ALTER FUNCTION public.fetch_check_in(p_check_in_id uuid) OWNER TO postgres;

--
-- Name: deals; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.deals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    lead_id uuid,
    contact_name text NOT NULL,
    company text,
    email text,
    phone text,
    trade text,
    crew_size integer,
    value integer,
    stage text DEFAULT 'new_scan'::text NOT NULL,
    lost_reason text,
    source text DEFAULT 'scan'::text,
    proposal_tier text,
    proposal_notes text,
    closed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    org_id uuid,
    archived_at timestamp with time zone,
    lead_type text,
    project_address text,
    billing_address text,
    first_name text,
    last_name text,
    secondary_phone text,
    remodel_or_new_construction text,
    existing_roof_type text[],
    roof_type_requested text[],
    service_address_street text,
    service_address_city text,
    service_address_state text,
    service_address_zip text,
    referral_name text,
    intake_checklist jsonb DEFAULT '{}'::jsonb NOT NULL,
    site_survey_complete_at timestamp with time zone,
    roof_scope_ordered_at timestamp with time zone,
    quote_presented_at timestamp with time zone,
    owner_id uuid,
    tags text[],
    CONSTRAINT deals_lead_type_check CHECK ((lead_type = ANY (ARRAY['homeowner'::text, 'contractor'::text, 'property_management'::text, 'commercial'::text]))),
    CONSTRAINT deals_remodel_or_new_construction_check CHECK ((remodel_or_new_construction = ANY (ARRAY['remodel'::text, 'new_construction'::text])))
);


ALTER TABLE public.deals OWNER TO postgres;

--
-- Name: COLUMN deals.archived_at; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.deals.archived_at IS 'Soft-delete. Archived deals drop off the pipeline board but stay fetchable (fetch_deal) so restore_deal() can undo a mistake. See migration header.';


--
-- Name: COLUMN deals.lead_type; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.deals.lead_type IS 'Customer type: homeowner | contractor | property_management | commercial. Widened from the Stage 1 2-value (homeowner/company) set — commercial absorbs the old ''company'' value. Labels (e.g. "Contractor (GC)") live in src/lib/crm/command-center.ts, not the DB.';


--
-- Name: COLUMN deals.project_address; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.deals.project_address IS 'The job/service address. Free text for now — see migration header note 1 (structured/geocoded is future work, BACKLOG.md).';


--
-- Name: COLUMN deals.billing_address; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.deals.billing_address IS 'Nullable — falls back to project_address wherever displayed if unset. See migration header note.';


--
-- Name: COLUMN deals.first_name; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.deals.first_name IS 'Split from contact_name (CRM Depth Stage 2). Nullable, no backfill — contact_name stays the load-bearing column; see migration header.';


--
-- Name: COLUMN deals.last_name; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.deals.last_name IS 'Split from contact_name (CRM Depth Stage 2). Nullable, no backfill — see migration header.';


--
-- Name: COLUMN deals.service_address_street; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.deals.service_address_street IS 'Structured service address (Stage 2) — independent of project_address (Stage 1, still live). See migration header note.';


--
-- Name: COLUMN deals.intake_checklist; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.deals.intake_checklist IS 'Written incrementally by Stage 3''s command-stage engine (not designed yet) — no RPC wiring in this migration.';


--
-- Name: COLUMN deals.owner_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.deals.owner_id IS 'Rep assignment — references profiles(id), not org_members (no single-column PK). Nullable; wiring is Stage 5 (Ownership & attribution).';


--
-- Name: fetch_deal(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fetch_deal(p_deal_id uuid) RETURNS SETOF public.deals
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select (
    jsonb_populate_record(
      null::public.deals,
      case
        when public.has_capability(d.org_id, 'view_financials') then to_jsonb(d)
        else to_jsonb(d) - 'value'
      end
    )
  ).*
  from public.deals d
  where d.id = p_deal_id
    and d.org_id in (select my_org_ids());
$$;


ALTER FUNCTION public.fetch_deal(p_deal_id uuid) OWNER TO postgres;

--
-- Name: estimates; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.estimates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    deal_id uuid NOT NULL,
    status text DEFAULT 'draft'::text NOT NULL,
    contact_name text,
    company text,
    phone text,
    email text,
    site_address text,
    squares numeric,
    pitch text,
    subtotal numeric DEFAULT 0 NOT NULL,
    presented_total numeric,
    presented_at timestamp with time zone,
    signed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    estimate_number text,
    notes_terms text,
    tax_rate numeric,
    estimate_date date DEFAULT CURRENT_DATE,
    valid_until date,
    build_mode text DEFAULT 'manual'::text NOT NULL,
    tax_amount numeric GENERATED ALWAYS AS (round((subtotal * COALESCE(tax_rate, (0)::numeric)), 2)) STORED,
    CONSTRAINT estimates_build_mode_check CHECK ((build_mode = ANY (ARRAY['manual'::text, 'guided'::text]))),
    CONSTRAINT estimates_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'presented'::text, 'signed'::text, 'void'::text])))
);


ALTER TABLE public.estimates OWNER TO postgres;

--
-- Name: TABLE estimates; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.estimates IS 'Live on-site estimate, generated from a deal. Status: draft -> presented (snapshot, not a lock) -> signed, or void. Only signed/void freeze the document (SCOPE §2.8 — presenting no longer locks edits).';


--
-- Name: COLUMN estimates.presented_total; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.estimates.presented_total IS 'Snapshot of subtotal at present_estimate() time — the price-lock habit (SCOPE.md §12C). Not re-synced after presenting.';


--
-- Name: COLUMN estimates.estimate_number; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.estimates.estimate_number IS 'Human-readable per-org number ("EST-1042"), claimed from estimate_number_counters at creation. Nullable: the 2 pre-existing rows have none and aren''t backfilled — nothing reads this as required.';


--
-- Name: COLUMN estimates.build_mode; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.estimates.build_mode IS 'Manual (default — Isaac types line items directly, any order) vs Guided (line items generated from the site-visit scope checklist + pricing matrix, Chunk 4). Switchable both ways without losing manual edits.';


--
-- Name: COLUMN estimates.tax_amount; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.estimates.tax_amount IS 'Generated from subtotal * tax_rate, same reasoning as estimate_line_items.line_total — never written directly.';


--
-- Name: fetch_estimate(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fetch_estimate(p_estimate_id uuid) RETURNS SETOF public.estimates
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  r public.estimates%rowtype;
  v_money boolean;
begin
  for r in
    select e.*
    from public.estimates e
    where e.id = p_estimate_id
      and e.org_id in (select my_org_ids())
  loop
    v_money := public.can_view_financials(r.org_id);
    if not v_money then
      r.subtotal := null;
      r.presented_total := null;
      r.tax_rate := null;
      r.tax_amount := null;
    end if;
    return next r;
  end loop;
end;
$$;


ALTER FUNCTION public.fetch_estimate(p_estimate_id uuid) OWNER TO postgres;

--
-- Name: fetch_field_jobs(uuid, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fetch_field_jobs(p_org_id uuid, p_today date DEFAULT CURRENT_DATE) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'schedule_block_id', j.id,
        'work_order_id', j.work_order_id,
        'crew_name', j.crew_name,
        'start_date', j.start_date,
        'end_date', j.end_date,
        'blocked', j.blocked,
        'blocked_reason', j.blocked_reason,
        'job_title', coalesce(nullif(j.company, ''), j.contact_name),
        'site_address', j.site_address,
        'squares', j.squares,
        'pitch', j.pitch
      ) order by j.start_date, j.created_at
    ), '[]'::jsonb)
  from (
    select sb.id, sb.work_order_id, sb.crew_name, sb.start_date, sb.end_date,
           sb.blocked, sb.blocked_reason, sb.created_at,
           e.company, e.contact_name, e.site_address, e.squares, e.pitch
    from public.schedule_blocks sb
    join public.work_orders w on w.id = sb.work_order_id
    join public.estimates e on e.id = w.estimate_id
    where sb.org_id = p_org_id
      and p_org_id in (select my_org_ids())
      and w.kind = 'trade'
      and w.voided_at is null
      and sb.end_date >= p_today
    order by sb.start_date, sb.created_at
    limit 20
  ) j;
$$;


ALTER FUNCTION public.fetch_field_jobs(p_org_id uuid, p_today date) OWNER TO postgres;

--
-- Name: FUNCTION fetch_field_jobs(p_org_id uuid, p_today date); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.fetch_field_jobs(p_org_id uuid, p_today date) IS 'A1.5. Today + upcoming trade work for the field module. Trade work orders only, voided ones excluded, and no money column anywhere in the select list — the crew UI reads this instead of embedding estimates, which is now closed to crew-tier members by a restrictive policy.';


--
-- Name: fetch_membership_context(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fetch_membership_context() RETURNS SETOF public.membership_context
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select
    o.id,
    o.name,
    o.tenant_type,
    m.role,
    coalesce(
      array_agg(tm.module_key) filter (where tm.enabled),
      '{}'
    )
  from public.org_members m
  join public.organizations o on o.id = m.org_id
  left join public.tenant_modules tm on tm.org_id = o.id
  where m.user_id = auth.uid()
  group by o.id, o.name, o.tenant_type, m.role;
$$;


ALTER FUNCTION public.fetch_membership_context() OWNER TO postgres;

--
-- Name: FUNCTION fetch_membership_context(); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.fetch_membership_context() IS 'App-shell load: every org the caller belongs to + role + entitled module keys. Scoped to auth.uid() internally.';


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.organizations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    trade text,
    deal_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    tenant_type text DEFAULT 'contractor'::text NOT NULL,
    CONSTRAINT organizations_tenant_type_check CHECK ((tenant_type = ANY (ARRAY['internal'::text, 'contractor'::text, 'supplier'::text])))
);


ALTER TABLE public.organizations OWNER TO postgres;

--
-- Name: COLUMN organizations.tenant_type; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.organizations.tenant_type IS 'internal = StructTech itself (agency layer, all modules). contractor = a licensed client tenant.';


--
-- Name: fetch_organization(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fetch_organization(p_org_id uuid) RETURNS SETOF public.organizations
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select o.*
  from public.organizations o
  where o.id = p_org_id
    and (is_platform_admin() or p_org_id in (select my_org_ids()));
$$;


ALTER FUNCTION public.fetch_organization(p_org_id uuid) OWNER TO postgres;

--
-- Name: production_packets; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.production_packets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    work_order_id uuid NOT NULL,
    notes text,
    callouts jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.production_packets OWNER TO postgres;

--
-- Name: TABLE production_packets; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.production_packets IS 'Built from work order + check-in photos (derived, not duplicated — SCOPE.md §6 no re-entry). Trim map / boot-vent layers deferred. See migration header notes 2/3.';


--
-- Name: COLUMN production_packets.callouts; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.production_packets.callouts IS 'jsonb array of {id, label, detail} — CRUD via add/update/delete_production_packet_callout RPCs, not a child table. See migration header note 3.';


--
-- Name: fetch_production_packet(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fetch_production_packet(p_production_packet_id uuid) RETURNS SETOF public.production_packets
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select p.*
  from public.production_packets p
  join public.work_orders w on w.id = p.work_order_id
  where p.id = p_production_packet_id
    and w.kind = 'trade'
    and w.org_id = p.org_id
    and w.org_id in (select my_org_ids());
$$;


ALTER FUNCTION public.fetch_production_packet(p_production_packet_id uuid) OWNER TO postgres;

--
-- Name: tracker_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tracker_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    project_id uuid NOT NULL,
    type text DEFAULT 'task'::text NOT NULL,
    title text NOT NULL,
    description text,
    status text DEFAULT 'inbox'::text NOT NULL,
    priority text DEFAULT 'normal'::text NOT NULL,
    assignee_id uuid,
    "position" integer DEFAULT 0 NOT NULL,
    source text DEFAULT 'internal'::text NOT NULL,
    reported_by_org_id uuid,
    reported_by_profile_id uuid,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    resolved_at timestamp with time zone,
    archived_at timestamp with time zone,
    CONSTRAINT tracker_items_priority_check CHECK ((priority = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text, 'urgent'::text]))),
    CONSTRAINT tracker_items_source_check CHECK ((source = ANY (ARRAY['internal'::text, 'client'::text]))),
    CONSTRAINT tracker_items_type_check CHECK ((type = ANY (ARRAY['task'::text, 'bug'::text, 'feature'::text, 'idea'::text])))
);


ALTER TABLE public.tracker_items OWNER TO postgres;

--
-- Name: TABLE tracker_items; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.tracker_items IS 'Tracker module: tasks/bugs/features/ideas within a tracker_project. status/type sets are validated against tenant_modules.config->tracker at the RPC layer, not a DB check constraint (config-driven, per SCOPE.md 2.7/12F) — the check constraints above are only the outer bound (never violate the base vocabulary even if config is misconfigured).';


--
-- Name: fetch_tracker_item(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fetch_tracker_item(p_item_id uuid) RETURNS SETOF public.tracker_items
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select i.*
  from public.tracker_items i
  where i.id = p_item_id
    and i.org_id in (select my_org_ids());
$$;


ALTER FUNCTION public.fetch_tracker_item(p_item_id uuid) OWNER TO postgres;

--
-- Name: tracker_projects; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tracker_projects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    name text NOT NULL,
    description text,
    status text DEFAULT 'active'::text NOT NULL,
    linked_org_id uuid,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    archived_at timestamp with time zone,
    CONSTRAINT tracker_projects_status_check CHECK ((status = ANY (ARRAY['active'::text, 'paused'::text, 'shipped'::text, 'archived'::text])))
);


ALTER TABLE public.tracker_projects OWNER TO postgres;

--
-- Name: TABLE tracker_projects; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.tracker_projects IS 'Tracker module: a fluid, org-scoped bucket of tracker_items. Internal tenants only (module entitlement gates the route).';


--
-- Name: fetch_tracker_project(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fetch_tracker_project(p_project_id uuid) RETURNS SETOF public.tracker_projects
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select p.*
  from public.tracker_projects p
  where p.id = p_project_id
    and p.org_id in (select my_org_ids());
$$;


ALTER FUNCTION public.fetch_tracker_project(p_project_id uuid) OWNER TO postgres;

--
-- Name: work_orders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.work_orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    estimate_id uuid NOT NULL,
    sign_off_at timestamp with time zone,
    sign_off_notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    voided_at timestamp with time zone,
    job_id uuid NOT NULL,
    kind text DEFAULT 'master'::text NOT NULL,
    trade text,
    assignee_type text,
    assignee_ref text,
    predecessor_id uuid,
    void_cascade_source_id uuid,
    CONSTRAINT work_orders_assignee_type_check CHECK (((assignee_type IS NULL) OR (assignee_type = ANY (ARRAY['crew'::text, 'department'::text, 'subcontractor'::text])))),
    CONSTRAINT work_orders_kind_check CHECK ((kind = ANY (ARRAY['master'::text, 'trade'::text]))),
    CONSTRAINT work_orders_void_cascade_requires_void CHECK (((void_cascade_source_id IS NULL) OR (voided_at IS NOT NULL)))
);


ALTER TABLE public.work_orders OWNER TO postgres;

--
-- Name: TABLE work_orders; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.work_orders IS 'Generated from a signed estimate — no re-entry (SCOPE.md §6). One per estimate. Progress is derived by the UI from sign_off_at / material_items / schedule_blocks presence, not a stored status.';


--
-- Name: COLUMN work_orders.sign_off_at; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.work_orders.sign_off_at IS 'Homeowner sign-off on colors/finishes — soft capture, does not block material/schedule creation. See migration header note 1.';


--
-- Name: COLUMN work_orders.voided_at; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.work_orders.voided_at IS 'Soft-cancel ("this job is off"), distinct from delete_work_order()''s hard delete. See migration header.';


--
-- Name: COLUMN work_orders.kind; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.work_orders.kind IS 'master = carries production scope + homeowner sign-off; trade = issued to a crew, department, or external subcontractor.';


--
-- Name: COLUMN work_orders.predecessor_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.work_orders.predecessor_id IS 'A1.1 records the dependency as a field only. The sequencing engine is backlogged (§6.6).';


--
-- Name: COLUMN work_orders.void_cascade_source_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.work_orders.void_cascade_source_id IS 'A1.4 cascade marker. NULL = live, or voided in its own right. Non-NULL = voided by that master work order''s cascade, and restoring that master restores this row. restore_work_order clears only rows carrying its own id, so a deliberate void is never silently reversed.';


--
-- Name: fetch_work_order(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fetch_work_order(p_work_order_id uuid) RETURNS SETOF public.work_orders
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select w.*
  from public.work_orders w
  where w.id = p_work_order_id
    and w.org_id in (select my_org_ids())
    and (w.kind = 'trade' or public.can_view_master_work_order(w.org_id));
$$;


ALTER FUNCTION public.fetch_work_order(p_work_order_id uuid) OWNER TO postgres;

--
-- Name: work_order_agreements; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.work_order_agreements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    work_order_id uuid NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    snapshot jsonb NOT NULL,
    colors_finishes jsonb DEFAULT '{}'::jsonb NOT NULL,
    signer_name text,
    signer_role text,
    signature_data text,
    signed_at timestamp with time zone,
    sign_token_hash text,
    sent_at timestamp with time zone,
    voided_at timestamp with time zone,
    void_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    void_cascade_source_id uuid,
    void_cascade_prior_status text,
    CONSTRAINT work_order_agreements_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'signed'::text, 'voided'::text]))),
    CONSTRAINT work_order_agreements_void_cascade_consistent CHECK ((((void_cascade_source_id IS NULL) AND (void_cascade_prior_status IS NULL)) OR ((void_cascade_source_id IS NOT NULL) AND (void_cascade_prior_status IS NOT NULL) AND (status = 'voided'::text))))
);


ALTER TABLE public.work_order_agreements OWNER TO postgres;

--
-- Name: TABLE work_order_agreements; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.work_order_agreements IS 'Versioned sign-off agreement (COORDINATION_MODULE_SCOPE.md §8) — original + each change order as its own row, only one active (non-voided) at a time. Replaces work_orders.sign_off_at/sign_off_notes as the source of truth; those columns stay as a denormalized mirror, updated by the sign RPC (chunk 2).';


--
-- Name: COLUMN work_order_agreements.snapshot; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.work_order_agreements.snapshot IS 'Frozen work order + estimate + materials + schedule at agreement-creation time — what was actually shown/signed, immune to later live edits.';


--
-- Name: COLUMN work_order_agreements.sign_token_hash; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.work_order_agreements.sign_token_hash IS 'Hash of the remote-signing link token (chunk 4), never the plaintext. Unlike signatures.sign_token (existing, plaintext, unused) — deliberate hardening for a bearer-credential link.';


--
-- Name: COLUMN work_order_agreements.void_cascade_source_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.work_order_agreements.void_cascade_source_id IS 'A1.4 cascade marker, same rule as work_orders.void_cascade_source_id. An agreement voided by a change order (void-and-replace) carries NULL here and is never reactivated by a master restore.';


--
-- Name: COLUMN work_order_agreements.void_cascade_prior_status; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.work_order_agreements.void_cascade_prior_status IS 'The status this agreement held when a master void cascaded onto it. Restore puts this back rather than guessing ''pending''.';


--
-- Name: fetch_work_order_agreement(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fetch_work_order_agreement(p_work_order_id uuid) RETURNS SETOF public.work_order_agreements
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  perform public.assert_work_order_level(p_work_order_id, 'master');

  return query
  select a.*
  from public.work_order_agreements a
  where a.work_order_id = p_work_order_id
    and a.status <> 'voided'
    and a.org_id in (select my_org_ids())
  order by a.created_at desc
  limit 1;
end;
$$;


ALTER FUNCTION public.fetch_work_order_agreement(p_work_order_id uuid) OWNER TO postgres;

--
-- Name: FUNCTION fetch_work_order_agreement(p_work_order_id uuid); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.fetch_work_order_agreement(p_work_order_id uuid) IS 'Returns the single active (non-voided) agreement for a work order, if any.';


--
-- Name: fetch_work_order_tree(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fetch_work_order_tree(p_work_order_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_kind text;
  v_job_id uuid;
  v_voided_at timestamptz;
  v_cascade_source uuid;
  v_master_id uuid;
  v_master_sign_off timestamptz;
  v_trades jsonb;
  v_job_materials int;
  v_job_schedule int;
  v_can_see_master boolean;
begin
  select w.org_id, w.kind, w.job_id, w.voided_at, w.void_cascade_source_id
  into v_org_id, v_kind, v_job_id, v_voided_at, v_cascade_source
  from public.work_orders w
  where w.id = p_work_order_id;

  -- Null rather than a raise: this mirrors fetch_work_order, which returns zero
  -- rows for an inaccessible id. The page redirects on a falsy result.
  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    return null;
  end if;

  v_can_see_master := public.can_view_master_work_order(v_org_id);

  -- A1.5: a crew-tier caller gets nothing for a master, exactly as
  -- fetch_work_order does.
  if v_kind = 'master' and not v_can_see_master then
    return null;
  end if;

  select m.id, m.sign_off_at
  into v_master_id, v_master_sign_off
  from public.work_orders m
  where m.job_id = v_job_id and m.kind = 'master';

  -- On a trade, a crew-tier caller still gets the trade — but not a pointer up
  -- to a master they may not open, and not the master's sign-off state.
  if not v_can_see_master then
    v_master_id := null;
    v_master_sign_off := null;
  end if;

  with node as (
    select
      t.id, t.trade, t.assignee_type, t.assignee_ref, t.predecessor_id,
      t.voided_at, t.void_cascade_source_id, t.created_at,
      (select count(*) from public.material_items mi where mi.work_order_id = t.id)::int as material_count,
      (select count(*) from public.schedule_blocks sb where sb.work_order_id = t.id)::int as schedule_count
    from public.work_orders t
    where t.job_id = v_job_id and t.kind = 'trade'
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', node.id,
        'trade', node.trade,
        'assignee_type', node.assignee_type,
        'assignee_ref', node.assignee_ref,
        'predecessor_id', node.predecessor_id,
        'voided_at', node.voided_at,
        'voided_by_cascade', node.void_cascade_source_id is not null,
        'material_count', node.material_count,
        'schedule_count', node.schedule_count
      ) order by node.created_at
    ), '[]'::jsonb)
  into v_trades
  from node;

  -- Job-wide counts span every work order on the job, master included: a
  -- pre-A1.3b master can still hold rows, and the master's roll-up line must
  -- not under-report them.
  select
    (select count(*) from public.material_items mi
       join public.work_orders w2 on w2.id = mi.work_order_id
      where w2.job_id = v_job_id)::int,
    (select count(*) from public.schedule_blocks sb
       join public.work_orders w2 on w2.id = sb.work_order_id
      where w2.job_id = v_job_id)::int
  into v_job_materials, v_job_schedule;

  return jsonb_build_object(
    'work_order_id', p_work_order_id,
    'level', v_kind,
    'job_id', v_job_id,
    'master_id', v_master_id,
    'master_sign_off_at', v_master_sign_off,
    'voided_at', v_voided_at,
    'voided_by_cascade', v_cascade_source is not null,
    'trades', v_trades,
    'job_material_count', v_job_materials,
    'job_schedule_count', v_job_schedule
  );
end;
$$;


ALTER FUNCTION public.fetch_work_order_tree(p_work_order_id uuid) OWNER TO postgres;

--
-- Name: generate_roadmap_for_lead(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.generate_roadmap_for_lead(p_lead_id uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
end $$;


ALTER FUNCTION public.generate_roadmap_for_lead(p_lead_id uuid) OWNER TO postgres;

--
-- Name: get_or_create_production_packet(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_or_create_production_packet(p_work_order_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_packet_id uuid;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');

  select id into v_packet_id
  from public.production_packets
  where work_order_id = p_work_order_id;

  if v_packet_id is not null then
    return v_packet_id;
  end if;

  insert into public.production_packets (org_id, work_order_id)
  values (v_org_id, p_work_order_id)
  returning id into v_packet_id;

  return v_packet_id;
end;
$$;


ALTER FUNCTION public.get_or_create_production_packet(p_work_order_id uuid) OWNER TO postgres;

--
-- Name: get_wh_order(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_wh_order(p_order_number text, p_email text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_order jsonb;
BEGIN
  SELECT jsonb_build_object(
           'order_number',   o.order_number,
           'order_date',     o.order_date,
           'created_at',     o.created_at,
           'status',         o.status,
           'system',         o.system,
           'customer_name',  o.customer_name,
           'customer_email', o.customer_email,
           'customer_phone', o.customer_phone,
           'job_name',       o.job_name,
           'fulfillment',    o.fulfillment,
           'order_notes',    o.order_notes,
           'order_total',    o.order_total,
           'pdf_url',        o.pdf_url,
           'line_items', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                     'category', li.category, 'description', li.description,
                                     'specs', li.specs, 'amount', li.amount) ORDER BY li.display_order)
                                     FROM public.wh_order_line_items li WHERE li.order_id = o.id), '[]'::jsonb),
           'spec_files', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                     'filename', sf.filename, 'description', sf.description))
                                     FROM public.wh_spec_files sf WHERE sf.order_id = o.id), '[]'::jsonb)
         )
    INTO v_order
    FROM public.wh_orders o
   WHERE o.order_number = p_order_number
     AND lower(o.customer_email) = lower(p_email)
   LIMIT 1;

  RETURN v_order;
END $$;


ALTER FUNCTION public.get_wh_order(p_order_number text, p_email text) OWNER TO postgres;

--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  insert into public.profiles (id, full_name, email)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'full_name', ''),
             nullif(new.raw_user_meta_data->>'name', ''),
             new.email),
    new.email
  )
  on conflict (id) do nothing;
  return new;
end;
$$;


ALTER FUNCTION public.handle_new_user() OWNER TO postgres;

--
-- Name: has_capability(uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.has_capability(p_org_id uuid, p_capability text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce(
    case
      when public.is_org_manager(p_org_id) then true
      else (
        select coalesce(
          (m.permissions ->> p_capability)::boolean,
          p_capability = any(array[
            'view_financials', 'view_estimates', 'view_field', 'add_notes', 'schedule'
          ])
        )
        from public.org_members m
        where m.org_id = p_org_id
          and m.user_id = auth.uid()
      )
    end,
    false
  );
$$;


ALTER FUNCTION public.has_capability(p_org_id uuid, p_capability text) OWNER TO postgres;

--
-- Name: FUNCTION has_capability(p_org_id uuid, p_capability text); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.has_capability(p_org_id uuid, p_capability text) IS 'Capability resolver for the assistant/member permission model. Manager-tier roles (owner/admin/agency_admin) always true. Member tier reads org_members.permissions, falling back to per-capability defaults that preserve legacy plain-member behavior. No membership row or unknown capability key resolves false, never an error.';


--
-- Name: is_org_manager(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_org_manager(p_org_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.org_members
    where user_id = auth.uid()
      and org_id = p_org_id
      and role in ('owner', 'admin', 'agency_admin')
  );
$$;


ALTER FUNCTION public.is_org_manager(p_org_id uuid) OWNER TO postgres;

--
-- Name: is_pipeline_manager(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_pipeline_manager() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'manager')
$$;


ALTER FUNCTION public.is_pipeline_manager() OWNER TO postgres;

--
-- Name: is_pipeline_user(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_pipeline_user() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (select 1 from public.profiles where id = auth.uid())
$$;


ALTER FUNCTION public.is_pipeline_user() OWNER TO postgres;

--
-- Name: is_platform_admin(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_platform_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1
    from public.org_members m
    join public.organizations o on o.id = m.org_id
    where m.user_id = auth.uid()
      and o.tenant_type = 'internal'
      and m.role in ('owner', 'agency_admin')
  );
$$;


ALTER FUNCTION public.is_platform_admin() OWNER TO postgres;

--
-- Name: FUNCTION is_platform_admin(); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.is_platform_admin() IS 'True if the caller holds an owner/agency_admin membership in some internal-type org (StructTech itself). Gate for provisioning RPCs and tenant_modules writes — never used as a blanket read bypass.';


--
-- Name: is_staff(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_staff() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (select 1 from public.staff_users where user_id = auth.uid())
$$;


ALTER FUNCTION public.is_staff() OWNER TO postgres;

--
-- Name: job_master_sign_off(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.job_master_sign_off(p_work_order_id uuid) RETURNS TABLE(master_id uuid, sign_off_at timestamp with time zone)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select m.id, m.sign_off_at
  from public.work_orders w
  join public.work_orders m on m.job_id = w.job_id and m.kind = 'master'
  where w.id = p_work_order_id;
$$;


ALTER FUNCTION public.job_master_sign_off(p_work_order_id uuid) OWNER TO postgres;

--
-- Name: list_org_members(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.list_org_members(p_org_id uuid) RETURNS TABLE(user_id uuid, full_name text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of organization %', p_org_id;
  end if;

  return query
    select om.user_id, om.full_name
    from public.org_members om
    where om.org_id = p_org_id
    order by om.full_name;
end;
$$;


ALTER FUNCTION public.list_org_members(p_org_id uuid) OWNER TO postgres;

--
-- Name: my_active_lead_count(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.my_active_lead_count() RETURNS integer
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select count(*)::int from public.leads where owner_id = auth.uid() and status = 'active';
$$;


ALTER FUNCTION public.my_active_lead_count() OWNER TO postgres;

--
-- Name: my_avg_cycle_days(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.my_avg_cycle_days() RETURNS numeric
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce(round(avg(extract(epoch from (closed_at - created_at)) / 86400), 1), 0)
  from public.leads where owner_id = auth.uid() and status = 'closed_won' and closed_at is not null;
$$;


ALTER FUNCTION public.my_avg_cycle_days() OWNER TO postgres;

--
-- Name: my_closes_this_month(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.my_closes_this_month() RETURNS integer
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select count(*)::int from public.leads
  where owner_id = auth.uid() and status = 'closed_won' and closed_at >= date_trunc('month', now());
$$;


ALTER FUNCTION public.my_closes_this_month() OWNER TO postgres;

--
-- Name: my_open_pipeline_value(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.my_open_pipeline_value() RETURNS numeric
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce(sum(value), 0) from public.leads
  where owner_id = auth.uid() and status = 'active' and stage in ('proposal_sent','negotiating') and value is not null;
$$;


ALTER FUNCTION public.my_open_pipeline_value() OWNER TO postgres;

--
-- Name: my_org_ids(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.my_org_ids() RETURNS SETOF uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select org_id from public.org_members where user_id = auth.uid()
$$;


ALTER FUNCTION public.my_org_ids() OWNER TO postgres;

--
-- Name: my_wh_role(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.my_wh_role() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce(
    -- (a) the caller's active WH team role for their org, if a row exists
    (select role
     from public.wh_team_members
     where user_id = auth.uid()
       and status = 'active'
       and org_id in (select public.my_org_ids())
     order by (role = 'admin') desc, (role = 'assistant') desc
     limit 1),
    -- (b) else 'admin' if the caller is the org owner of a WH org they belong to
    (select 'admin'
     from public.org_members
     where user_id = auth.uid()
       and role = 'owner'
       and org_id in (select public.my_org_ids())
     limit 1)
    -- (c) else null (coalesce yields null)
  );
$$;


ALTER FUNCTION public.my_wh_role() OWNER TO postgres;

--
-- Name: my_win_rate(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.my_win_rate() RETURNS numeric
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select case when total = 0 then 0 else round((won::numeric / total) * 100, 1) end
  from (
    select count(*) filter (where status = 'closed_won') as won,
           count(*) filter (where status in ('closed_won','closed_lost')) as total
    from public.leads where owner_id = auth.uid()
  ) t;
$$;


ALTER FUNCTION public.my_win_rate() OWNER TO postgres;

--
-- Name: order_scope(uuid, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.order_scope(p_deal_id uuid, p_ordered_at timestamp with time zone DEFAULT now()) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_owner_id uuid;
  v_actor_id uuid;
begin
  select org_id, owner_id into v_org_id, v_owner_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (public.is_org_manager(v_org_id) or coalesce(v_owner_id = auth.uid(), false)) then
    raise exception 'not authorized: only the deal owner or an org manager can order scope';
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals
  set roof_scope_ordered_at = p_ordered_at,
      updated_at = now()
  where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, to_value, actor_id)
  values (p_deal_id, v_org_id, 'scope_ordered', coalesce(p_ordered_at::text, 'cleared'), v_actor_id);
end;
$$;


ALTER FUNCTION public.order_scope(p_deal_id uuid, p_ordered_at timestamp with time zone) OWNER TO postgres;

--
-- Name: FUNCTION order_scope(p_deal_id uuid, p_ordered_at timestamp with time zone); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.order_scope(p_deal_id uuid, p_ordered_at timestamp with time zone) IS 'Sets/clears deals.roof_scope_ordered_at. Explicit null param clears it; omitted param defaults to now(). No completion gating — see migration header.';


--
-- Name: present_estimate(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.present_estimate(p_estimate_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_status text;
  v_subtotal numeric;
  v_tax_amount numeric;
begin
  select org_id, status, subtotal, tax_amount into v_org_id, v_status, v_subtotal, v_tax_amount
  from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  if v_status in ('signed', 'void') then
    raise exception 'estimate % cannot be presented from status %', p_estimate_id, v_status;
  end if;

  update public.estimates
  set status = 'presented',
      presented_total = v_subtotal + coalesce(v_tax_amount, 0),
      presented_at = now()
  where id = p_estimate_id;
end;
$$;


ALTER FUNCTION public.present_estimate(p_estimate_id uuid) OWNER TO postgres;

--
-- Name: present_quote(uuid, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.present_quote(p_deal_id uuid, p_presented_at timestamp with time zone DEFAULT now()) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_owner_id uuid;
  v_actor_id uuid;
begin
  select org_id, owner_id into v_org_id, v_owner_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (public.is_org_manager(v_org_id) or coalesce(v_owner_id = auth.uid(), false)) then
    raise exception 'not authorized: only the deal owner or an org manager can present the quote';
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals
  set quote_presented_at = p_presented_at,
      updated_at = now()
  where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, to_value, actor_id)
  values (p_deal_id, v_org_id, 'quote_presented', coalesce(p_presented_at::text, 'cleared'), v_actor_id);
end;
$$;


ALTER FUNCTION public.present_quote(p_deal_id uuid, p_presented_at timestamp with time zone) OWNER TO postgres;

--
-- Name: FUNCTION present_quote(p_deal_id uuid, p_presented_at timestamp with time zone); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.present_quote(p_deal_id uuid, p_presented_at timestamp with time zone) IS 'Sets/clears deals.quote_presented_at. Explicit null param clears it; omitted param defaults to now(). No completion gating — see migration header.';


--
-- Name: protect_roadmap_columns(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.protect_roadmap_columns() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
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
end $$;


ALTER FUNCTION public.protect_roadmap_columns() OWNER TO postgres;

--
-- Name: record_work_order_sign_off(uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.record_work_order_sign_off(p_work_order_id uuid, p_notes text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_was_signed_off boolean;
  v_old_notes text;
  v_actor_id uuid;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'master');

  select sign_off_at is not null, sign_off_notes
  into v_was_signed_off, v_old_notes
  from public.work_orders where id = p_work_order_id;

  update public.work_orders
  set sign_off_at = coalesce(sign_off_at, now()),
      sign_off_notes = coalesce(p_notes, sign_off_notes),
      updated_at = now()
  where id = p_work_order_id;

  if v_was_signed_off and p_notes is not null and p_notes is distinct from v_old_notes then
    select id into v_actor_id from public.profiles where id = auth.uid();
    insert into public.work_order_activity (work_order_id, org_id, action, from_value, to_value, actor_id)
    values (p_work_order_id, v_org_id, 'signoff_notes_updated_after_signoff', coalesce(v_old_notes, '—'), p_notes, v_actor_id);
  end if;
end;
$$;


ALTER FUNCTION public.record_work_order_sign_off(p_work_order_id uuid, p_notes text) OWNER TO postgres;

--
-- Name: remove_check_in_photo(uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.remove_check_in_photo(p_check_in_id uuid, p_photo_data_url text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.check_ins where id = p_check_in_id;

  if v_org_id is null then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  update public.check_ins
  set photos = array_remove(photos, p_photo_data_url),
      updated_at = now()
  where id = p_check_in_id;
end;
$$;


ALTER FUNCTION public.remove_check_in_photo(p_check_in_id uuid, p_photo_data_url text) OWNER TO postgres;

--
-- Name: reorder_estimate_line_items(uuid, uuid[]); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.reorder_estimate_line_items(p_estimate_id uuid, p_line_item_ids uuid[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_status text;
  v_id uuid;
  v_idx int := 0;
begin
  select org_id, status into v_org_id, v_status
  from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  if v_status in ('signed', 'void') then
    raise exception 'estimate % is locked (status: %) — cannot reorder line items', p_estimate_id, v_status;
  end if;

  foreach v_id in array p_line_item_ids loop
    update public.estimate_line_items
    set sort_order = v_idx, updated_at = now()
    where id = v_id and estimate_id = p_estimate_id;
    v_idx := v_idx + 1;
  end loop;
end;
$$;


ALTER FUNCTION public.reorder_estimate_line_items(p_estimate_id uuid, p_line_item_ids uuid[]) OWNER TO postgres;

--
-- Name: restore_deal(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.restore_deal(p_deal_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_owner_id uuid;
  v_actor_id uuid;
begin
  select org_id, owner_id into v_org_id, v_owner_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (
    public.is_org_manager(v_org_id)
    or coalesce(v_owner_id = auth.uid(), false)
    or public.has_capability(v_org_id, 'edit_leads')
  ) then
    raise exception 'not authorized: only the deal owner, an org manager, or a caller with edit_leads can restore this deal';
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals set archived_at = null where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, actor_id)
  values (p_deal_id, v_org_id, 'restored', v_actor_id);
end;
$$;


ALTER FUNCTION public.restore_deal(p_deal_id uuid) OWNER TO postgres;

--
-- Name: restore_tracker_item(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.restore_tracker_item(p_item_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


ALTER FUNCTION public.restore_tracker_item(p_item_id uuid) OWNER TO postgres;

--
-- Name: restore_tracker_project(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.restore_tracker_project(p_project_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


ALTER FUNCTION public.restore_tracker_project(p_project_id uuid) OWNER TO postgres;

--
-- Name: restore_work_order(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.restore_work_order(p_work_order_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_kind text;
  v_job_id uuid;
  v_master_voided_at timestamptz;
begin
  select org_id, kind, job_id
  into v_org_id, v_kind, v_job_id
  from public.work_orders where id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  -- A live trade hanging under a voided master is not a state the tree allows.
  -- Refusing here is not SCOPE §2.8 blocking: nothing is disabled pending other
  -- data, the action itself would produce an invalid tree, and the message
  -- names the one move that works.
  if v_kind = 'trade' then
    select m.voided_at into v_master_voided_at
    from public.work_orders m
    where m.job_id = v_job_id and m.kind = 'master';

    if v_master_voided_at is not null then
      raise exception 'trade work order % cannot be restored while its master work order is voided — restore the master, which brings back every trade that was voided with it', p_work_order_id;
    end if;
  end if;

  update public.work_orders
  set voided_at = null,
      void_cascade_source_id = null,
      updated_at = now()
  where id = p_work_order_id;

  if v_kind = 'master' then
    -- Matches ONLY rows this master's cascade voided. A trade with a null
    -- marker was voided deliberately and is left exactly where it is.
    update public.work_orders
    set voided_at = null,
        void_cascade_source_id = null,
        updated_at = now()
    where kind = 'trade'
      and void_cascade_source_id = p_work_order_id;

    -- Reactivates to the exact status held before the cascade. The not-exists
    -- guard covers the one case that would otherwise produce two active
    -- documents: an agreement created while the master was voided.
    update public.work_order_agreements
    set status = void_cascade_prior_status,
        voided_at = null,
        void_reason = null,
        void_cascade_prior_status = null,
        void_cascade_source_id = null,
        updated_at = now()
    where void_cascade_source_id = p_work_order_id
      and not exists (
        select 1 from public.work_order_agreements a2
        where a2.work_order_id = work_order_agreements.work_order_id
          and a2.status <> 'voided'
      );
  end if;
end;
$$;


ALTER FUNCTION public.restore_work_order(p_work_order_id uuid) OWNER TO postgres;

--
-- Name: roadmap_playbook(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.roadmap_playbook(q text) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
select case q
  when 'sales' then '{
    "title": "Sales Pipeline System",
    "why": "Leads are slipping in twice — slow first response AND estimates dying in silence. One custom sales system fixes the whole pipe: capture, respond, quote, follow up, close.",
    "milestones": [
      {"label":"StructTech maps your current sales flow and builds your custom pipeline — instant lead response, estimate tracking, and automatic follow-up in one system","owner":"jacob"},
      {"label":"Every lead answered inside the response window and logged in the pipeline — no tracking in your head","owner":"client"},
      {"label":"Every estimate logged the day it goes out, with win/loss reason captured on close","owner":"client"},
      {"label":"{{W}} straight: every lead answered under 5 minutes AND one job won from a revived estimate","owner":"client"},
      {"label":"StructTech trains your team on the pipeline and documents the process — runs without you","owner":"jacob"}
    ]}'::jsonb
  when 'q1' then '{
    "title": "Instant Lead Response System",
    "why": "Speed wins jobs. The contractor who answers first gets the walkthrough — this system makes sure that is always you, even when you are on a job.",
    "milestones": [
      {"label":"StructTech maps how leads reach you today and builds your custom capture + instant-response system — every call and form fill answered immediately","owner":"jacob"},
      {"label":"Every lead gets a personal follow-up within the response window — no lead sits overnight","owner":"client"},
      {"label":"Log the outcome of every lead conversation in the pipeline","owner":"client"},
      {"label":"{{W}} straight: every new lead answered in under 5 minutes","owner":"client"},
      {"label":"StructTech trains your team and documents the response process — runs without you touching it","owner":"jacob"}
    ]}'::jsonb
  when 'q2' then '{
    "title": "Estimate Follow-Up Engine",
    "why": "Most estimates die from silence, not price. Consistent follow-up revives jobs you already quoted.",
    "milestones": [
      {"label":"StructTech reviews your open estimates and builds your custom follow-up engine — automatic touchpoints at set intervals, tracked in your pipeline","owner":"jacob"},
      {"label":"Every estimate logged with amount and expected decision date the day it goes out","owner":"client"},
      {"label":"Win/loss reason captured on every closed estimate — your pricing intelligence","owner":"client"},
      {"label":"Win one job from a revived estimate that would have died silent","owner":"client"},
      {"label":"StructTech documents the cadence and trains the team — the engine runs itself","owner":"jacob"}
    ]}'::jsonb
  when 'q3' then '{
    "title": "Field-to-Office Communication Flow",
    "why": "Work happens in the field but the office finds out whenever someone remembers to mention it. This closes that gap the same day.",
    "milestones": [
      {"label":"StructTech maps what the field knows that the office does not, then builds your custom crew check-in system — photos, hours, materials in under 5 minutes from a phone","owner":"jacob"},
      {"label":"Crew lead completes the daily check-in on every active job — end of day, no exceptions","owner":"client"},
      {"label":"Scope changes logged the moment they happen, not at invoice time","owner":"client"},
      {"label":"{{W}} of consistent daily logs from every active job","owner":"client"},
      {"label":"StructTech trains every crew member and documents the process — office dashboard live","owner":"jacob"}
    ]}'::jsonb
  when 'q4' then '{
    "title": "Real-Time Job Cost Tracking",
    "why": "If you cannot see what a job actually costs while it is running, you find out you lost money when it is too late to fix.",
    "milestones": [
      {"label":"StructTech breaks down how you price and track costs today, then builds your custom per-job cost tracker — labor, materials, and margin in real time","owner":"jacob"},
      {"label":"Log labor hours and material costs against each active job as they happen","owner":"client"},
      {"label":"Review estimated vs actual margin on every job close-out","owner":"client"},
      {"label":"{{J}} jobs fully costed — you know your real margin on each","owner":"client"},
      {"label":"StructTech trains the office and documents costing — margin reports automatic","owner":"jacob"}
    ]}'::jsonb
  when 'q5' then '{
    "title": "One Hub, Fewer Apps",
    "why": "Every app your data hops between is a place it gets lost. We consolidate into one hub your whole crew actually uses.",
    "milestones": [
      {"label":"StructTech inventories every tool, spreadsheet, and paper process, then builds your custom ops hub — connecting what is worth keeping, replacing what is not","owner":"jacob"},
      {"label":"Whole crew works out of the hub — no side spreadsheets, no I-will-add-it-later","owner":"client"},
      {"label":"Cancel the redundant subscriptions and confirm nothing breaks","owner":"client"},
      {"label":"{{W}} with the entire operation running through one system","owner":"client"},
      {"label":"StructTech documents the hub and trains the team — one system, owned by you","owner":"jacob"}
    ]}'::jsonb
  when 'q6' then '{
    "title": "Key-Person Backup System",
    "why": "If one person getting sick stops your operation, you do not have a system — you have a liability.",
    "milestones": [
      {"label":"StructTech identifies what knowledge lives only in someone''s head and documents your critical workflows into SOPs built into your hub — not a binder on a shelf","owner":"jacob"},
      {"label":"Name a backup person for each critical role","owner":"client"},
      {"label":"Backup shadows the primary through one full cycle of the workflow","owner":"client"},
      {"label":"Backup person runs the workflow solo for one full week","owner":"client"},
      {"label":"StructTech finalizes SOPs and cross-training — single point of failure eliminated","owner":"jacob"}
    ]}'::jsonb
  when 'q7' then '{
    "title": "Same-Day Invoicing System",
    "why": "Every day an invoice sits unsent is a day you are funding your client''s business instead of yours.",
    "milestones": [
      {"label":"StructTech maps your job-completion-to-payment cycle and builds custom invoice automation — the moment a job closes, the invoice drafts itself, connected to your existing accounting","owner":"jacob"},
      {"label":"Review and send the drafted invoice the same day the job completes","owner":"client"},
      {"label":"Log payment status so overdue invoices trigger follow-up automatically","owner":"client"},
      {"label":"{{J}} straight jobs invoiced same-day","owner":"client"},
      {"label":"StructTech trains the office and documents the flow — cash cycle measurably shorter","owner":"jacob"}
    ]}'::jsonb
  when 'q8' then '{
    "title": "Visual Crew Scheduling Board",
    "why": "Scheduling from memory and texts means double-booked crews and dead days. One board, whole week visible, no surprises.",
    "milestones": [
      {"label":"StructTech maps how jobs get scheduled today and builds your custom scheduling board — every job, every crew member, whole week visible, updates pushed to phones","owner":"jacob"},
      {"label":"All scheduling happens on the board — no side texts, no verbal-only changes","owner":"client"},
      {"label":"Crew checks the board before every shift instead of calling you","owner":"client"},
      {"label":"{{W}} with zero scheduling conflicts or dead days","owner":"client"},
      {"label":"StructTech trains whoever runs scheduling and documents it — you are out of the middle","owner":"jacob"}
    ]}'::jsonb
  when 'q9' then '{
    "title": "Automated Client Updates",
    "why": "Clients who know what is happening do not call, do not stress, and do not dispute scope.",
    "milestones": [
      {"label":"StructTech maps every client touchpoint from contract to final payment and builds your custom update system — en-route texts, daily progress with photos, completion notice, all automatic","owner":"jacob"},
      {"label":"Approve the message templates so they sound like you","owner":"client"},
      {"label":"Crew captures the job photos that feed the updates","owner":"client"},
      {"label":"One full job start-to-finish with automated updates — zero what-is-happening calls","owner":"client"},
      {"label":"StructTech locks the templates and documents the flow — runs on every job automatically","owner":"jacob"}
    ]}'::jsonb
  when 'q10' then '{
    "title": "Owner Independence Dashboard",
    "why": "The business should run when you take a day off.",
    "milestones": [
      {"label":"StructTech lists every decision that routes through you and builds your custom owner dashboard — jobs, cash, crew, pipeline at a glance, plus delegation workflows","owner":"jacob"},
      {"label":"Delegate scheduling and invoicing to your second-in-command with clear authority limits","owner":"client"},
      {"label":"Weekly review rhythm — you check the dashboard instead of being in every conversation","owner":"client"},
      {"label":"Take a full day off — business runs without a single call to you","owner":"client"},
      {"label":"StructTech documents the delegation map and trains your second — you own growth, not operations","owner":"jacob"}
    ]}'::jsonb
  when 'q11' then '{
    "title": "Material Ordering System",
    "why": "Wrong materials, late deliveries, and emergency supply-house runs kill crew days. Ordering should flow straight from the estimate — not from memory.",
    "milestones": [
      {"label":"StructTech maps how materials get ordered today — who orders, from where, what goes wrong — and builds your custom ordering system tied to each job''s estimate","owner":"jacob"},
      {"label":"Every job''s material list generated from the estimate before the crew rolls","owner":"client"},
      {"label":"Deliveries confirmed against the list — shortages flagged before they cost a crew day","owner":"client"},
      {"label":"{{J}} jobs with zero emergency supply runs","owner":"client"},
      {"label":"StructTech trains whoever owns ordering and documents the flow — materials just show up right","owner":"jacob"}
    ]}'::jsonb
  else null
end $$;


ALTER FUNCTION public.roadmap_playbook(q text) OWNER TO postgres;

--
-- Name: set_tenant_module(uuid, text, boolean, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.set_tenant_module(p_org_id uuid, p_module_key text, p_enabled boolean DEFAULT true, p_config jsonb DEFAULT '{}'::jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_id uuid;
begin
  if not is_platform_admin() then
    raise exception 'only a platform admin can set tenant module entitlements';
  end if;

  insert into public.tenant_modules (org_id, module_key, enabled, config)
  values (p_org_id, p_module_key, p_enabled, p_config)
  on conflict (org_id, module_key) do update
    set enabled = excluded.enabled,
        config = excluded.config,
        updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;


ALTER FUNCTION public.set_tenant_module(p_org_id uuid, p_module_key text, p_enabled boolean, p_config jsonb) OWNER TO postgres;

--
-- Name: sign_estimate(uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sign_estimate(p_estimate_id uuid, p_signer_name text, p_signer_role text, p_signature_data text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_status text;
  v_signature_id uuid;
begin
  select org_id, status into v_org_id, v_status
  from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  if v_status <> 'presented' then
    raise exception 'estimate % must be presented before it can be signed (current status: %)', p_estimate_id, v_status;
  end if;

  insert into public.signatures (org_id, estimate_id, signer_name, signer_role, signature_data)
  values (v_org_id, p_estimate_id, p_signer_name, p_signer_role, p_signature_data)
  returning id into v_signature_id;

  update public.estimates
  set status = 'signed',
      signed_at = now()
  where id = p_estimate_id;

  return v_signature_id;
end;
$$;


ALTER FUNCTION public.sign_estimate(p_estimate_id uuid, p_signer_name text, p_signer_role text, p_signature_data text) OWNER TO postgres;

--
-- Name: touch_leads_updated_at(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.touch_leads_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
begin new.updated_at = now(); return new; end;
$$;


ALTER FUNCTION public.touch_leads_updated_at() OWNER TO postgres;

--
-- Name: tracker_status_config(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.tracker_status_config(p_org_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce(tm.config -> 'statuses', '[]'::jsonb)
  from public.tenant_modules tm
  where tm.org_id = p_org_id
    and tm.module_key = 'tracker'
  limit 1;
$$;


ALTER FUNCTION public.tracker_status_config(p_org_id uuid) OWNER TO postgres;

--
-- Name: tracker_type_config(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.tracker_type_config(p_org_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce(tm.config -> 'types', '[]'::jsonb)
  from public.tenant_modules tm
  where tm.org_id = p_org_id
    and tm.module_key = 'tracker'
  limit 1;
$$;


ALTER FUNCTION public.tracker_type_config(p_org_id uuid) OWNER TO postgres;

--
-- Name: update_check_in(uuid, text, date, numeric, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_check_in(p_check_in_id uuid, p_crew_name text DEFAULT NULL::text, p_check_in_date date DEFAULT NULL::date, p_hours numeric DEFAULT NULL::numeric, p_materials_used text DEFAULT NULL::text, p_blockers text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.check_ins where id = p_check_in_id;

  if v_org_id is null then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'check-in not found or not accessible: %', p_check_in_id;
  end if;

  update public.check_ins
  set crew_name = coalesce(p_crew_name, crew_name),
      check_in_date = coalesce(p_check_in_date, check_in_date),
      hours = coalesce(p_hours, hours),
      materials_used = coalesce(p_materials_used, materials_used),
      blockers = coalesce(p_blockers, blockers),
      updated_at = now()
  where id = p_check_in_id;
end;
$$;


ALTER FUNCTION public.update_check_in(p_check_in_id uuid, p_crew_name text, p_check_in_date date, p_hours numeric, p_materials_used text, p_blockers text) OWNER TO postgres;

--
-- Name: update_deal_fields(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_deal_fields(p_deal_id uuid, p_patch jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_owner_id uuid;
  v_actor_id uuid;
  v_key text;
  v_allowed text[] := array[
    'contact_name', 'company', 'email', 'phone', 'value', 'trade', 'crew_size',
    'lead_type', 'project_address', 'billing_address', 'first_name', 'last_name',
    'secondary_phone', 'remodel_or_new_construction', 'existing_roof_type',
    'roof_type_requested', 'service_address_street', 'service_address_city',
    'service_address_state', 'service_address_zip', 'referral_name', 'tags'
  ];
begin
  select org_id, owner_id into v_org_id, v_owner_id
  from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (
    public.is_org_manager(v_org_id)
    or coalesce(v_owner_id = auth.uid(), false)
    or public.has_capability(v_org_id, 'edit_leads')
  ) then
    raise exception 'not authorized: only the deal owner, an org manager, or a caller with edit_leads can edit this deal';
  end if;

  for v_key in select jsonb_object_keys(p_patch) loop
    if not (v_key = any(v_allowed)) then
      raise exception 'field not writable via patch: %', v_key;
    end if;
  end loop;

  if p_patch ? 'value' and not public.has_capability(v_org_id, 'view_financials') then
    raise exception 'not authorized: view_financials capability required to write deal value';
  end if;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals
  set
    contact_name = case
      when p_patch ? 'contact_name' and nullif(trim(p_patch->>'contact_name'), '') is not null
        then trim(p_patch->>'contact_name')
      when p_patch ? 'contact_name' or p_patch ? 'first_name' or p_patch ? 'last_name' then
        coalesce(
          nullif(trim(concat_ws(' ',
            case when p_patch ? 'first_name' then p_patch->>'first_name' else first_name end,
            case when p_patch ? 'last_name' then p_patch->>'last_name' else last_name end
          )), ''),
          contact_name
        )
      else contact_name
    end,
    company = case when p_patch ? 'company' then p_patch->>'company' else company end,
    email = case when p_patch ? 'email' then p_patch->>'email' else email end,
    phone = case when p_patch ? 'phone' then p_patch->>'phone' else phone end,
    value = case when p_patch ? 'value' then nullif(p_patch->>'value', '')::numeric else value end,
    trade = case when p_patch ? 'trade' then p_patch->>'trade' else trade end,
    crew_size = case when p_patch ? 'crew_size' then nullif(p_patch->>'crew_size', '')::integer else crew_size end,
    lead_type = case when p_patch ? 'lead_type' then p_patch->>'lead_type' else lead_type end,
    project_address = case when p_patch ? 'project_address' then p_patch->>'project_address' else project_address end,
    billing_address = case when p_patch ? 'billing_address' then p_patch->>'billing_address' else billing_address end,
    first_name = case when p_patch ? 'first_name' then p_patch->>'first_name' else first_name end,
    last_name = case when p_patch ? 'last_name' then p_patch->>'last_name' else last_name end,
    secondary_phone = case when p_patch ? 'secondary_phone' then p_patch->>'secondary_phone' else secondary_phone end,
    remodel_or_new_construction = case when p_patch ? 'remodel_or_new_construction' then p_patch->>'remodel_or_new_construction' else remodel_or_new_construction end,
    existing_roof_type = case
      when not (p_patch ? 'existing_roof_type') then existing_roof_type
      when jsonb_typeof(p_patch->'existing_roof_type') = 'null' then null
      else (select coalesce(array_agg(x), array[]::text[]) from jsonb_array_elements_text(p_patch->'existing_roof_type') x)
    end,
    roof_type_requested = case
      when not (p_patch ? 'roof_type_requested') then roof_type_requested
      when jsonb_typeof(p_patch->'roof_type_requested') = 'null' then null
      else (select coalesce(array_agg(x), array[]::text[]) from jsonb_array_elements_text(p_patch->'roof_type_requested') x)
    end,
    service_address_street = case when p_patch ? 'service_address_street' then p_patch->>'service_address_street' else service_address_street end,
    service_address_city = case when p_patch ? 'service_address_city' then p_patch->>'service_address_city' else service_address_city end,
    service_address_state = case when p_patch ? 'service_address_state' then p_patch->>'service_address_state' else service_address_state end,
    service_address_zip = case when p_patch ? 'service_address_zip' then p_patch->>'service_address_zip' else service_address_zip end,
    referral_name = case when p_patch ? 'referral_name' then p_patch->>'referral_name' else referral_name end,
    tags = case
      when not (p_patch ? 'tags') then tags
      when jsonb_typeof(p_patch->'tags') = 'null' then null
      else (select coalesce(array_agg(x), array[]::text[]) from jsonb_array_elements_text(p_patch->'tags') x)
    end,
    updated_at = now()
  where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, actor_id)
  values (p_deal_id, v_org_id, 'details_updated', v_actor_id);
end;
$$;


ALTER FUNCTION public.update_deal_fields(p_deal_id uuid, p_patch jsonb) OWNER TO postgres;

--
-- Name: update_deal_stage(uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_deal_stage(p_deal_id uuid, p_new_stage text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_owner_id uuid;
  v_stage_valid boolean;
begin
  select org_id, owner_id into v_org_id, v_owner_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (
    public.is_org_manager(v_org_id)
    or coalesce(v_owner_id = auth.uid(), false)
    or public.has_capability(v_org_id, 'edit_leads')
  ) then
    raise exception 'not authorized: only the deal owner, an org manager, or a caller with edit_leads can change stage';
  end if;

  select exists (
    select 1
    from jsonb_array_elements(public.crm_stage_config(v_org_id)) as stage
    where stage ->> 'key' = p_new_stage
  ) into v_stage_valid;

  if not v_stage_valid then
    raise exception 'stage % is not configured for organization %', p_new_stage, v_org_id;
  end if;

  update public.deals set stage = p_new_stage where id = p_deal_id;
end;
$$;


ALTER FUNCTION public.update_deal_stage(p_deal_id uuid, p_new_stage text) OWNER TO postgres;

--
-- Name: update_estimate_build_mode(uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_estimate_build_mode(p_estimate_id uuid, p_build_mode text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_status text;
begin
  select org_id, status into v_org_id, v_status
  from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  if v_status in ('signed', 'void') then
    raise exception 'estimate % is locked (status: %)', p_estimate_id, v_status;
  end if;

  if p_build_mode not in ('manual', 'guided') then
    raise exception 'invalid build_mode: %', p_build_mode;
  end if;

  update public.estimates
  set build_mode = p_build_mode,
      updated_at = now()
  where id = p_estimate_id;
end;
$$;


ALTER FUNCTION public.update_estimate_build_mode(p_estimate_id uuid, p_build_mode text) OWNER TO postgres;

--
-- Name: update_estimate_contact(uuid, text, text, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_estimate_contact(p_estimate_id uuid, p_contact_name text DEFAULT NULL::text, p_company text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_email text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  -- No status lock, unlike update_estimate_details — correcting a contact
  -- typo doesn't touch pricing or the signed/presented content, so it's
  -- safe at any status including signed. See migration header.
  update public.estimates
  set contact_name = coalesce(p_contact_name, contact_name),
      company = coalesce(p_company, company),
      phone = coalesce(p_phone, phone),
      email = coalesce(p_email, email),
      updated_at = now()
  where id = p_estimate_id;
end;
$$;


ALTER FUNCTION public.update_estimate_contact(p_estimate_id uuid, p_contact_name text, p_company text, p_phone text, p_email text) OWNER TO postgres;

--
-- Name: update_estimate_details(uuid, numeric, text, text, date, date, numeric, text, boolean, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_estimate_details(p_estimate_id uuid, p_squares numeric DEFAULT NULL::numeric, p_pitch text DEFAULT NULL::text, p_site_address text DEFAULT NULL::text, p_estimate_date date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_tax_rate numeric DEFAULT NULL::numeric, p_notes_terms text DEFAULT NULL::text, p_clear_valid_until boolean DEFAULT false, p_clear_tax_rate boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_status text;
begin
  select org_id, status into v_org_id, v_status
  from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  if v_status in ('signed', 'void') then
    raise exception 'estimate % is locked (status: %)', p_estimate_id, v_status;
  end if;

  update public.estimates
  set squares = coalesce(p_squares, squares),
      pitch = coalesce(p_pitch, pitch),
      site_address = coalesce(p_site_address, site_address),
      estimate_date = coalesce(p_estimate_date, estimate_date),
      valid_until = case when p_clear_valid_until then null else coalesce(p_valid_until, valid_until) end,
      tax_rate = case when p_clear_tax_rate then null else coalesce(p_tax_rate, tax_rate) end,
      notes_terms = coalesce(p_notes_terms, notes_terms),
      updated_at = now()
  where id = p_estimate_id;
end;
$$;


ALTER FUNCTION public.update_estimate_details(p_estimate_id uuid, p_squares numeric, p_pitch text, p_site_address text, p_estimate_date date, p_valid_until date, p_tax_rate numeric, p_notes_terms text, p_clear_valid_until boolean, p_clear_tax_rate boolean) OWNER TO postgres;

--
-- Name: update_estimate_line_item(uuid, text, numeric, numeric, integer, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_estimate_line_item(p_line_item_id uuid, p_description text DEFAULT NULL::text, p_quantity numeric DEFAULT NULL::numeric, p_unit_price numeric DEFAULT NULL::numeric, p_sort_order integer DEFAULT NULL::integer, p_unit text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_estimate_id uuid;
  v_status text;
begin
  select li.org_id, li.estimate_id into v_org_id, v_estimate_id
  from public.estimate_line_items li
  where li.id = p_line_item_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'line item not found or not accessible: %', p_line_item_id;
  end if;

  select status into v_status from public.estimates where id = v_estimate_id;

  if v_status in ('signed', 'void') then
    raise exception 'estimate is locked (status: %) — line items can only change before signing', v_status;
  end if;

  update public.estimate_line_items
  set description = coalesce(p_description, description),
      quantity = coalesce(p_quantity, quantity),
      unit_price = coalesce(p_unit_price, unit_price),
      sort_order = coalesce(p_sort_order, sort_order),
      unit = coalesce(p_unit, unit),
      updated_at = now()
  where id = p_line_item_id;
end;
$$;


ALTER FUNCTION public.update_estimate_line_item(p_line_item_id uuid, p_description text, p_quantity numeric, p_unit_price numeric, p_sort_order integer, p_unit text) OWNER TO postgres;

--
-- Name: update_intake_checklist_field(uuid, text[], jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_intake_checklist_field(p_deal_id uuid, p_field_path text[], p_value jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_owner_id uuid;
  v_intake jsonb;
  v_value jsonb;
begin
  if array_length(p_field_path, 1) is null or array_length(p_field_path, 1) not between 1 and 2 then
    raise exception 'p_field_path must have 1 or 2 elements, got %', p_field_path;
  end if;

  select org_id, owner_id, coalesce(intake_checklist, '{}'::jsonb)
  into v_org_id, v_owner_id, v_intake
  from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  if not (
    public.is_org_manager(v_org_id)
    or coalesce(v_owner_id = auth.uid(), false)
    or public.has_capability(v_org_id, 'edit_leads')
  ) then
    raise exception 'not authorized: only the deal owner, an org manager, or a caller with edit_leads can edit this checklist';
  end if;

  v_value := coalesce(p_value, 'null'::jsonb);

  if array_length(p_field_path, 1) = 2 then
    v_intake := jsonb_set(
      v_intake,
      p_field_path[1:1],
      coalesce(v_intake -> p_field_path[1], '{}'::jsonb),
      true
    );
  end if;

  v_intake := jsonb_set(v_intake, p_field_path, v_value, true);

  update public.deals
  set intake_checklist = v_intake,
      updated_at = now()
  where id = p_deal_id;
end;
$$;


ALTER FUNCTION public.update_intake_checklist_field(p_deal_id uuid, p_field_path text[], p_value jsonb) OWNER TO postgres;

--
-- Name: FUNCTION update_intake_checklist_field(p_deal_id uuid, p_field_path text[], p_value jsonb); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.update_intake_checklist_field(p_deal_id uuid, p_field_path text[], p_value jsonb) IS 'Incremental (field-by-field, not blob-overwrite) writer for deals.intake_checklist — the mechanism behind both the intake-call and site-visit-scope checklists. No deal_activity log (see header note).';


--
-- Name: update_material_item(uuid, text, numeric, date, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_material_item(p_material_item_id uuid, p_name text DEFAULT NULL::text, p_quantity numeric DEFAULT NULL::numeric, p_ready_by date DEFAULT NULL::date, p_sort_order integer DEFAULT NULL::integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_work_order_id uuid;
  v_trade text;
  v_master_id uuid;
  v_sign_off_at timestamptz;
  v_old_name text;
  v_old_quantity numeric;
  v_old_ready_by date;
  v_actor_id uuid;
begin
  select mi.org_id, mi.work_order_id, mi.name, mi.quantity, mi.ready_by
  into v_org_id, v_work_order_id, v_old_name, v_old_quantity, v_old_ready_by
  from public.material_items mi
  where mi.id = p_material_item_id;

  if v_org_id is null then
    raise exception 'material item not found or not accessible: %', p_material_item_id;
  end if;

  -- A1.3b checked org against the parent; A1.4 adds the level. Split from the
  -- null check on purpose: PL/pgSQL does not guarantee short-circuit
  -- evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'material item not found or not accessible: %', p_material_item_id;
  end if;

  select w.trade into v_trade from public.work_orders w where w.id = v_work_order_id;

  select s.master_id, s.sign_off_at into v_master_id, v_sign_off_at
  from public.job_master_sign_off(v_work_order_id) s;

  update public.material_items
  set name = coalesce(p_name, name),
      quantity = coalesce(p_quantity, quantity),
      ready_by = coalesce(p_ready_by, ready_by),
      sort_order = coalesce(p_sort_order, sort_order),
      updated_at = now()
  where id = p_material_item_id;

  if v_sign_off_at is not null then
    select id into v_actor_id from public.profiles where id = auth.uid();
    insert into public.work_order_activity (work_order_id, org_id, action, from_value, to_value, actor_id)
    values (
      coalesce(v_master_id, v_work_order_id), v_org_id, 'material_updated_after_signoff',
      format('%s (qty %s%s)', v_old_name, v_old_quantity, case when v_old_ready_by is not null then ', ready ' || v_old_ready_by else '' end),
      format('%s (qty %s%s) [%s]', coalesce(p_name, v_old_name), coalesce(p_quantity, v_old_quantity), case when coalesce(p_ready_by, v_old_ready_by) is not null then ', ready ' || coalesce(p_ready_by, v_old_ready_by) else '' end, coalesce(v_trade, 'trade')),
      v_actor_id
    );
  end if;
end;
$$;


ALTER FUNCTION public.update_material_item(p_material_item_id uuid, p_name text, p_quantity numeric, p_ready_by date, p_sort_order integer) OWNER TO postgres;

--
-- Name: update_production_packet_callout(uuid, uuid, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_production_packet_callout(p_production_packet_id uuid, p_callout_id uuid, p_label text DEFAULT NULL::text, p_detail text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.production_packets where id = p_production_packet_id;

  if v_org_id is null then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  update public.production_packets
  set callouts = (
        select coalesce(jsonb_agg(
          case when (elem->>'id')::uuid = p_callout_id
            then jsonb_build_object(
              'id', elem->>'id',
              'label', coalesce(p_label, elem->>'label'),
              'detail', coalesce(p_detail, elem->>'detail')
            )
            else elem
          end
        ), '[]'::jsonb)
        from jsonb_array_elements(callouts) as elem
      ),
      updated_at = now()
  where id = p_production_packet_id;
end;
$$;


ALTER FUNCTION public.update_production_packet_callout(p_production_packet_id uuid, p_callout_id uuid, p_label text, p_detail text) OWNER TO postgres;

--
-- Name: update_production_packet_notes(uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_production_packet_notes(p_production_packet_id uuid, p_notes text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.production_packets where id = p_production_packet_id;

  if v_org_id is null then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'production packet not found or not accessible: %', p_production_packet_id;
  end if;

  update public.production_packets
  set notes = p_notes,
      updated_at = now()
  where id = p_production_packet_id;
end;
$$;


ALTER FUNCTION public.update_production_packet_notes(p_production_packet_id uuid, p_notes text) OWNER TO postgres;

--
-- Name: update_roadmap_fields(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_roadmap_fields(p_id uuid, p_patch jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


ALTER FUNCTION public.update_roadmap_fields(p_id uuid, p_patch jsonb) OWNER TO postgres;

--
-- Name: FUNCTION update_roadmap_fields(p_id uuid, p_patch jsonb); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.update_roadmap_fields(p_id uuid, p_patch jsonb) IS 'Build Tracker patch-update RPC (jsonb-patch + allowlist convention). Absent key = untouched; present key = write it, including clearing notes to null/empty.';


--
-- Name: update_roadmap_project(uuid, text, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_roadmap_project(p_project_id uuid, p_name text DEFAULT NULL::text, p_sort_order integer DEFAULT NULL::integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


ALTER FUNCTION public.update_roadmap_project(p_project_id uuid, p_name text, p_sort_order integer) OWNER TO postgres;

--
-- Name: FUNCTION update_roadmap_project(p_project_id uuid, p_name text, p_sort_order integer); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.update_roadmap_project(p_project_id uuid, p_name text, p_sort_order integer) IS 'Build Tracker project rename/reorder RPC. key is immutable by design (it is the stable slug items key off of) — delete and recreate if a project was truly misnamed at creation.';


--
-- Name: update_schedule_block(uuid, text, date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_schedule_block(p_schedule_block_id uuid, p_crew_name text DEFAULT NULL::text, p_start_date date DEFAULT NULL::date, p_end_date date DEFAULT NULL::date) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_work_order_id uuid;
  v_start_date date;
  v_end_date date;
  v_blocking_name text;
  v_blocking_ready_by date;
  v_blocked boolean;
  v_reason text;
begin
  select org_id, work_order_id, start_date, end_date
  into v_org_id, v_work_order_id, v_start_date, v_end_date
  from public.schedule_blocks where id = p_schedule_block_id;

  if v_org_id is null then
    raise exception 'schedule block not found or not accessible: %', p_schedule_block_id;
  end if;

  -- Split from the null check on purpose: PL/pgSQL does not guarantee
  -- short-circuit evaluation of OR, and assert_work_order_level() raises.
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'schedule block not found or not accessible: %', p_schedule_block_id;
  end if;

  v_start_date := coalesce(p_start_date, v_start_date);
  v_end_date := coalesce(p_end_date, v_end_date);

  select name, ready_by into v_blocking_name, v_blocking_ready_by
  from public.material_items
  where work_order_id = v_work_order_id and ready_by is not null
  order by ready_by desc
  limit 1;

  v_blocked := v_blocking_ready_by is not null and v_start_date < v_blocking_ready_by;
  v_reason := case when v_blocked
    then format('blocked on %s (ready %s)', v_blocking_name, v_blocking_ready_by)
    else null
  end;

  update public.schedule_blocks
  set crew_name = coalesce(p_crew_name, crew_name),
      start_date = v_start_date,
      end_date = v_end_date,
      blocked = v_blocked,
      blocked_reason = v_reason,
      updated_at = now()
  where id = p_schedule_block_id;
end;
$$;


ALTER FUNCTION public.update_schedule_block(p_schedule_block_id uuid, p_crew_name text, p_start_date date, p_end_date date) OWNER TO postgres;

--
-- Name: update_tracker_item(uuid, text, text, text, text, text, uuid, boolean, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_tracker_item(p_item_id uuid, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_type text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_priority text DEFAULT NULL::text, p_assignee_id uuid DEFAULT NULL::uuid, p_clear_assignee boolean DEFAULT false, p_position integer DEFAULT NULL::integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


ALTER FUNCTION public.update_tracker_item(p_item_id uuid, p_title text, p_description text, p_type text, p_status text, p_priority text, p_assignee_id uuid, p_clear_assignee boolean, p_position integer) OWNER TO postgres;

--
-- Name: FUNCTION update_tracker_item(p_item_id uuid, p_title text, p_description text, p_type text, p_status text, p_priority text, p_assignee_id uuid, p_clear_assignee boolean, p_position integer); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.update_tracker_item(p_item_id uuid, p_title text, p_description text, p_type text, p_status text, p_priority text, p_assignee_id uuid, p_clear_assignee boolean, p_position integer) IS 'Full-edit RPC: title/description/type/status/priority/assignee/position. p_clear_assignee is the explicit unassign path (coalesce alone cannot distinguish "not given" from "set to null").';


--
-- Name: update_tracker_project(uuid, text, text, text, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_tracker_project(p_project_id uuid, p_name text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_linked_org_id uuid DEFAULT NULL::uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


ALTER FUNCTION public.update_tracker_project(p_project_id uuid, p_name text, p_description text, p_status text, p_linked_org_id uuid) OWNER TO postgres;

--
-- Name: upsert_estimate_scope_line_items(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.upsert_estimate_scope_line_items(p_estimate_id uuid, p_items jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_status text;
  v_next_sort int;
  v_item jsonb;
begin
  select org_id, status into v_org_id, v_status
  from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  if v_status in ('signed', 'void') then
    raise exception 'estimate % is locked (status: %) — line items can only change before signing', p_estimate_id, v_status;
  end if;

  select coalesce(max(sort_order) + 1, 0) into v_next_sort
  from public.estimate_line_items where estimate_id = p_estimate_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    insert into public.estimate_line_items
      (org_id, estimate_id, scope_key, description, quantity, unit, unit_price, product_id, sort_order)
    values
      (v_org_id, p_estimate_id, v_item->>'scope_key', v_item->>'description',
       (v_item->>'quantity')::numeric, v_item->>'unit', 0, null, v_next_sort)
    on conflict (estimate_id, scope_key) where scope_key is not null
    do update set
      quantity = excluded.quantity,
      unit = excluded.unit,
      updated_at = now();

    v_next_sort := v_next_sort + 1;
  end loop;
end;
$$;


ALTER FUNCTION public.upsert_estimate_scope_line_items(p_estimate_id uuid, p_items jsonb) OWNER TO postgres;

--
-- Name: void_estimate(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.void_estimate(p_estimate_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  update public.estimates
  set status = 'void',
      updated_at = now()
  where id = p_estimate_id;
end;
$$;


ALTER FUNCTION public.void_estimate(p_estimate_id uuid) OWNER TO postgres;

--
-- Name: void_work_order(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.void_work_order(p_work_order_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_kind text;
  v_job_id uuid;
begin
  select org_id, kind, job_id
  into v_org_id, v_kind, v_job_id
  from public.work_orders where id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  -- The row named in the call is ALWAYS a deliberate void, so its marker is
  -- cleared. That is what makes the Monday/Tuesday case work: a trade voided
  -- by name on Monday carries no marker and survives Wednesday's restore.
  update public.work_orders
  set voided_at = coalesce(voided_at, now()),
      void_cascade_source_id = null,
      updated_at = now()
  where id = p_work_order_id;

  if v_kind = 'master' then
    -- `voided_at is null` is the whole trick: already-voided trades are not
    -- re-stamped and not marked, so the cascade owns only what it took.
    update public.work_orders
    set voided_at = now(),
        void_cascade_source_id = p_work_order_id,
        updated_at = now()
    where job_id = v_job_id
      and kind = 'trade'
      and voided_at is null;

    -- No active agreement may point at a voided work order. Voided here in the
    -- same transaction, with the prior status preserved so restore is exact.
    update public.work_order_agreements
    set void_cascade_prior_status = status,
        status = 'voided',
        voided_at = coalesce(voided_at, now()),
        void_reason = coalesce(void_reason, 'master work order voided'),
        void_cascade_source_id = p_work_order_id,
        updated_at = now()
    where work_order_id = p_work_order_id
      and status <> 'voided';
  end if;
end;
$$;


ALTER FUNCTION public.void_work_order(p_work_order_id uuid) OWNER TO postgres;

--
-- Name: wh_save_catalog_family(jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.wh_save_catalog_family(p_family jsonb, p_variations jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  v_org       uuid := '1084baa8-0355-4298-9b98-b876a7581173';
  v_role      text;
  v_family_id uuid;
  v_new_fam   boolean;
  v_systems   text[];
  v_ptype     text;
  v_section   text;
  v_type_id   uuid;
  v_elem      jsonb;
  v_var_id    uuid;
  v_prod_id   uuid;
  v_name      text;
  v_prod_name text;
  v_price     numeric(10,2);
  v_unit      text;
  v_cur_price numeric(10,2);
  v_cur_from  timestamptz;
  v_close_at  timestamptz;
  v_opened    boolean;
  v_status    text;
  v_colors    uuid[];
  v_cats      uuid[];
  v_results   jsonb := '[]'::jsonb;
begin
  -- ── Authorisation. SECURITY DEFINER bypasses RLS, so this IS the gate. ────
  v_role := public.my_wh_role();
  if v_role is null then
    raise exception 'Your account is not set up as a Material Matrix team member, so nothing was saved. Ask an admin to add you.'
      using errcode = '42501';
  end if;
  if v_role not in ('admin','assistant') then
    raise exception 'Your role (%) can view the catalog but not change it. Nothing was saved.', v_role
      using errcode = '42501';
  end if;
  if v_org not in (select public.my_org_ids()) then
    raise exception 'Your account is not a member of the Material Matrix organisation, so nothing was saved.'
      using errcode = '42501';
  end if;

  -- ── Validation, in the language of the screen ────────────────────────────
  if coalesce(btrim(p_family->>'name'), '') = '' then
    raise exception 'This product needs a name before it can be saved.' using errcode = '23514';
  end if;
  if p_variations is null or jsonb_typeof(p_variations) <> 'array'
     or jsonb_array_length(p_variations) = 0 then
    raise exception 'Add at least one option to "%" before saving. Every product needs one option, even if it is just "Standard".',
      btrim(p_family->>'name') using errcode = '23514';
  end if;

  v_systems := coalesce(array(select jsonb_array_elements_text(
                 case when jsonb_typeof(p_family->'compatible_systems') = 'array'
                      then p_family->'compatible_systems' else '[]'::jsonb end)), '{}'::text[]);
  v_ptype   := nullif(btrim(coalesce(p_family->>'product_type','')), '');
  v_section := nullif(btrim(coalesce(p_family->>'catalog_section','')), '');
  v_type_id := nullif(p_family->>'type_id', '')::uuid;

  -- ── Family ───────────────────────────────────────────────────────────────
  v_family_id := nullif(p_family->>'id', '')::uuid;
  v_new_fam   := v_family_id is null;

  begin
    if v_new_fam then
      insert into public.wh_product_families
        (org_id, name, slug, product_type, type_id, catalog_section,
         compatible_systems, image_url, status, display_order)
      values
        (v_org, btrim(p_family->>'name'), nullif(btrim(coalesce(p_family->>'slug','')),''),
         v_ptype, v_type_id, v_section, v_systems,
         nullif(btrim(coalesce(p_family->>'image_url','')),''),
         coalesce(nullif(p_family->>'status',''), 'live'),
         coalesce((p_family->>'display_order')::int, 0))
      returning id into v_family_id;
    else
      update public.wh_product_families
         set name               = btrim(p_family->>'name'),
             slug               = nullif(btrim(coalesce(p_family->>'slug','')),''),
             product_type       = v_ptype,
             type_id            = v_type_id,
             catalog_section    = v_section,
             compatible_systems = v_systems,
             image_url          = nullif(btrim(coalesce(p_family->>'image_url','')),''),
             status             = coalesce(nullif(p_family->>'status',''), 'live'),
             display_order      = coalesce((p_family->>'display_order')::int, 0)
       where id = v_family_id and org_id = v_org;
      if not found then
        raise exception 'That product no longer exists — someone may have deleted it. Reload the page and try again.'
          using errcode = 'P0002';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'There is already a product called "%". Use a different name.', btrim(p_family->>'name')
      using errcode = '23505';
  end;

  -- ── Each option: mirror row FIRST, then variation, then price/colors/cats ─
  for v_elem in select * from jsonb_array_elements(p_variations)
  loop
    v_var_id := nullif(v_elem->>'id', '')::uuid;
    v_name   := btrim(coalesce(v_elem->>'name', ''));
    if v_name = '' then
      raise exception 'One of the options on "%" has no name. Give every option a name (for example 4", or 26 GA Smooth).',
        btrim(p_family->>'name') using errcode = '23514';
    end if;

    v_price := nullif(btrim(coalesce(v_elem->>'price','')), '')::numeric(10,2);
    if v_price is not null and v_price < 0 then
      raise exception 'The price for "%" cannot be negative.', v_name using errcode = '23514';
    end if;
    v_unit   := nullif(btrim(coalesce(v_elem->>'price_unit','')), '');
    v_status := coalesce(nullif(v_elem->>'status',''), 'live');

    v_colors := coalesce(array(select jsonb_array_elements_text(
                  case when jsonb_typeof(v_elem->'color_ids') = 'array'
                       then v_elem->'color_ids' else '[]'::jsonb end))::uuid[], '{}'::uuid[]);
    v_cats   := coalesce(array(select jsonb_array_elements_text(
                  case when jsonb_typeof(v_elem->'category_ids') = 'array'
                       then v_elem->'category_ids' else '[]'::jsonb end))::uuid[], '{}'::uuid[]);

    -- existing mirror row, if this option already exists
    v_prod_id := null;
    if v_var_id is not null then
      select source_product_id into v_prod_id
        from public.wh_product_variations where id = v_var_id and org_id = v_org;
    end if;

    -- Storefront display name. The live catalog uses THREE different conventions
    -- ("Fascia Trim — 4\" Crinkle", "1 1/2\" Copper Screws", bare "Vented Soffit"),
    -- so this is never auto-derived for an existing product: renaming a live
    -- product silently is worse than an imperfect default. Explicit value wins,
    -- then the existing name, and only a brand-new row gets a derived default.
    v_prod_name := nullif(btrim(coalesce(v_elem->>'product_name','')), '');
    if v_prod_name is null and v_prod_id is not null then
      select name into v_prod_name from public.wh_products where id = v_prod_id;
    end if;
    if v_prod_name is null then
      v_prod_name := case
        when jsonb_array_length(p_variations) = 1
             and lower(v_name) in ('standard','default','one size')
        then btrim(p_family->>'name')
        else btrim(p_family->>'name') || ' — ' || v_name end;
    end if;

    -- ── Mirror row (wh_products) — still authoritative for the storefront ──
    if v_prod_id is null then
      insert into public.wh_products
        (org_id, name, sku, base_price, unit_type, gauge, finish, active, image_url,
         product_type, catalog_section, compatible_systems, display_order)
      values
        (v_org, v_prod_name, nullif(btrim(coalesce(v_elem->>'sku','')),''), v_price, v_unit,
         nullif(btrim(coalesce(v_elem->>'gauge','')),''), nullif(btrim(coalesce(v_elem->>'finish','')),''),
         (v_status = 'live'), nullif(btrim(coalesce(v_elem->>'image_url','')),''),
         v_ptype, v_section, v_systems, coalesce((v_elem->>'display_order')::int, 0))
      returning id into v_prod_id;
    else
      update public.wh_products
         set name = v_prod_name,
             sku = nullif(btrim(coalesce(v_elem->>'sku','')),''),
             base_price = v_price,
             unit_type = v_unit,
             gauge = nullif(btrim(coalesce(v_elem->>'gauge','')),''),
             finish = nullif(btrim(coalesce(v_elem->>'finish','')),''),
             active = (v_status = 'live'),
             image_url = nullif(btrim(coalesce(v_elem->>'image_url','')),''),
             product_type = v_ptype,
             catalog_section = v_section,
             compatible_systems = v_systems,
             display_order = coalesce((v_elem->>'display_order')::int, 0)
       where id = v_prod_id;
    end if;

    -- ── Variation row, bridged to the mirror ────────────────────────────────
    if v_var_id is null then
      insert into public.wh_product_variations
        (org_id, family_id, source_product_id, name, sku, price, price_unit,
         gauge, finish, status, display_order, image_url, type_id)
      values
        (v_org, v_family_id, v_prod_id, v_name, nullif(btrim(coalesce(v_elem->>'sku','')),''),
         v_price, v_unit, nullif(btrim(coalesce(v_elem->>'gauge','')),''),
         nullif(btrim(coalesce(v_elem->>'finish','')),''), v_status,
         coalesce((v_elem->>'display_order')::int, 0),
         nullif(btrim(coalesce(v_elem->>'image_url','')),''), v_type_id)
      returning id into v_var_id;
    else
      update public.wh_product_variations
         set family_id = v_family_id, source_product_id = v_prod_id, name = v_name,
             sku = nullif(btrim(coalesce(v_elem->>'sku','')),''),
             price = v_price, price_unit = v_unit,
             gauge = nullif(btrim(coalesce(v_elem->>'gauge','')),''),
             finish = nullif(btrim(coalesce(v_elem->>'finish','')),''),
             status = v_status,
             display_order = coalesce((v_elem->>'display_order')::int, 0),
             image_url = nullif(btrim(coalesce(v_elem->>'image_url','')),''),
             type_id = v_type_id
       where id = v_var_id and org_id = v_org;
      if not found then
        raise exception 'One of the options on "%" no longer exists. Reload the page and try again.',
          btrim(p_family->>'name') using errcode = 'P0002';
      end if;
    end if;

    -- ── Price ALWAYS goes through history. Never an in-place overwrite. ─────
    v_opened := false;
    if v_price is not null then
      select price, effective_from into v_cur_price, v_cur_from
        from public.wh_price_history
       where variation_id = v_var_id and effective_to is null;

      if v_cur_price is null then
        insert into public.wh_price_history
          (org_id, variation_id, price, price_unit, effective_from, changed_by, note)
        values (v_org, v_var_id, v_price, v_unit, now(), auth.uid(),
                coalesce(nullif(v_elem->>'price_note',''), 'First price set in the catalog editor'));
        v_opened := true;

      elsif v_cur_price is distinct from v_price then
        -- effective_to must be strictly > effective_from. now() is frozen for the
        -- whole transaction, so a period opened in THIS transaction would close at
        -- its own start instant and trip the sanity check. Nudge forward 1us.
        v_close_at := greatest(now(), v_cur_from + interval '1 microsecond');

        update public.wh_price_history
           set effective_to = v_close_at
         where variation_id = v_var_id and effective_to is null;

        -- New period starts exactly where the old one ended: no gap, no overlap
        -- ([a,c) then [c,d) do not intersect under tstzrange).
        insert into public.wh_price_history
          (org_id, variation_id, price, price_unit, effective_from, changed_by, note)
        values (v_org, v_var_id, v_price, v_unit, v_close_at, auth.uid(),
                coalesce(nullif(v_elem->>'price_note',''),
                         format('Price changed from %s to %s in the catalog editor', v_cur_price, v_price)));
        v_opened := true;
      end if;
    end if;

    -- ── Colours: BOTH models ───────────────────────────────────────────────
    delete from public.wh_variation_colors
     where variation_id = v_var_id and color_id <> all(v_colors);
    insert into public.wh_variation_colors (org_id, variation_id, color_id)
    select v_org, v_var_id, c from unnest(v_colors) c
    on conflict (variation_id, color_id) do nothing;

    delete from public.wh_product_colors
     where product_id = v_prod_id and color_id <> all(v_colors);
    insert into public.wh_product_colors (product_id, color_id)
    select v_prod_id, c from unnest(v_colors) c
    on conflict (product_id, color_id) do nothing;

    -- ── Category membership (storefront reads this) ────────────────────────
    delete from public.wh_category_products
     where product_id = v_prod_id and category_id <> all(v_cats);
    insert into public.wh_category_products (category_id, product_id)
    select c, v_prod_id from unnest(v_cats) c
    on conflict (category_id, product_id) do nothing;

    v_results := v_results || jsonb_build_object(
      'variation_id', v_var_id, 'product_id', v_prod_id, 'option_name', v_name,
      'storefront_name', v_prod_name, 'price_period_opened', v_opened);
  end loop;

  return jsonb_build_object(
    'family_id', v_family_id, 'created', v_new_fam,
    'option_count', jsonb_array_length(p_variations), 'options', v_results);
end
$$;


ALTER FUNCTION public.wh_save_catalog_family(p_family jsonb, p_variations jsonb) OWNER TO postgres;

--
-- Name: work_order_is_my_trade(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.work_order_is_my_trade(p_work_order_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1
    from public.work_orders w
    where w.id = p_work_order_id
      and w.kind = 'trade'
      and w.org_id in (select my_org_ids())
  );
$$;


ALTER FUNCTION public.work_order_is_my_trade(p_work_order_id uuid) OWNER TO postgres;

--
-- Name: FUNCTION work_order_is_my_trade(p_work_order_id uuid); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.work_order_is_my_trade(p_work_order_id uuid) IS 'A1.5. Ties a child row to its parent for the check_ins / material_items / schedule_blocks / production_packets write policies: the referenced work order must be in one of my orgs AND be a trade. Closes the A1.4 finding that those policies constrained org_id and left work_order_id free.';


--
-- Name: wh_categories_backup_20260817; Type: TABLE; Schema: archive; Owner: postgres
--

CREATE TABLE archive.wh_categories_backup_20260817 (
    id uuid,
    org_id uuid,
    system_id uuid,
    stage_id uuid,
    name text,
    slug text,
    microcopy text,
    image_url text,
    required boolean,
    badge text,
    skip_label text,
    display_order integer,
    active boolean,
    catalog_section text,
    created_at timestamp with time zone
);


ALTER TABLE archive.wh_categories_backup_20260817 OWNER TO postgres;

--
-- Name: wh_categories_backup_20260820; Type: TABLE; Schema: archive; Owner: postgres
--

CREATE TABLE archive.wh_categories_backup_20260820 (
    id uuid,
    org_id uuid,
    system_id uuid,
    stage_id uuid,
    name text,
    slug text,
    microcopy text,
    image_url text,
    required boolean,
    badge text,
    skip_label text,
    display_order integer,
    active boolean,
    catalog_section text,
    created_at timestamp with time zone
);


ALTER TABLE archive.wh_categories_backup_20260820 OWNER TO postgres;

--
-- Name: wh_category_products_backup_20260817; Type: TABLE; Schema: archive; Owner: postgres
--

CREATE TABLE archive.wh_category_products_backup_20260817 (
    category_id uuid,
    product_id uuid
);


ALTER TABLE archive.wh_category_products_backup_20260817 OWNER TO postgres;

--
-- Name: wh_category_products_backup_20260819; Type: TABLE; Schema: archive; Owner: postgres
--

CREATE TABLE archive.wh_category_products_backup_20260819 (
    category_id uuid,
    product_id uuid
);


ALTER TABLE archive.wh_category_products_backup_20260819 OWNER TO postgres;

--
-- Name: wh_colors_backup_20260814; Type: TABLE; Schema: archive; Owner: postgres
--

CREATE TABLE archive.wh_colors_backup_20260814 (
    id uuid,
    org_id uuid,
    name text,
    hex_code text,
    swatch_image_url text,
    active boolean,
    display_order integer,
    created_at timestamp with time zone
);


ALTER TABLE archive.wh_colors_backup_20260814 OWNER TO postgres;

--
-- Name: TABLE wh_colors_backup_20260814; Type: COMMENT; Schema: archive; Owner: postgres
--

COMMENT ON TABLE archive.wh_colors_backup_20260814 IS 'Pre-normalisation snapshot of wh_colors taken 2026-08-14. Retained because 491/831 product-colour mappings changed during normalisation; this is the only record of the prior state.';


--
-- Name: wh_colors_backup_20260818; Type: TABLE; Schema: archive; Owner: postgres
--

CREATE TABLE archive.wh_colors_backup_20260818 (
    id uuid,
    org_id uuid,
    name text,
    hex_code text,
    swatch_image_url text,
    active boolean,
    display_order integer,
    created_at timestamp with time zone,
    color_family text,
    available_finishes text[]
);


ALTER TABLE archive.wh_colors_backup_20260818 OWNER TO postgres;

--
-- Name: wh_price_history_backup_20260819; Type: TABLE; Schema: archive; Owner: postgres
--

CREATE TABLE archive.wh_price_history_backup_20260819 (
    id uuid,
    org_id uuid,
    variation_id uuid,
    price numeric(10,2),
    price_unit text,
    effective_from timestamp with time zone,
    effective_to timestamp with time zone,
    changed_by uuid,
    note text,
    created_at timestamp with time zone
);


ALTER TABLE archive.wh_price_history_backup_20260819 OWNER TO postgres;

--
-- Name: wh_product_colors_backup_20260814; Type: TABLE; Schema: archive; Owner: postgres
--

CREATE TABLE archive.wh_product_colors_backup_20260814 (
    product_id uuid,
    color_id uuid,
    price_modifier numeric(10,2)
);


ALTER TABLE archive.wh_product_colors_backup_20260814 OWNER TO postgres;

--
-- Name: TABLE wh_product_colors_backup_20260814; Type: COMMENT; Schema: archive; Owner: postgres
--

COMMENT ON TABLE archive.wh_product_colors_backup_20260814 IS 'Pre-normalisation snapshot of wh_product_colors taken 2026-08-14. 491 of 831 pairs differ from live.';


--
-- Name: wh_product_colors_backup_20260817; Type: TABLE; Schema: archive; Owner: postgres
--

CREATE TABLE archive.wh_product_colors_backup_20260817 (
    product_id uuid,
    color_id uuid,
    price_modifier numeric(10,2)
);


ALTER TABLE archive.wh_product_colors_backup_20260817 OWNER TO postgres;

--
-- Name: wh_product_colors_backup_20260818; Type: TABLE; Schema: archive; Owner: postgres
--

CREATE TABLE archive.wh_product_colors_backup_20260818 (
    product_id uuid,
    color_id uuid,
    price_modifier numeric(10,2)
);


ALTER TABLE archive.wh_product_colors_backup_20260818 OWNER TO postgres;

--
-- Name: wh_product_colors_backup_20260819; Type: TABLE; Schema: archive; Owner: postgres
--

CREATE TABLE archive.wh_product_colors_backup_20260819 (
    product_id uuid,
    color_id uuid,
    price_modifier numeric(10,2)
);


ALTER TABLE archive.wh_product_colors_backup_20260819 OWNER TO postgres;

--
-- Name: wh_product_families_backup_20260818; Type: TABLE; Schema: archive; Owner: postgres
--

CREATE TABLE archive.wh_product_families_backup_20260818 (
    id uuid,
    org_id uuid,
    name text,
    slug text,
    product_type text,
    catalog_section text,
    compatible_systems text[],
    image_url text,
    display_order integer,
    status text,
    member_conflicts jsonb,
    created_at timestamp with time zone
);


ALTER TABLE archive.wh_product_families_backup_20260818 OWNER TO postgres;

--
-- Name: wh_product_families_backup_20260819; Type: TABLE; Schema: archive; Owner: postgres
--

CREATE TABLE archive.wh_product_families_backup_20260819 (
    id uuid,
    org_id uuid,
    name text,
    slug text,
    product_type text,
    catalog_section text,
    compatible_systems text[],
    image_url text,
    display_order integer,
    status text,
    member_conflicts jsonb,
    created_at timestamp with time zone,
    type_id uuid
);


ALTER TABLE archive.wh_product_families_backup_20260819 OWNER TO postgres;

--
-- Name: wh_product_variations_backup_20260818; Type: TABLE; Schema: archive; Owner: postgres
--

CREATE TABLE archive.wh_product_variations_backup_20260818 (
    id uuid,
    org_id uuid,
    family_id uuid,
    source_product_id uuid,
    name text,
    sku text,
    price numeric(10,2),
    price_unit text,
    gauge text,
    finish text,
    status text,
    display_order integer,
    created_at timestamp with time zone
);


ALTER TABLE archive.wh_product_variations_backup_20260818 OWNER TO postgres;

--
-- Name: wh_product_variations_backup_20260819; Type: TABLE; Schema: archive; Owner: postgres
--

CREATE TABLE archive.wh_product_variations_backup_20260819 (
    id uuid,
    org_id uuid,
    family_id uuid,
    source_product_id uuid,
    name text,
    sku text,
    price numeric(10,2),
    price_unit text,
    gauge text,
    finish text,
    status text,
    display_order integer,
    created_at timestamp with time zone,
    type_id uuid
);


ALTER TABLE archive.wh_product_variations_backup_20260819 OWNER TO postgres;

--
-- Name: wh_products_backup_20260817; Type: TABLE; Schema: archive; Owner: postgres
--

CREATE TABLE archive.wh_products_backup_20260817 (
    id uuid,
    org_id uuid,
    name text,
    sku text,
    description text,
    gauge text,
    finish text,
    image_url text,
    unit_type text,
    unit_size text,
    base_price numeric(10,2),
    active boolean,
    display_order integer,
    product_type text,
    catalog_section text,
    compatible_systems text[],
    created_at timestamp with time zone
);


ALTER TABLE archive.wh_products_backup_20260817 OWNER TO postgres;

--
-- Name: wh_products_backup_20260818; Type: TABLE; Schema: archive; Owner: postgres
--

CREATE TABLE archive.wh_products_backup_20260818 (
    id uuid,
    org_id uuid,
    name text,
    sku text,
    description text,
    gauge text,
    finish text,
    image_url text,
    unit_type text,
    unit_size text,
    base_price numeric(10,2),
    active boolean,
    display_order integer,
    product_type text,
    catalog_section text,
    compatible_systems text[],
    created_at timestamp with time zone
);


ALTER TABLE archive.wh_products_backup_20260818 OWNER TO postgres;

--
-- Name: wh_products_backup_20260819; Type: TABLE; Schema: archive; Owner: postgres
--

CREATE TABLE archive.wh_products_backup_20260819 (
    id uuid,
    org_id uuid,
    name text,
    sku text,
    description text,
    gauge text,
    finish text,
    image_url text,
    unit_type text,
    unit_size text,
    base_price numeric(10,2),
    active boolean,
    display_order integer,
    product_type text,
    catalog_section text,
    compatible_systems text[],
    created_at timestamp with time zone
);


ALTER TABLE archive.wh_products_backup_20260819 OWNER TO postgres;

--
-- Name: wh_systems_backup_20260820; Type: TABLE; Schema: archive; Owner: postgres
--

CREATE TABLE archive.wh_systems_backup_20260820 (
    id uuid,
    org_id uuid,
    name text,
    slug text,
    hero_image_url text,
    tagline text,
    description text,
    display_order integer,
    active boolean,
    created_at timestamp with time zone
);


ALTER TABLE archive.wh_systems_backup_20260820 OWNER TO postgres;

--
-- Name: wh_variation_colors_backup_20260819; Type: TABLE; Schema: archive; Owner: postgres
--

CREATE TABLE archive.wh_variation_colors_backup_20260819 (
    id uuid,
    org_id uuid,
    variation_id uuid,
    color_id uuid,
    price_modifier numeric,
    created_at timestamp with time zone
);


ALTER TABLE archive.wh_variation_colors_backup_20260819 OWNER TO postgres;

--
-- Name: audit_leads; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.audit_leads (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    name text,
    email text NOT NULL,
    company text,
    trade text,
    score integer,
    risk_level text,
    monthly_leak integer,
    crew_size integer,
    top_leaks text[],
    answers jsonb,
    source text DEFAULT 'audit.structtek.com'::text,
    contacted boolean DEFAULT false,
    notes text,
    org_id uuid
);


ALTER TABLE public.audit_leads OWNER TO postgres;

--
-- Name: audits; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.audits (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    prospect_id uuid,
    answers jsonb,
    area_scores jsonb,
    ranked_bottlenecks jsonb,
    recommended_tier text,
    total_pain_score integer
);


ALTER TABLE public.audits OWNER TO postgres;

--
-- Name: client_roadmaps; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.client_roadmaps (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    token text DEFAULT encode(extensions.gen_random_bytes(9), 'hex'::text) NOT NULL,
    client_name text NOT NULL,
    company text NOT NULL,
    trade text,
    crew_size integer,
    score integer,
    risk_level text,
    revenue_leak_monthly integer,
    levels jsonb DEFAULT '[]'::jsonb NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    lead_id uuid,
    history jsonb DEFAULT '[]'::jsonb NOT NULL,
    org_id uuid
);


ALTER TABLE public.client_roadmaps OWNER TO postgres;

--
-- Name: deal_activity; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.deal_activity (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    deal_id uuid NOT NULL,
    action text NOT NULL,
    from_value text,
    to_value text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    org_id uuid,
    actor_id uuid
);


ALTER TABLE public.deal_activity OWNER TO postgres;

--
-- Name: deal_notes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.deal_notes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    deal_id uuid NOT NULL,
    content text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    org_id uuid,
    created_by uuid
);


ALTER TABLE public.deal_notes OWNER TO postgres;

--
-- Name: engagement_checkins; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.engagement_checkins (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    engagement_id uuid NOT NULL,
    level_id uuid,
    org_id uuid,
    title text NOT NULL,
    scheduled_at timestamp with time zone NOT NULL,
    status text DEFAULT 'scheduled'::text NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT engagement_checkins_status_check CHECK ((status = ANY (ARRAY['scheduled'::text, 'done'::text, 'missed'::text, 'rescheduled'::text])))
);


ALTER TABLE public.engagement_checkins OWNER TO postgres;

--
-- Name: engagement_levels; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.engagement_levels (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    engagement_id uuid NOT NULL,
    org_id uuid,
    level_no integer NOT NULL,
    title text NOT NULL,
    why text,
    area text,
    sort_order integer DEFAULT 0 NOT NULL,
    depends_on_level_id uuid,
    planned_start date,
    planned_end date,
    actual_start date,
    actual_end date,
    status text DEFAULT 'not_started'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT engagement_levels_status_check CHECK ((status = ANY (ARRAY['not_started'::text, 'in_progress'::text, 'blocked'::text, 'complete'::text])))
);


ALTER TABLE public.engagement_levels OWNER TO postgres;

--
-- Name: engagement_milestones; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.engagement_milestones (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    level_id uuid NOT NULL,
    org_id uuid,
    owner text NOT NULL,
    body text NOT NULL,
    is_win_condition boolean DEFAULT false NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    completed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT engagement_milestones_owner_check CHECK ((owner = ANY (ARRAY['jacob'::text, 'client'::text]))),
    CONSTRAINT engagement_milestones_status_check CHECK ((status = ANY (ARRAY['open'::text, 'complete'::text])))
);


ALTER TABLE public.engagement_milestones OWNER TO postgres;

--
-- Name: engagements; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.engagements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    deal_id uuid NOT NULL,
    roadmap_id uuid,
    org_id uuid,
    start_date date,
    target_end_date date,
    status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT engagements_status_check CHECK ((status = ANY (ARRAY['active'::text, 'paused'::text, 'complete'::text])))
);


ALTER TABLE public.engagements OWNER TO postgres;

--
-- Name: estimate_line_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.estimate_line_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    estimate_id uuid NOT NULL,
    product_id uuid,
    description text NOT NULL,
    quantity numeric DEFAULT 1 NOT NULL,
    unit_price numeric DEFAULT 0 NOT NULL,
    line_total numeric GENERATED ALWAYS AS ((quantity * unit_price)) STORED,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    unit text,
    scope_key text
);


ALTER TABLE public.estimate_line_items OWNER TO postgres;

--
-- Name: COLUMN estimate_line_items.product_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.estimate_line_items.product_id IS 'Reserved for the future product catalog (SCOPE.md §12B) — no FK yet, no products table exists. Nullable: lines are free-text-only until then.';


--
-- Name: COLUMN estimate_line_items.unit; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.estimate_line_items.unit IS 'Free text (ea/sq/lf/hr/...), no enum lock-in — same reasoning as product_id staying unconstrained until a real catalog exists.';


--
-- Name: COLUMN estimate_line_items.scope_key; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.estimate_line_items.scope_key IS 'Tags a line item as generated by Guided mode from this site-visit-scope checklist key. Null for manual/free-typed lines. Never set by the UI directly — only upsert_estimate_scope_line_items() writes it.';


--
-- Name: estimate_number_counters; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.estimate_number_counters (
    org_id uuid NOT NULL,
    next_number integer DEFAULT 1 NOT NULL
);


ALTER TABLE public.estimate_number_counters OWNER TO postgres;

--
-- Name: TABLE estimate_number_counters; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.estimate_number_counters IS 'Per-org counter for human-readable estimate_number ("EST-1042"). Claimed atomically by create_estimate_from_deal() via INSERT ... ON CONFLICT DO UPDATE (row lock, no race). Never read/written directly by app code.';


--
-- Name: follow_ups; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.follow_ups (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    deal_id uuid NOT NULL,
    send_at timestamp with time zone NOT NULL,
    subject text NOT NULL,
    body text NOT NULL,
    to_email text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    sent_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    org_id uuid,
    CONSTRAINT follow_ups_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'sent'::text, 'cancelled'::text])))
);


ALTER TABLE public.follow_ups OWNER TO postgres;

--
-- Name: jobs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    deal_id uuid NOT NULL,
    estimate_id uuid NOT NULL,
    service_address_street text,
    service_address_city text,
    service_address_state text,
    service_address_zip text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.jobs OWNER TO postgres;

--
-- Name: TABLE jobs; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.jobs IS 'Job container (directive D1): one service address, one signed estimate. Parent of the master work order and its trade work orders.';


--
-- Name: lead_activity; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lead_activity (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    lead_id uuid NOT NULL,
    actor_id uuid NOT NULL,
    action public.lead_activity_action NOT NULL,
    from_value text,
    to_value text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.lead_activity OWNER TO postgres;

--
-- Name: lead_appointments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lead_appointments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    lead_id uuid NOT NULL,
    title text,
    scheduled_at timestamp with time zone NOT NULL,
    duration_minutes integer DEFAULT 60 NOT NULL,
    status text DEFAULT 'scheduled'::text NOT NULL,
    notes text,
    completed_at timestamp with time zone,
    cancelled_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT lead_appointments_status_check CHECK ((status = ANY (ARRAY['scheduled'::text, 'completed'::text, 'cancelled'::text, 'no_show'::text])))
);


ALTER TABLE public.lead_appointments OWNER TO postgres;

--
-- Name: lead_notes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lead_notes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    lead_id uuid NOT NULL,
    author_id uuid NOT NULL,
    content text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.lead_notes OWNER TO postgres;

--
-- Name: leads; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.leads (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    first_name text,
    last_name text,
    name text NOT NULL,
    company_name text,
    phone text,
    cell_phone text,
    secondary_phone text,
    email text,
    street_address text,
    city text,
    state text,
    zip text,
    service_street_address text,
    service_city text,
    service_state text,
    service_zip text,
    source public.lead_source DEFAULT 'manual'::public.lead_source NOT NULL,
    referral_name text,
    stage public.lead_stage DEFAULT 'lead_captured'::public.lead_stage NOT NULL,
    status public.lead_status DEFAULT 'active'::public.lead_status NOT NULL,
    value numeric(12,2),
    owner_id uuid,
    claim_locked boolean DEFAULT false NOT NULL,
    lost_reason text,
    intake_checklist jsonb DEFAULT '{}'::jsonb NOT NULL,
    site_visit_complete_at timestamp with time zone,
    scope_ordered_at timestamp with time zone,
    quote_presented_at timestamp with time zone,
    proposal_sent_at timestamp with time zone,
    last_contacted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    closed_at timestamp with time zone
);


ALTER TABLE public.leads OWNER TO postgres;

--
-- Name: material_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.material_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    work_order_id uuid NOT NULL,
    name text NOT NULL,
    quantity numeric DEFAULT 1 NOT NULL,
    ready_by date,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.material_items OWNER TO postgres;

--
-- Name: migration_bmr_activity_raw; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.migration_bmr_activity_raw (
    old_id uuid NOT NULL,
    payload jsonb NOT NULL,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.migration_bmr_activity_raw OWNER TO postgres;

--
-- Name: TABLE migration_bmr_activity_raw; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.migration_bmr_activity_raw IS 'BMR migration staging: raw export of the old app''s public.lead_activity. Scaffolding — drop after the migration is verified.';


--
-- Name: migration_bmr_id_map; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.migration_bmr_id_map (
    entity text NOT NULL,
    old_id uuid NOT NULL,
    new_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT migration_bmr_id_map_entity_check CHECK ((entity = ANY (ARRAY['lead'::text, 'note'::text, 'activity'::text, 'user'::text])))
);


ALTER TABLE public.migration_bmr_id_map OWNER TO postgres;

--
-- Name: TABLE migration_bmr_id_map; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.migration_bmr_id_map IS 'BMR migration staging: old id -> new id per entity, the provenance/idempotency backbone for docs/migration/bmr_transform.sql. Scaffolding — drop after the migration is verified.';


--
-- Name: migration_bmr_leads_raw; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.migration_bmr_leads_raw (
    old_id uuid NOT NULL,
    payload jsonb NOT NULL,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.migration_bmr_leads_raw OWNER TO postgres;

--
-- Name: TABLE migration_bmr_leads_raw; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.migration_bmr_leads_raw IS 'BMR migration staging: raw export of the old app''s public.leads, one row per record, keyed by old id. Scaffolding — drop after the migration is verified.';


--
-- Name: migration_bmr_notes_raw; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.migration_bmr_notes_raw (
    old_id uuid NOT NULL,
    payload jsonb NOT NULL,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.migration_bmr_notes_raw OWNER TO postgres;

--
-- Name: TABLE migration_bmr_notes_raw; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.migration_bmr_notes_raw IS 'BMR migration staging: raw export of the old app''s public.lead_notes. Scaffolding — drop after the migration is verified.';


--
-- Name: migration_bmr_users_raw; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.migration_bmr_users_raw (
    old_id uuid NOT NULL,
    payload jsonb NOT NULL,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.migration_bmr_users_raw OWNER TO postgres;

--
-- Name: TABLE migration_bmr_users_raw; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.migration_bmr_users_raw IS 'BMR migration staging: raw export of the old app''s users/profiles. Used ONLY to build migration_bmr_id_map''s user rows (email match against public.profiles) — never inserted as a target row itself. Scaffolding — drop after the migration is verified.';


--
-- Name: org_invites; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.org_invites (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    token text DEFAULT encode(extensions.gen_random_bytes(12), 'hex'::text) NOT NULL,
    org_id uuid NOT NULL,
    email text NOT NULL,
    role text DEFAULT 'member'::text NOT NULL,
    accepted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT org_invites_role_check CHECK ((role = ANY (ARRAY['owner'::text, 'member'::text])))
);


ALTER TABLE public.org_invites OWNER TO postgres;

--
-- Name: org_invoices; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.org_invoices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    label text NOT NULL,
    amount integer NOT NULL,
    kind text DEFAULT 'invoice'::text NOT NULL,
    status text DEFAULT 'due'::text NOT NULL,
    due_date date,
    paid_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT org_invoices_kind_check CHECK ((kind = ANY (ARRAY['invoice'::text, 'upcoming'::text]))),
    CONSTRAINT org_invoices_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'due'::text, 'paid'::text, 'void'::text])))
);


ALTER TABLE public.org_invoices OWNER TO postgres;

--
-- Name: org_members; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.org_members (
    org_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role text DEFAULT 'member'::text NOT NULL,
    full_name text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    permissions jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT org_members_role_check CHECK ((role = ANY (ARRAY['owner'::text, 'admin'::text, 'office'::text, 'field'::text, 'client_portal_viewer'::text, 'agency_admin'::text, 'member'::text])))
);


ALTER TABLE public.org_members OWNER TO postgres;

--
-- Name: COLUMN org_members.role; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.org_members.role IS 'owner: full tenant, dashboard, financials. admin: delegated admin (settings, users) short of owner. office: office/coordinator tier — pipeline, coordination, estimating. field: field/crew tier — Field module only, no $ or pipeline. client_portal_viewer: read-only delivery view + confirm own items. agency_admin: StructTech operator membership inside a client org (internal tenant type only). member: legacy value, preserved for existing rows/features.';


--
-- Name: COLUMN org_members.permissions; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.org_members.permissions IS 'Capability overrides for member-tier users. Keys: view_financials, view_estimates, create_estimates, edit_leads, add_notes, schedule, manage_users, view_field. Absent key = role default (see has_capability()). Ignored for manager-tier roles (owner/admin/agency_admin) — they are unrestricted regardless of this column.';


--
-- Name: org_systems; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.org_systems (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    name text NOT NULL,
    description text,
    status text DEFAULT 'in_build'::text NOT NULL,
    url text,
    sort integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT org_systems_status_check CHECK ((status = ANY (ARRAY['planned'::text, 'in_build'::text, 'training'::text, 'live'::text, 'maintenance'::text])))
);


ALTER TABLE public.org_systems OWNER TO postgres;

--
-- Name: pipeline_invites; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pipeline_invites (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    token text DEFAULT encode(extensions.gen_random_bytes(12), 'hex'::text) NOT NULL,
    email text NOT NULL,
    role public.pipeline_user_role DEFAULT 'salesman'::public.pipeline_user_role NOT NULL,
    created_by uuid,
    accepted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.pipeline_invites OWNER TO postgres;

--
-- Name: profiles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    full_name text NOT NULL,
    email text NOT NULL,
    role public.pipeline_user_role DEFAULT 'salesman'::public.pipeline_user_role NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.profiles OWNER TO postgres;

--
-- Name: proposals; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.proposals (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    prospect_id uuid,
    audit_id uuid,
    tier text,
    price text,
    custom_notes text,
    status text DEFAULT 'draft'::text
);


ALTER TABLE public.proposals OWNER TO postgres;

--
-- Name: prospects; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.prospects (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    company_name text NOT NULL,
    owner_name text,
    trade_type text,
    employee_count integer,
    city text,
    state text,
    email text,
    phone text,
    website text,
    owner_operated boolean DEFAULT false,
    stage text DEFAULT 'cold'::text,
    icp_score integer,
    icp_verdict text,
    leak_signals text[],
    notes text,
    business_type text,
    serves_contractors boolean DEFAULT false
);


ALTER TABLE public.prospects OWNER TO postgres;

--
-- Name: roadmap_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.roadmap_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    phase text NOT NULL,
    section text NOT NULL,
    feature text NOT NULL,
    status text DEFAULT 'planned'::text NOT NULL,
    notes text,
    sort_order integer DEFAULT 0 NOT NULL,
    updated_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    project_id uuid NOT NULL,
    CONSTRAINT roadmap_items_phase_check CHECK ((phase = ANY (ARRAY['now'::text, 'A'::text, 'B'::text, 'C'::text, 'D'::text, 'later'::text]))),
    CONSTRAINT roadmap_items_status_check CHECK ((status = ANY (ARRAY['shipped'::text, 'in_progress'::text, 'planned'::text])))
);


ALTER TABLE public.roadmap_items OWNER TO postgres;

--
-- Name: TABLE roadmap_items; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.roadmap_items IS 'In-app Build Tracker: one row per feature/phase cell on the roadmap matrix. StructTech-internal (module entitlement gates the route) — never licensed to contractor tenants.';


--
-- Name: roadmap_projects; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.roadmap_projects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    key text NOT NULL,
    name text NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.roadmap_projects OWNER TO postgres;

--
-- Name: TABLE roadmap_projects; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.roadmap_projects IS 'Build Tracker: one row per tracked build (StructTech OS, Material Matrix, ...). Config-driven — adding a project is an insert, not a migration. Same org/entitlement boundary as roadmap_items (module_key=''build'', StructTech-internal).';


--
-- Name: schedule_blocks; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.schedule_blocks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    work_order_id uuid NOT NULL,
    crew_name text NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    blocked boolean DEFAULT false NOT NULL,
    blocked_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT schedule_blocks_check CHECK ((end_date >= start_date))
);


ALTER TABLE public.schedule_blocks OWNER TO postgres;

--
-- Name: COLUMN schedule_blocks.blocked; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.schedule_blocks.blocked IS 'Computed at write time only (start_date vs. latest material ready_by) — not recomputed when material_items change later. See migration header note 2.';


--
-- Name: signatures; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.signatures (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    estimate_id uuid NOT NULL,
    signer_name text NOT NULL,
    signer_role text NOT NULL,
    signature_data text NOT NULL,
    pdf_url text,
    sign_token text,
    signed_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.signatures OWNER TO postgres;

--
-- Name: COLUMN signatures.sign_token; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.signatures.sign_token IS 'Reserved for future remote signing — no anon/public path uses it this phase. sign_estimate() is same-session, authenticated-caller-only.';


--
-- Name: staff_invites; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.staff_invites (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    token text DEFAULT encode(extensions.gen_random_bytes(12), 'hex'::text) NOT NULL,
    email text NOT NULL,
    role text DEFAULT 'admin'::text NOT NULL,
    created_by uuid,
    accepted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT staff_invites_role_check CHECK ((role = ANY (ARRAY['admin'::text])))
);


ALTER TABLE public.staff_invites OWNER TO postgres;

--
-- Name: staff_users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.staff_users (
    user_id uuid NOT NULL,
    role text DEFAULT 'admin'::text NOT NULL,
    full_name text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    email text,
    CONSTRAINT staff_users_role_check CHECK ((role = ANY (ARRAY['admin'::text])))
);


ALTER TABLE public.staff_users OWNER TO postgres;

--
-- Name: structtech_state; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.structtech_state (
    id text DEFAULT 'jacob'::text NOT NULL,
    task_state jsonb DEFAULT '{}'::jsonb,
    income_entries jsonb DEFAULT '[]'::jsonb,
    current_week integer DEFAULT 1,
    updated_at timestamp with time zone DEFAULT now(),
    os_data jsonb DEFAULT '{}'::jsonb
);


ALTER TABLE public.structtech_state OWNER TO postgres;

--
-- Name: tenant_modules; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tenant_modules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    module_key text NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tenant_modules_module_key_check CHECK ((module_key = ANY (ARRAY['crm'::text, 'estimating'::text, 'coordination'::text, 'field'::text, 'delivery'::text, 'scan'::text, 'roadmap'::text, 'tracker'::text, 'build'::text])))
);


ALTER TABLE public.tenant_modules OWNER TO postgres;

--
-- Name: TABLE tenant_modules; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.tenant_modules IS 'Entitlement layer: which modules an org is licensed for. Nav and route guards render from this.';


--
-- Name: tg_agenda_card; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tg_agenda_card (
    id bigint NOT NULL,
    created_by bigint,
    chat_id bigint,
    payload jsonb NOT NULL,
    delivered_to jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.tg_agenda_card OWNER TO postgres;

--
-- Name: TABLE tg_agenda_card; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.tg_agenda_card IS 'History of built cards. payload is the exact CardData used, so any card can be re-rendered or reused as a template.';


--
-- Name: tg_agenda_card_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.tg_agenda_card_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tg_agenda_card_id_seq OWNER TO postgres;

--
-- Name: tg_agenda_card_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.tg_agenda_card_id_seq OWNED BY public.tg_agenda_card.id;


--
-- Name: tg_agenda_contact; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tg_agenda_contact (
    id bigint NOT NULL,
    tg_user_id bigint,
    username text,
    label text NOT NULL,
    active boolean DEFAULT false NOT NULL,
    added_by bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.tg_agenda_contact OWNER TO postgres;

--
-- Name: TABLE tg_agenda_contact; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.tg_agenda_contact IS 'People who can be DMed an approved card. Telegram forbids a bot messaging anyone who has not started it, so rows are created when a person runs /start — they cannot be added by handle. active is flipped on by a sender via /contacts.';


--
-- Name: tg_agenda_contact_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.tg_agenda_contact_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tg_agenda_contact_id_seq OWNER TO postgres;

--
-- Name: tg_agenda_contact_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.tg_agenda_contact_id_seq OWNED BY public.tg_agenda_contact.id;


--
-- Name: tg_agenda_group; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tg_agenda_group (
    chat_id bigint NOT NULL,
    title text,
    active boolean DEFAULT false NOT NULL,
    added_by bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.tg_agenda_group OWNER TO postgres;

--
-- Name: TABLE tg_agenda_group; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.tg_agenda_group IS 'Group chats the bot posts approved cards into. Populated when the bot is added to a group.';


--
-- Name: COLUMN tg_agenda_group.active; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.tg_agenda_group.active IS 'Off until a sender enables it via /groups. Anyone can add the bot to a group; that must not be enough to start receiving cards.';


--
-- Name: tg_agenda_sender; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tg_agenda_sender (
    tg_user_id bigint NOT NULL,
    label text,
    added_by bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    owner boolean DEFAULT false NOT NULL
);


ALTER TABLE public.tg_agenda_sender OWNER TO postgres;

--
-- Name: TABLE tg_agenda_sender; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.tg_agenda_sender IS 'Send allowlist. Anyone may build and download a card; only these Telegram user ids may push one to the group or to contacts. Seeded with the first user to run /claim while the table is empty.';


--
-- Name: COLUMN tg_agenda_sender.owner; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.tg_agenda_sender.owner IS 'True for the first person to /claim. Only the owner may remove other senders.';


--
-- Name: tg_agenda_session; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tg_agenda_session (
    chat_id bigint NOT NULL,
    tg_user_id bigint NOT NULL,
    step text DEFAULT 'idle'::text NOT NULL,
    draft jsonb DEFAULT '{}'::jsonb NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.tg_agenda_session OWNER TO postgres;

--
-- Name: TABLE tg_agenda_session; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.tg_agenda_session IS 'One in-flight agenda conversation per (chat, person). Keyed by both so two people building in the same group chat cannot overwrite each other, and so a callback can only ever act on its own author''s draft.';


--
-- Name: tg_agenda_update; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tg_agenda_update (
    update_id bigint NOT NULL,
    seen_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.tg_agenda_update OWNER TO postgres;

--
-- Name: TABLE tg_agenda_update; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.tg_agenda_update IS 'Idempotency guard. Telegram retries a webhook until it gets a 200, so every update_id is claimed once before any side effect runs.';


--
-- Name: ticket_messages; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ticket_messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ticket_id uuid NOT NULL,
    author_name text NOT NULL,
    is_structtech boolean DEFAULT false NOT NULL,
    content text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.ticket_messages OWNER TO postgres;

--
-- Name: tickets; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tickets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    title text NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    priority text DEFAULT 'normal'::text NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tickets_priority_check CHECK ((priority = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text]))),
    CONSTRAINT tickets_status_check CHECK ((status = ANY (ARRAY['open'::text, 'in_progress'::text, 'waiting_client'::text, 'resolved'::text, 'closed'::text])))
);


ALTER TABLE public.tickets OWNER TO postgres;

--
-- Name: wh_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wh_categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    system_id uuid NOT NULL,
    stage_id uuid,
    name text NOT NULL,
    slug text NOT NULL,
    microcopy text,
    image_url text,
    required boolean DEFAULT false,
    badge text DEFAULT 'OPTIONAL'::text,
    skip_label text,
    display_order integer DEFAULT 0,
    active boolean DEFAULT true,
    catalog_section text,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.wh_categories OWNER TO postgres;

--
-- Name: wh_category_products; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wh_category_products (
    category_id uuid NOT NULL,
    product_id uuid NOT NULL
);


ALTER TABLE public.wh_category_products OWNER TO postgres;

--
-- Name: wh_colors; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wh_colors (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    name text NOT NULL,
    hex_code text,
    swatch_image_url text,
    active boolean DEFAULT true,
    display_order integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    color_family text,
    available_finishes text[] DEFAULT ARRAY['smooth'::text] NOT NULL,
    CONSTRAINT wh_colors_available_finishes_chk CHECK (((available_finishes <@ ARRAY['smooth'::text, 'textured'::text]) AND (array_length(available_finishes, 1) >= 1)))
);


ALTER TABLE public.wh_colors OWNER TO postgres;

--
-- Name: wh_price_history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wh_price_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid DEFAULT '1084baa8-0355-4298-9b98-b876a7581173'::uuid NOT NULL,
    variation_id uuid NOT NULL,
    price numeric(10,2) NOT NULL,
    price_unit text,
    effective_from timestamp with time zone DEFAULT now() NOT NULL,
    effective_to timestamp with time zone,
    changed_by uuid,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT wh_price_history_interval_sane CHECK (((effective_to IS NULL) OR (effective_to > effective_from)))
);


ALTER TABLE public.wh_price_history OWNER TO postgres;

--
-- Name: wh_current_prices; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.wh_current_prices WITH (security_invoker='true') AS
 SELECT variation_id,
    price,
    price_unit,
    effective_from,
    effective_to
   FROM public.wh_price_history
  WHERE ((effective_from <= now()) AND ((effective_to IS NULL) OR (effective_to > now())));


ALTER VIEW public.wh_current_prices OWNER TO postgres;

--
-- Name: wh_drivers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wh_drivers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid DEFAULT '1084baa8-0355-4298-9b98-b876a7581173'::uuid NOT NULL,
    name text NOT NULL,
    email text NOT NULL,
    phone text,
    active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.wh_drivers OWNER TO postgres;

--
-- Name: wh_order_line_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wh_order_line_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid DEFAULT '1084baa8-0355-4298-9b98-b876a7581173'::uuid NOT NULL,
    order_id uuid NOT NULL,
    category text,
    description text,
    specs text,
    amount numeric(10,2),
    display_order integer DEFAULT 0
);


ALTER TABLE public.wh_order_line_items OWNER TO postgres;

--
-- Name: wh_order_number_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wh_order_number_seq
    START WITH 10001
    INCREMENT BY 1
    MINVALUE 10001
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wh_order_number_seq OWNER TO postgres;

--
-- Name: wh_orders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wh_orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid DEFAULT '1084baa8-0355-4298-9b98-b876a7581173'::uuid NOT NULL,
    order_number text NOT NULL,
    order_date timestamp with time zone DEFAULT now(),
    system text,
    customer_id uuid,
    customer_name text,
    customer_phone text,
    customer_email text,
    job_name text,
    fulfillment text,
    order_notes text,
    order_total numeric(10,2),
    status text DEFAULT 'pending'::text,
    driver_email text,
    webhook_fired boolean DEFAULT false,
    webhook_payload jsonb,
    pdf_url text,
    pdf_generated_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    webhook_error text,
    payment_status text DEFAULT 'unpaid'::text NOT NULL,
    stripe_payment_intent_id text,
    amount_paid_cents integer,
    paid_at timestamp with time zone,
    CONSTRAINT wh_orders_payment_status_chk CHECK ((payment_status = ANY (ARRAY['unpaid'::text, 'paid'::text, 'refunded'::text, 'not_required'::text])))
);


ALTER TABLE public.wh_orders OWNER TO postgres;

--
-- Name: wh_product_colors; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wh_product_colors (
    product_id uuid NOT NULL,
    color_id uuid NOT NULL,
    price_modifier numeric(10,2) DEFAULT 0
);


ALTER TABLE public.wh_product_colors OWNER TO postgres;

--
-- Name: wh_product_families; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wh_product_families (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid DEFAULT '1084baa8-0355-4298-9b98-b876a7581173'::uuid NOT NULL,
    name text NOT NULL,
    slug text,
    product_type text,
    catalog_section text,
    compatible_systems text[] DEFAULT '{}'::text[] NOT NULL,
    image_url text,
    display_order integer DEFAULT 0 NOT NULL,
    status text DEFAULT 'live'::text NOT NULL,
    member_conflicts jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    type_id uuid,
    CONSTRAINT wh_product_families_status_check CHECK ((status = ANY (ARRAY['live'::text, 'draft'::text, 'archived'::text])))
);


ALTER TABLE public.wh_product_families OWNER TO postgres;

--
-- Name: wh_product_roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wh_product_roles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid DEFAULT '1084baa8-0355-4298-9b98-b876a7581173'::uuid NOT NULL,
    key text NOT NULL,
    name text NOT NULL,
    product_id uuid,
    system_slug text,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.wh_product_roles OWNER TO postgres;

--
-- Name: wh_product_types; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wh_product_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid DEFAULT '1084baa8-0355-4298-9b98-b876a7581173'::uuid NOT NULL,
    key text NOT NULL,
    name text NOT NULL,
    takes_color boolean DEFAULT false NOT NULL,
    takes_finish boolean DEFAULT false NOT NULL,
    takes_gauge boolean DEFAULT false NOT NULL,
    sold_in_packs boolean DEFAULT false NOT NULL,
    input_mode text,
    unit_factor numeric,
    waste_factor numeric,
    coverage_mult numeric,
    pack_qty integer,
    attributes jsonb DEFAULT '{}'::jsonb NOT NULL,
    display_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT wh_product_types_input_mode_check CHECK (((input_mode IS NULL) OR (input_mode = ANY (ARRAY['area'::text, 'linear'::text, 'each'::text, 'panel_run'::text]))))
);


ALTER TABLE public.wh_product_types OWNER TO postgres;

--
-- Name: COLUMN wh_product_types.input_mode; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.wh_product_types.input_mode IS 'CP13-owned. NULL = not yet assigned; do not populate outside Checkpoint 13.';


--
-- Name: COLUMN wh_product_types.unit_factor; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.wh_product_types.unit_factor IS 'CP13-owned. NULL = not yet assigned; do not populate outside Checkpoint 13.';


--
-- Name: COLUMN wh_product_types.waste_factor; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.wh_product_types.waste_factor IS 'CP13-owned. NULL = not yet assigned; NULL is NOT equivalent to 1.0.';


--
-- Name: COLUMN wh_product_types.coverage_mult; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.wh_product_types.coverage_mult IS 'CP13-owned. NULL = not yet assigned; NULL is NOT equivalent to 1.0.';


--
-- Name: COLUMN wh_product_types.pack_qty; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.wh_product_types.pack_qty IS 'CP13-owned. NULL = not yet assigned.';


--
-- Name: wh_product_variations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wh_product_variations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid DEFAULT '1084baa8-0355-4298-9b98-b876a7581173'::uuid NOT NULL,
    family_id uuid NOT NULL,
    source_product_id uuid,
    name text NOT NULL,
    sku text,
    price numeric(10,2),
    price_unit text,
    gauge text,
    finish text,
    status text DEFAULT 'live'::text NOT NULL,
    display_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    type_id uuid,
    image_url text,
    CONSTRAINT wh_product_variations_status_check CHECK ((status = ANY (ARRAY['live'::text, 'draft'::text, 'special_order'::text])))
);


ALTER TABLE public.wh_product_variations OWNER TO postgres;

--
-- Name: COLUMN wh_product_variations.image_url; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.wh_product_variations.image_url IS 'Per-variation photo. Storefront resolver order: variation -> family -> category -> repo convention.';


--
-- Name: wh_products; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wh_products (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    name text NOT NULL,
    sku text,
    description text,
    gauge text,
    finish text,
    image_url text,
    unit_type text DEFAULT 'linear_foot'::text,
    unit_size text,
    base_price numeric(10,2),
    active boolean DEFAULT true,
    display_order integer DEFAULT 0,
    product_type text,
    catalog_section text,
    compatible_systems text[] DEFAULT '{}'::text[],
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.wh_products OWNER TO postgres;

--
-- Name: wh_settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wh_settings (
    org_id uuid DEFAULT '1084baa8-0355-4298-9b98-b876a7581173'::uuid NOT NULL,
    key text NOT NULL,
    value text,
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.wh_settings OWNER TO postgres;

--
-- Name: wh_spec_files; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wh_spec_files (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid DEFAULT '1084baa8-0355-4298-9b98-b876a7581173'::uuid NOT NULL,
    order_id uuid NOT NULL,
    filename text,
    storage_url text,
    description text,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.wh_spec_files OWNER TO postgres;

--
-- Name: wh_stages; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wh_stages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    system_id uuid NOT NULL,
    name text NOT NULL,
    display_order integer NOT NULL,
    active boolean DEFAULT true NOT NULL
);


ALTER TABLE public.wh_stages OWNER TO postgres;

--
-- Name: wh_systems; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wh_systems (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid NOT NULL,
    name text NOT NULL,
    slug text NOT NULL,
    hero_image_url text,
    tagline text,
    description text,
    display_order integer DEFAULT 0,
    active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.wh_systems OWNER TO postgres;

--
-- Name: wh_team_members; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wh_team_members (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid DEFAULT '1084baa8-0355-4298-9b98-b876a7581173'::uuid NOT NULL,
    user_id uuid,
    name text NOT NULL,
    email text NOT NULL,
    phone text,
    role text DEFAULT 'assistant'::text NOT NULL,
    is_driver boolean DEFAULT false NOT NULL,
    driver_active boolean DEFAULT false NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT wh_team_members_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'assistant'::text, 'driver'::text]))),
    CONSTRAINT wh_team_members_status_check CHECK ((status = ANY (ARRAY['active'::text, 'invited'::text, 'disabled'::text])))
);


ALTER TABLE public.wh_team_members OWNER TO postgres;

--
-- Name: wh_variation_colors; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wh_variation_colors (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    org_id uuid DEFAULT '1084baa8-0355-4298-9b98-b876a7581173'::uuid NOT NULL,
    variation_id uuid NOT NULL,
    color_id uuid NOT NULL,
    price_modifier numeric,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.wh_variation_colors OWNER TO postgres;

--
-- Name: work_order_activity; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.work_order_activity (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    work_order_id uuid NOT NULL,
    org_id uuid NOT NULL,
    action text NOT NULL,
    from_value text,
    to_value text,
    actor_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.work_order_activity OWNER TO postgres;

--
-- Name: tg_agenda_card id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tg_agenda_card ALTER COLUMN id SET DEFAULT nextval('public.tg_agenda_card_id_seq'::regclass);


--
-- Name: tg_agenda_contact id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tg_agenda_contact ALTER COLUMN id SET DEFAULT nextval('public.tg_agenda_contact_id_seq'::regclass);


--
-- Name: audit_leads audit_leads_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_leads
    ADD CONSTRAINT audit_leads_pkey PRIMARY KEY (id);


--
-- Name: audits audits_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audits
    ADD CONSTRAINT audits_pkey PRIMARY KEY (id);


--
-- Name: check_ins check_ins_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.check_ins
    ADD CONSTRAINT check_ins_pkey PRIMARY KEY (id);


--
-- Name: client_roadmaps client_roadmaps_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client_roadmaps
    ADD CONSTRAINT client_roadmaps_pkey PRIMARY KEY (id);


--
-- Name: client_roadmaps client_roadmaps_token_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client_roadmaps
    ADD CONSTRAINT client_roadmaps_token_key UNIQUE (token);


--
-- Name: deal_activity deal_activity_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deal_activity
    ADD CONSTRAINT deal_activity_pkey PRIMARY KEY (id);


--
-- Name: deal_notes deal_notes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deal_notes
    ADD CONSTRAINT deal_notes_pkey PRIMARY KEY (id);


--
-- Name: deals deals_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deals
    ADD CONSTRAINT deals_pkey PRIMARY KEY (id);


--
-- Name: engagement_checkins engagement_checkins_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.engagement_checkins
    ADD CONSTRAINT engagement_checkins_pkey PRIMARY KEY (id);


--
-- Name: engagement_levels engagement_levels_engagement_id_level_no_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.engagement_levels
    ADD CONSTRAINT engagement_levels_engagement_id_level_no_key UNIQUE (engagement_id, level_no);


--
-- Name: engagement_levels engagement_levels_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.engagement_levels
    ADD CONSTRAINT engagement_levels_pkey PRIMARY KEY (id);


--
-- Name: engagement_milestones engagement_milestones_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.engagement_milestones
    ADD CONSTRAINT engagement_milestones_pkey PRIMARY KEY (id);


--
-- Name: engagements engagements_deal_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.engagements
    ADD CONSTRAINT engagements_deal_id_key UNIQUE (deal_id);


--
-- Name: engagements engagements_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.engagements
    ADD CONSTRAINT engagements_pkey PRIMARY KEY (id);


--
-- Name: estimate_line_items estimate_line_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estimate_line_items
    ADD CONSTRAINT estimate_line_items_pkey PRIMARY KEY (id);


--
-- Name: estimate_number_counters estimate_number_counters_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estimate_number_counters
    ADD CONSTRAINT estimate_number_counters_pkey PRIMARY KEY (org_id);


--
-- Name: estimates estimates_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estimates
    ADD CONSTRAINT estimates_pkey PRIMARY KEY (id);


--
-- Name: follow_ups follow_ups_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.follow_ups
    ADD CONSTRAINT follow_ups_pkey PRIMARY KEY (id);


--
-- Name: jobs jobs_estimate_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT jobs_estimate_id_key UNIQUE (estimate_id);


--
-- Name: CONSTRAINT jobs_estimate_id_key ON jobs; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON CONSTRAINT jobs_estimate_id_key ON public.jobs IS 'D1: one job per signed estimate. Without this a double-click creates two jobs on one estimate.';


--
-- Name: jobs jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT jobs_pkey PRIMARY KEY (id);


--
-- Name: lead_activity lead_activity_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lead_activity
    ADD CONSTRAINT lead_activity_pkey PRIMARY KEY (id);


--
-- Name: lead_appointments lead_appointments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lead_appointments
    ADD CONSTRAINT lead_appointments_pkey PRIMARY KEY (id);


--
-- Name: lead_notes lead_notes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lead_notes
    ADD CONSTRAINT lead_notes_pkey PRIMARY KEY (id);


--
-- Name: leads leads_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT leads_pkey PRIMARY KEY (id);


--
-- Name: material_items material_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.material_items
    ADD CONSTRAINT material_items_pkey PRIMARY KEY (id);


--
-- Name: migration_bmr_activity_raw migration_bmr_activity_raw_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.migration_bmr_activity_raw
    ADD CONSTRAINT migration_bmr_activity_raw_pkey PRIMARY KEY (old_id);


--
-- Name: migration_bmr_id_map migration_bmr_id_map_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.migration_bmr_id_map
    ADD CONSTRAINT migration_bmr_id_map_pkey PRIMARY KEY (entity, old_id);


--
-- Name: migration_bmr_leads_raw migration_bmr_leads_raw_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.migration_bmr_leads_raw
    ADD CONSTRAINT migration_bmr_leads_raw_pkey PRIMARY KEY (old_id);


--
-- Name: migration_bmr_notes_raw migration_bmr_notes_raw_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.migration_bmr_notes_raw
    ADD CONSTRAINT migration_bmr_notes_raw_pkey PRIMARY KEY (old_id);


--
-- Name: migration_bmr_users_raw migration_bmr_users_raw_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.migration_bmr_users_raw
    ADD CONSTRAINT migration_bmr_users_raw_pkey PRIMARY KEY (old_id);


--
-- Name: org_invites org_invites_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.org_invites
    ADD CONSTRAINT org_invites_pkey PRIMARY KEY (id);


--
-- Name: org_invites org_invites_token_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.org_invites
    ADD CONSTRAINT org_invites_token_key UNIQUE (token);


--
-- Name: org_invoices org_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.org_invoices
    ADD CONSTRAINT org_invoices_pkey PRIMARY KEY (id);


--
-- Name: org_members org_members_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.org_members
    ADD CONSTRAINT org_members_pkey PRIMARY KEY (org_id, user_id);


--
-- Name: org_systems org_systems_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.org_systems
    ADD CONSTRAINT org_systems_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: pipeline_invites pipeline_invites_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pipeline_invites
    ADD CONSTRAINT pipeline_invites_pkey PRIMARY KEY (id);


--
-- Name: pipeline_invites pipeline_invites_token_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pipeline_invites
    ADD CONSTRAINT pipeline_invites_token_key UNIQUE (token);


--
-- Name: production_packets production_packets_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.production_packets
    ADD CONSTRAINT production_packets_pkey PRIMARY KEY (id);


--
-- Name: production_packets production_packets_work_order_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.production_packets
    ADD CONSTRAINT production_packets_work_order_id_key UNIQUE (work_order_id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: proposals proposals_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.proposals
    ADD CONSTRAINT proposals_pkey PRIMARY KEY (id);


--
-- Name: prospects prospects_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.prospects
    ADD CONSTRAINT prospects_pkey PRIMARY KEY (id);


--
-- Name: roadmap_items roadmap_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roadmap_items
    ADD CONSTRAINT roadmap_items_pkey PRIMARY KEY (id);


--
-- Name: roadmap_projects roadmap_projects_org_id_key_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roadmap_projects
    ADD CONSTRAINT roadmap_projects_org_id_key_key UNIQUE (org_id, key);


--
-- Name: roadmap_projects roadmap_projects_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roadmap_projects
    ADD CONSTRAINT roadmap_projects_pkey PRIMARY KEY (id);


--
-- Name: schedule_blocks schedule_blocks_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schedule_blocks
    ADD CONSTRAINT schedule_blocks_pkey PRIMARY KEY (id);


--
-- Name: signatures signatures_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.signatures
    ADD CONSTRAINT signatures_pkey PRIMARY KEY (id);


--
-- Name: signatures signatures_sign_token_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.signatures
    ADD CONSTRAINT signatures_sign_token_key UNIQUE (sign_token);


--
-- Name: staff_invites staff_invites_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_invites
    ADD CONSTRAINT staff_invites_pkey PRIMARY KEY (id);


--
-- Name: staff_invites staff_invites_token_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_invites
    ADD CONSTRAINT staff_invites_token_key UNIQUE (token);


--
-- Name: staff_users staff_users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_users
    ADD CONSTRAINT staff_users_pkey PRIMARY KEY (user_id);


--
-- Name: structtech_state structtech_state_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.structtech_state
    ADD CONSTRAINT structtech_state_pkey PRIMARY KEY (id);


--
-- Name: tenant_modules tenant_modules_org_id_module_key_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tenant_modules
    ADD CONSTRAINT tenant_modules_org_id_module_key_key UNIQUE (org_id, module_key);


--
-- Name: tenant_modules tenant_modules_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tenant_modules
    ADD CONSTRAINT tenant_modules_pkey PRIMARY KEY (id);


--
-- Name: tg_agenda_card tg_agenda_card_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tg_agenda_card
    ADD CONSTRAINT tg_agenda_card_pkey PRIMARY KEY (id);


--
-- Name: tg_agenda_contact tg_agenda_contact_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tg_agenda_contact
    ADD CONSTRAINT tg_agenda_contact_pkey PRIMARY KEY (id);


--
-- Name: tg_agenda_contact tg_agenda_contact_tg_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tg_agenda_contact
    ADD CONSTRAINT tg_agenda_contact_tg_user_id_key UNIQUE (tg_user_id);


--
-- Name: tg_agenda_group tg_agenda_group_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tg_agenda_group
    ADD CONSTRAINT tg_agenda_group_pkey PRIMARY KEY (chat_id);


--
-- Name: tg_agenda_sender tg_agenda_sender_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tg_agenda_sender
    ADD CONSTRAINT tg_agenda_sender_pkey PRIMARY KEY (tg_user_id);


--
-- Name: tg_agenda_session tg_agenda_session_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tg_agenda_session
    ADD CONSTRAINT tg_agenda_session_pkey PRIMARY KEY (chat_id, tg_user_id);


--
-- Name: tg_agenda_update tg_agenda_update_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tg_agenda_update
    ADD CONSTRAINT tg_agenda_update_pkey PRIMARY KEY (update_id);


--
-- Name: ticket_messages ticket_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ticket_messages
    ADD CONSTRAINT ticket_messages_pkey PRIMARY KEY (id);


--
-- Name: tickets tickets_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_pkey PRIMARY KEY (id);


--
-- Name: tracker_items tracker_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tracker_items
    ADD CONSTRAINT tracker_items_pkey PRIMARY KEY (id);


--
-- Name: tracker_projects tracker_projects_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tracker_projects
    ADD CONSTRAINT tracker_projects_pkey PRIMARY KEY (id);


--
-- Name: wh_categories wh_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_categories
    ADD CONSTRAINT wh_categories_pkey PRIMARY KEY (id);


--
-- Name: wh_category_products wh_category_products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_category_products
    ADD CONSTRAINT wh_category_products_pkey PRIMARY KEY (category_id, product_id);


--
-- Name: wh_colors wh_colors_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_colors
    ADD CONSTRAINT wh_colors_pkey PRIMARY KEY (id);


--
-- Name: wh_drivers wh_drivers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_drivers
    ADD CONSTRAINT wh_drivers_pkey PRIMARY KEY (id);


--
-- Name: wh_order_line_items wh_order_line_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_order_line_items
    ADD CONSTRAINT wh_order_line_items_pkey PRIMARY KEY (id);


--
-- Name: wh_orders wh_orders_order_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_orders
    ADD CONSTRAINT wh_orders_order_number_key UNIQUE (order_number);


--
-- Name: wh_orders wh_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_orders
    ADD CONSTRAINT wh_orders_pkey PRIMARY KEY (id);


--
-- Name: wh_price_history wh_price_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_price_history
    ADD CONSTRAINT wh_price_history_pkey PRIMARY KEY (id);


--
-- Name: wh_price_history wh_price_no_overlap; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_price_history
    ADD CONSTRAINT wh_price_no_overlap EXCLUDE USING gist (variation_id WITH =, tstzrange(effective_from, COALESCE(effective_to, 'infinity'::timestamp with time zone)) WITH &&);


--
-- Name: wh_product_colors wh_product_colors_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_product_colors
    ADD CONSTRAINT wh_product_colors_pkey PRIMARY KEY (product_id, color_id);


--
-- Name: wh_product_families wh_product_families_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_product_families
    ADD CONSTRAINT wh_product_families_pkey PRIMARY KEY (id);


--
-- Name: wh_product_roles wh_product_roles_org_id_key_system_slug_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_product_roles
    ADD CONSTRAINT wh_product_roles_org_id_key_system_slug_key UNIQUE NULLS NOT DISTINCT (org_id, key, system_slug);


--
-- Name: wh_product_roles wh_product_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_product_roles
    ADD CONSTRAINT wh_product_roles_pkey PRIMARY KEY (id);


--
-- Name: wh_product_types wh_product_types_org_id_key_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_product_types
    ADD CONSTRAINT wh_product_types_org_id_key_key UNIQUE (org_id, key);


--
-- Name: wh_product_types wh_product_types_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_product_types
    ADD CONSTRAINT wh_product_types_pkey PRIMARY KEY (id);


--
-- Name: wh_product_variations wh_product_variations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_product_variations
    ADD CONSTRAINT wh_product_variations_pkey PRIMARY KEY (id);


--
-- Name: wh_products wh_products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_products
    ADD CONSTRAINT wh_products_pkey PRIMARY KEY (id);


--
-- Name: wh_settings wh_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_settings
    ADD CONSTRAINT wh_settings_pkey PRIMARY KEY (org_id, key);


--
-- Name: wh_spec_files wh_spec_files_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_spec_files
    ADD CONSTRAINT wh_spec_files_pkey PRIMARY KEY (id);


--
-- Name: wh_stages wh_stages_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_stages
    ADD CONSTRAINT wh_stages_pkey PRIMARY KEY (id);


--
-- Name: wh_systems wh_systems_org_id_slug_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_systems
    ADD CONSTRAINT wh_systems_org_id_slug_key UNIQUE (org_id, slug);


--
-- Name: wh_systems wh_systems_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_systems
    ADD CONSTRAINT wh_systems_pkey PRIMARY KEY (id);


--
-- Name: wh_team_members wh_team_members_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_team_members
    ADD CONSTRAINT wh_team_members_pkey PRIMARY KEY (id);


--
-- Name: wh_variation_colors wh_variation_colors_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_variation_colors
    ADD CONSTRAINT wh_variation_colors_pkey PRIMARY KEY (id);


--
-- Name: wh_variation_colors wh_variation_colors_variation_id_color_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_variation_colors
    ADD CONSTRAINT wh_variation_colors_variation_id_color_id_key UNIQUE (variation_id, color_id);


--
-- Name: work_order_activity work_order_activity_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.work_order_activity
    ADD CONSTRAINT work_order_activity_pkey PRIMARY KEY (id);


--
-- Name: work_order_agreements work_order_agreements_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.work_order_agreements
    ADD CONSTRAINT work_order_agreements_pkey PRIMARY KEY (id);


--
-- Name: work_order_agreements work_order_agreements_sign_token_hash_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.work_order_agreements
    ADD CONSTRAINT work_order_agreements_sign_token_hash_key UNIQUE (sign_token_hash);


--
-- Name: work_orders work_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.work_orders
    ADD CONSTRAINT work_orders_pkey PRIMARY KEY (id);


--
-- Name: check_ins_org_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX check_ins_org_id_idx ON public.check_ins USING btree (org_id);


--
-- Name: check_ins_work_order_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX check_ins_work_order_id_idx ON public.check_ins USING btree (work_order_id);


--
-- Name: engagement_checkins_engagement_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX engagement_checkins_engagement_id_idx ON public.engagement_checkins USING btree (engagement_id);


--
-- Name: engagement_checkins_org_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX engagement_checkins_org_id_idx ON public.engagement_checkins USING btree (org_id);


--
-- Name: engagement_levels_engagement_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX engagement_levels_engagement_id_idx ON public.engagement_levels USING btree (engagement_id);


--
-- Name: engagement_levels_org_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX engagement_levels_org_id_idx ON public.engagement_levels USING btree (org_id);


--
-- Name: engagement_milestones_level_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX engagement_milestones_level_id_idx ON public.engagement_milestones USING btree (level_id);


--
-- Name: engagement_milestones_org_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX engagement_milestones_org_id_idx ON public.engagement_milestones USING btree (org_id);


--
-- Name: engagements_org_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX engagements_org_id_idx ON public.engagements USING btree (org_id);


--
-- Name: estimate_line_items_estimate_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX estimate_line_items_estimate_id_idx ON public.estimate_line_items USING btree (estimate_id);


--
-- Name: estimate_line_items_estimate_scope_key_uidx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX estimate_line_items_estimate_scope_key_uidx ON public.estimate_line_items USING btree (estimate_id, scope_key) WHERE (scope_key IS NOT NULL);


--
-- Name: estimate_line_items_org_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX estimate_line_items_org_id_idx ON public.estimate_line_items USING btree (org_id);


--
-- Name: estimates_deal_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX estimates_deal_id_idx ON public.estimates USING btree (deal_id);


--
-- Name: estimates_org_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX estimates_org_id_idx ON public.estimates USING btree (org_id);


--
-- Name: idx_audit_leads_created; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_audit_leads_created ON public.audit_leads USING btree (created_at DESC);


--
-- Name: idx_audit_leads_email; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_audit_leads_email ON public.audit_leads USING btree (email);


--
-- Name: idx_audit_leads_risk; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_audit_leads_risk ON public.audit_leads USING btree (risk_level);


--
-- Name: idx_client_roadmaps_token; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_client_roadmaps_token ON public.client_roadmaps USING btree (token);


--
-- Name: idx_wh_drivers_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wh_drivers_org_id ON public.wh_drivers USING btree (org_id);


--
-- Name: idx_wh_line_items_order_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wh_line_items_order_id ON public.wh_order_line_items USING btree (order_id);


--
-- Name: idx_wh_line_items_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wh_line_items_org_id ON public.wh_order_line_items USING btree (org_id);


--
-- Name: idx_wh_orders_customer_email; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wh_orders_customer_email ON public.wh_orders USING btree (lower(customer_email));


--
-- Name: idx_wh_orders_customer_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wh_orders_customer_id ON public.wh_orders USING btree (customer_id);


--
-- Name: idx_wh_orders_order_number; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wh_orders_order_number ON public.wh_orders USING btree (order_number);


--
-- Name: idx_wh_orders_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wh_orders_org_id ON public.wh_orders USING btree (org_id);


--
-- Name: idx_wh_orders_stripe_pi; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wh_orders_stripe_pi ON public.wh_orders USING btree (stripe_payment_intent_id);


--
-- Name: idx_wh_products_catalog_section; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wh_products_catalog_section ON public.wh_products USING btree (catalog_section);


--
-- Name: idx_wh_products_compatible_systems; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wh_products_compatible_systems ON public.wh_products USING gin (compatible_systems);


--
-- Name: idx_wh_spec_files_order_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wh_spec_files_order_id ON public.wh_spec_files USING btree (order_id);


--
-- Name: idx_wh_spec_files_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wh_spec_files_org_id ON public.wh_spec_files USING btree (org_id);


--
-- Name: jobs_deal_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX jobs_deal_id_idx ON public.jobs USING btree (deal_id);


--
-- Name: jobs_estimate_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX jobs_estimate_id_idx ON public.jobs USING btree (estimate_id);


--
-- Name: jobs_org_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX jobs_org_id_idx ON public.jobs USING btree (org_id);


--
-- Name: lead_activity_lead_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX lead_activity_lead_idx ON public.lead_activity USING btree (lead_id);


--
-- Name: lead_appointments_lead_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX lead_appointments_lead_idx ON public.lead_appointments USING btree (lead_id);


--
-- Name: lead_notes_lead_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX lead_notes_lead_idx ON public.lead_notes USING btree (lead_id);


--
-- Name: leads_created_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX leads_created_at_idx ON public.leads USING btree (created_at);


--
-- Name: leads_owner_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX leads_owner_idx ON public.leads USING btree (owner_id);


--
-- Name: leads_stage_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX leads_stage_idx ON public.leads USING btree (stage);


--
-- Name: leads_status_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX leads_status_idx ON public.leads USING btree (status);


--
-- Name: material_items_org_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX material_items_org_id_idx ON public.material_items USING btree (org_id);


--
-- Name: material_items_work_order_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX material_items_work_order_id_idx ON public.material_items USING btree (work_order_id);


--
-- Name: production_packets_org_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX production_packets_org_id_idx ON public.production_packets USING btree (org_id);


--
-- Name: roadmap_items_org_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX roadmap_items_org_id_idx ON public.roadmap_items USING btree (org_id);


--
-- Name: roadmap_items_org_project_section_sort_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX roadmap_items_org_project_section_sort_idx ON public.roadmap_items USING btree (org_id, project_id, section, sort_order);


--
-- Name: roadmap_items_org_section_sort_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX roadmap_items_org_section_sort_idx ON public.roadmap_items USING btree (org_id, section, sort_order);


--
-- Name: schedule_blocks_org_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX schedule_blocks_org_id_idx ON public.schedule_blocks USING btree (org_id);


--
-- Name: schedule_blocks_work_order_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX schedule_blocks_work_order_id_idx ON public.schedule_blocks USING btree (work_order_id);


--
-- Name: signatures_estimate_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX signatures_estimate_id_idx ON public.signatures USING btree (estimate_id);


--
-- Name: signatures_org_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX signatures_org_id_idx ON public.signatures USING btree (org_id);


--
-- Name: tg_agenda_card_created_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX tg_agenda_card_created_idx ON public.tg_agenda_card USING btree (created_at DESC);


--
-- Name: tg_agenda_session_updated_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX tg_agenda_session_updated_idx ON public.tg_agenda_session USING btree (updated_at);


--
-- Name: tg_agenda_update_seen_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX tg_agenda_update_seen_idx ON public.tg_agenda_update USING btree (seen_at);


--
-- Name: tracker_items_org_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX tracker_items_org_id_idx ON public.tracker_items USING btree (org_id);


--
-- Name: tracker_items_project_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX tracker_items_project_id_idx ON public.tracker_items USING btree (project_id);


--
-- Name: wh_price_history_one_open; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX wh_price_history_one_open ON public.wh_price_history USING btree (variation_id) WHERE (effective_to IS NULL);


--
-- Name: wh_price_history_variation_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX wh_price_history_variation_idx ON public.wh_price_history USING btree (variation_id, effective_from DESC);


--
-- Name: wh_product_families_org_name_uk; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX wh_product_families_org_name_uk ON public.wh_product_families USING btree (org_id, lower(name));


--
-- Name: wh_product_families_type_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX wh_product_families_type_idx ON public.wh_product_families USING btree (type_id);


--
-- Name: wh_product_roles_product_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX wh_product_roles_product_idx ON public.wh_product_roles USING btree (product_id);


--
-- Name: wh_product_variations_family_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX wh_product_variations_family_idx ON public.wh_product_variations USING btree (family_id);


--
-- Name: wh_product_variations_source_uk; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX wh_product_variations_source_uk ON public.wh_product_variations USING btree (source_product_id) WHERE (source_product_id IS NOT NULL);


--
-- Name: wh_product_variations_type_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX wh_product_variations_type_idx ON public.wh_product_variations USING btree (type_id);


--
-- Name: wh_team_members_one_active_driver; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX wh_team_members_one_active_driver ON public.wh_team_members USING btree (org_id) WHERE (driver_active = true);


--
-- Name: wh_team_members_org_user_uk; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX wh_team_members_org_user_uk ON public.wh_team_members USING btree (org_id, user_id) WHERE (user_id IS NOT NULL);


--
-- Name: wh_variation_colors_color_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX wh_variation_colors_color_idx ON public.wh_variation_colors USING btree (color_id);


--
-- Name: wh_variation_colors_variation_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX wh_variation_colors_variation_idx ON public.wh_variation_colors USING btree (variation_id);


--
-- Name: work_order_agreements_one_active_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX work_order_agreements_one_active_idx ON public.work_order_agreements USING btree (work_order_id) WHERE (status <> 'voided'::text);


--
-- Name: work_order_agreements_org_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX work_order_agreements_org_id_idx ON public.work_order_agreements USING btree (org_id);


--
-- Name: work_order_agreements_work_order_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX work_order_agreements_work_order_id_idx ON public.work_order_agreements USING btree (work_order_id);


--
-- Name: work_orders_job_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX work_orders_job_id_idx ON public.work_orders USING btree (job_id);


--
-- Name: work_orders_one_master_per_job; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX work_orders_one_master_per_job ON public.work_orders USING btree (job_id) WHERE (kind = 'master'::text);


--
-- Name: work_orders_org_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX work_orders_org_id_idx ON public.work_orders USING btree (org_id);


--
-- Name: work_orders_predecessor_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX work_orders_predecessor_id_idx ON public.work_orders USING btree (predecessor_id);


--
-- Name: leads leads_touch_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER leads_touch_updated_at BEFORE UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION public.touch_leads_updated_at();


--
-- Name: audit_leads trg_auto_deal; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_auto_deal AFTER INSERT ON public.audit_leads FOR EACH ROW EXECUTE FUNCTION public.auto_create_deal();


--
-- Name: audit_leads trg_auto_roadmap; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_auto_roadmap AFTER INSERT ON public.audit_leads FOR EACH ROW EXECUTE FUNCTION public.auto_create_roadmap();


--
-- Name: deals trg_deal_stage; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_deal_stage BEFORE UPDATE ON public.deals FOR EACH ROW EXECUTE FUNCTION public.deal_stage_side_effects();


--
-- Name: engagement_milestones trg_derive_level_status; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_derive_level_status AFTER INSERT OR UPDATE OF status ON public.engagement_milestones FOR EACH ROW EXECUTE FUNCTION public.derive_level_status();


--
-- Name: estimate_line_items trg_estimate_line_items_sync_subtotal; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_estimate_line_items_sync_subtotal AFTER INSERT OR DELETE OR UPDATE ON public.estimate_line_items FOR EACH ROW EXECUTE FUNCTION public.estimate_line_items_sync_subtotal();


--
-- Name: client_roadmaps trg_protect_roadmap; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_protect_roadmap BEFORE UPDATE ON public.client_roadmaps FOR EACH ROW EXECUTE FUNCTION public.protect_roadmap_columns();


--
-- Name: audit_leads audit_leads_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_leads
    ADD CONSTRAINT audit_leads_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: audits audits_prospect_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audits
    ADD CONSTRAINT audits_prospect_id_fkey FOREIGN KEY (prospect_id) REFERENCES public.prospects(id) ON DELETE CASCADE;


--
-- Name: check_ins check_ins_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.check_ins
    ADD CONSTRAINT check_ins_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: check_ins check_ins_schedule_block_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.check_ins
    ADD CONSTRAINT check_ins_schedule_block_id_fkey FOREIGN KEY (schedule_block_id) REFERENCES public.schedule_blocks(id) ON DELETE SET NULL;


--
-- Name: check_ins check_ins_work_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.check_ins
    ADD CONSTRAINT check_ins_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES public.work_orders(id) ON DELETE CASCADE;


--
-- Name: client_roadmaps client_roadmaps_lead_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client_roadmaps
    ADD CONSTRAINT client_roadmaps_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES public.audit_leads(id);


--
-- Name: client_roadmaps client_roadmaps_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.client_roadmaps
    ADD CONSTRAINT client_roadmaps_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: deal_activity deal_activity_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deal_activity
    ADD CONSTRAINT deal_activity_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.profiles(id);


--
-- Name: deal_activity deal_activity_deal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deal_activity
    ADD CONSTRAINT deal_activity_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES public.deals(id) ON DELETE CASCADE;


--
-- Name: deal_activity deal_activity_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deal_activity
    ADD CONSTRAINT deal_activity_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: deal_notes deal_notes_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deal_notes
    ADD CONSTRAINT deal_notes_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);


--
-- Name: deal_notes deal_notes_deal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deal_notes
    ADD CONSTRAINT deal_notes_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES public.deals(id) ON DELETE CASCADE;


--
-- Name: deal_notes deal_notes_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deal_notes
    ADD CONSTRAINT deal_notes_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: deals deals_lead_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deals
    ADD CONSTRAINT deals_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES public.audit_leads(id);


--
-- Name: deals deals_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deals
    ADD CONSTRAINT deals_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: deals deals_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deals
    ADD CONSTRAINT deals_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.profiles(id);


--
-- Name: engagement_checkins engagement_checkins_engagement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.engagement_checkins
    ADD CONSTRAINT engagement_checkins_engagement_id_fkey FOREIGN KEY (engagement_id) REFERENCES public.engagements(id) ON DELETE CASCADE;


--
-- Name: engagement_checkins engagement_checkins_level_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.engagement_checkins
    ADD CONSTRAINT engagement_checkins_level_id_fkey FOREIGN KEY (level_id) REFERENCES public.engagement_levels(id) ON DELETE SET NULL;


--
-- Name: engagement_checkins engagement_checkins_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.engagement_checkins
    ADD CONSTRAINT engagement_checkins_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: engagement_levels engagement_levels_depends_on_level_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.engagement_levels
    ADD CONSTRAINT engagement_levels_depends_on_level_id_fkey FOREIGN KEY (depends_on_level_id) REFERENCES public.engagement_levels(id);


--
-- Name: engagement_levels engagement_levels_engagement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.engagement_levels
    ADD CONSTRAINT engagement_levels_engagement_id_fkey FOREIGN KEY (engagement_id) REFERENCES public.engagements(id) ON DELETE CASCADE;


--
-- Name: engagement_levels engagement_levels_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.engagement_levels
    ADD CONSTRAINT engagement_levels_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: engagement_milestones engagement_milestones_level_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.engagement_milestones
    ADD CONSTRAINT engagement_milestones_level_id_fkey FOREIGN KEY (level_id) REFERENCES public.engagement_levels(id) ON DELETE CASCADE;


--
-- Name: engagement_milestones engagement_milestones_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.engagement_milestones
    ADD CONSTRAINT engagement_milestones_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: engagements engagements_deal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.engagements
    ADD CONSTRAINT engagements_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES public.deals(id);


--
-- Name: engagements engagements_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.engagements
    ADD CONSTRAINT engagements_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: engagements engagements_roadmap_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.engagements
    ADD CONSTRAINT engagements_roadmap_id_fkey FOREIGN KEY (roadmap_id) REFERENCES public.client_roadmaps(id);


--
-- Name: estimate_line_items estimate_line_items_estimate_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estimate_line_items
    ADD CONSTRAINT estimate_line_items_estimate_id_fkey FOREIGN KEY (estimate_id) REFERENCES public.estimates(id) ON DELETE CASCADE;


--
-- Name: estimate_line_items estimate_line_items_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estimate_line_items
    ADD CONSTRAINT estimate_line_items_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: estimate_number_counters estimate_number_counters_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estimate_number_counters
    ADD CONSTRAINT estimate_number_counters_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: estimates estimates_deal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estimates
    ADD CONSTRAINT estimates_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES public.deals(id);


--
-- Name: estimates estimates_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estimates
    ADD CONSTRAINT estimates_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: follow_ups follow_ups_deal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.follow_ups
    ADD CONSTRAINT follow_ups_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES public.deals(id) ON DELETE CASCADE;


--
-- Name: follow_ups follow_ups_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.follow_ups
    ADD CONSTRAINT follow_ups_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: jobs jobs_deal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT jobs_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES public.deals(id);


--
-- Name: jobs jobs_estimate_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT jobs_estimate_id_fkey FOREIGN KEY (estimate_id) REFERENCES public.estimates(id);


--
-- Name: jobs jobs_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT jobs_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: lead_activity lead_activity_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lead_activity
    ADD CONSTRAINT lead_activity_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.profiles(id);


--
-- Name: lead_activity lead_activity_lead_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lead_activity
    ADD CONSTRAINT lead_activity_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES public.leads(id) ON DELETE CASCADE;


--
-- Name: lead_appointments lead_appointments_lead_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lead_appointments
    ADD CONSTRAINT lead_appointments_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES public.leads(id) ON DELETE CASCADE;


--
-- Name: lead_notes lead_notes_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lead_notes
    ADD CONSTRAINT lead_notes_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.profiles(id);


--
-- Name: lead_notes lead_notes_lead_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lead_notes
    ADD CONSTRAINT lead_notes_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES public.leads(id) ON DELETE CASCADE;


--
-- Name: leads leads_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT leads_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.profiles(id);


--
-- Name: material_items material_items_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.material_items
    ADD CONSTRAINT material_items_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: material_items material_items_work_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.material_items
    ADD CONSTRAINT material_items_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES public.work_orders(id) ON DELETE CASCADE;


--
-- Name: org_invites org_invites_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.org_invites
    ADD CONSTRAINT org_invites_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: org_invoices org_invoices_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.org_invoices
    ADD CONSTRAINT org_invoices_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: org_members org_members_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.org_members
    ADD CONSTRAINT org_members_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: org_members org_members_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.org_members
    ADD CONSTRAINT org_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: org_systems org_systems_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.org_systems
    ADD CONSTRAINT org_systems_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: organizations organizations_deal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES public.deals(id);


--
-- Name: pipeline_invites pipeline_invites_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pipeline_invites
    ADD CONSTRAINT pipeline_invites_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);


--
-- Name: production_packets production_packets_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.production_packets
    ADD CONSTRAINT production_packets_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: production_packets production_packets_work_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.production_packets
    ADD CONSTRAINT production_packets_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES public.work_orders(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: proposals proposals_audit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.proposals
    ADD CONSTRAINT proposals_audit_id_fkey FOREIGN KEY (audit_id) REFERENCES public.audits(id);


--
-- Name: proposals proposals_prospect_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.proposals
    ADD CONSTRAINT proposals_prospect_id_fkey FOREIGN KEY (prospect_id) REFERENCES public.prospects(id) ON DELETE CASCADE;


--
-- Name: roadmap_items roadmap_items_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roadmap_items
    ADD CONSTRAINT roadmap_items_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: roadmap_items roadmap_items_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roadmap_items
    ADD CONSTRAINT roadmap_items_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.roadmap_projects(id) ON DELETE CASCADE;


--
-- Name: roadmap_items roadmap_items_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roadmap_items
    ADD CONSTRAINT roadmap_items_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.profiles(id);


--
-- Name: roadmap_projects roadmap_projects_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roadmap_projects
    ADD CONSTRAINT roadmap_projects_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: schedule_blocks schedule_blocks_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schedule_blocks
    ADD CONSTRAINT schedule_blocks_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: schedule_blocks schedule_blocks_work_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schedule_blocks
    ADD CONSTRAINT schedule_blocks_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES public.work_orders(id) ON DELETE CASCADE;


--
-- Name: signatures signatures_estimate_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.signatures
    ADD CONSTRAINT signatures_estimate_id_fkey FOREIGN KEY (estimate_id) REFERENCES public.estimates(id) ON DELETE CASCADE;


--
-- Name: signatures signatures_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.signatures
    ADD CONSTRAINT signatures_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: staff_invites staff_invites_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_invites
    ADD CONSTRAINT staff_invites_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);


--
-- Name: staff_users staff_users_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_users
    ADD CONSTRAINT staff_users_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);


--
-- Name: tenant_modules tenant_modules_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tenant_modules
    ADD CONSTRAINT tenant_modules_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: ticket_messages ticket_messages_ticket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ticket_messages
    ADD CONSTRAINT ticket_messages_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES public.tickets(id) ON DELETE CASCADE;


--
-- Name: tickets tickets_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: tracker_items tracker_items_assignee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tracker_items
    ADD CONSTRAINT tracker_items_assignee_id_fkey FOREIGN KEY (assignee_id) REFERENCES public.profiles(id);


--
-- Name: tracker_items tracker_items_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tracker_items
    ADD CONSTRAINT tracker_items_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);


--
-- Name: tracker_items tracker_items_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tracker_items
    ADD CONSTRAINT tracker_items_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: tracker_items tracker_items_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tracker_items
    ADD CONSTRAINT tracker_items_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.tracker_projects(id) ON DELETE CASCADE;


--
-- Name: tracker_items tracker_items_reported_by_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tracker_items
    ADD CONSTRAINT tracker_items_reported_by_org_id_fkey FOREIGN KEY (reported_by_org_id) REFERENCES public.organizations(id);


--
-- Name: tracker_items tracker_items_reported_by_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tracker_items
    ADD CONSTRAINT tracker_items_reported_by_profile_id_fkey FOREIGN KEY (reported_by_profile_id) REFERENCES public.profiles(id);


--
-- Name: tracker_projects tracker_projects_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tracker_projects
    ADD CONSTRAINT tracker_projects_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);


--
-- Name: tracker_projects tracker_projects_linked_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tracker_projects
    ADD CONSTRAINT tracker_projects_linked_org_id_fkey FOREIGN KEY (linked_org_id) REFERENCES public.organizations(id) ON DELETE SET NULL;


--
-- Name: tracker_projects tracker_projects_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tracker_projects
    ADD CONSTRAINT tracker_projects_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: wh_categories wh_categories_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_categories
    ADD CONSTRAINT wh_categories_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: wh_categories wh_categories_stage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_categories
    ADD CONSTRAINT wh_categories_stage_id_fkey FOREIGN KEY (stage_id) REFERENCES public.wh_stages(id);


--
-- Name: wh_categories wh_categories_system_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_categories
    ADD CONSTRAINT wh_categories_system_id_fkey FOREIGN KEY (system_id) REFERENCES public.wh_systems(id) ON DELETE CASCADE;


--
-- Name: wh_category_products wh_category_products_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_category_products
    ADD CONSTRAINT wh_category_products_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.wh_categories(id) ON DELETE CASCADE;


--
-- Name: wh_category_products wh_category_products_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_category_products
    ADD CONSTRAINT wh_category_products_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.wh_products(id) ON DELETE CASCADE;


--
-- Name: wh_colors wh_colors_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_colors
    ADD CONSTRAINT wh_colors_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: wh_drivers wh_drivers_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_drivers
    ADD CONSTRAINT wh_drivers_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: wh_order_line_items wh_order_line_items_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_order_line_items
    ADD CONSTRAINT wh_order_line_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.wh_orders(id) ON DELETE CASCADE;


--
-- Name: wh_order_line_items wh_order_line_items_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_order_line_items
    ADD CONSTRAINT wh_order_line_items_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: wh_orders wh_orders_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_orders
    ADD CONSTRAINT wh_orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: wh_orders wh_orders_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_orders
    ADD CONSTRAINT wh_orders_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: wh_price_history wh_price_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_price_history
    ADD CONSTRAINT wh_price_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES auth.users(id);


--
-- Name: wh_price_history wh_price_history_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_price_history
    ADD CONSTRAINT wh_price_history_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: wh_price_history wh_price_history_variation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_price_history
    ADD CONSTRAINT wh_price_history_variation_id_fkey FOREIGN KEY (variation_id) REFERENCES public.wh_product_variations(id) ON DELETE CASCADE;


--
-- Name: wh_product_colors wh_product_colors_color_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_product_colors
    ADD CONSTRAINT wh_product_colors_color_id_fkey FOREIGN KEY (color_id) REFERENCES public.wh_colors(id) ON DELETE CASCADE;


--
-- Name: wh_product_colors wh_product_colors_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_product_colors
    ADD CONSTRAINT wh_product_colors_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.wh_products(id) ON DELETE CASCADE;


--
-- Name: wh_product_families wh_product_families_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_product_families
    ADD CONSTRAINT wh_product_families_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: wh_product_families wh_product_families_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_product_families
    ADD CONSTRAINT wh_product_families_type_id_fkey FOREIGN KEY (type_id) REFERENCES public.wh_product_types(id);


--
-- Name: wh_product_roles wh_product_roles_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_product_roles
    ADD CONSTRAINT wh_product_roles_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: wh_product_roles wh_product_roles_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_product_roles
    ADD CONSTRAINT wh_product_roles_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.wh_products(id) ON DELETE SET NULL;


--
-- Name: wh_product_types wh_product_types_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_product_types
    ADD CONSTRAINT wh_product_types_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: wh_product_variations wh_product_variations_family_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_product_variations
    ADD CONSTRAINT wh_product_variations_family_id_fkey FOREIGN KEY (family_id) REFERENCES public.wh_product_families(id) ON DELETE CASCADE;


--
-- Name: wh_product_variations wh_product_variations_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_product_variations
    ADD CONSTRAINT wh_product_variations_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: wh_product_variations wh_product_variations_source_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_product_variations
    ADD CONSTRAINT wh_product_variations_source_product_id_fkey FOREIGN KEY (source_product_id) REFERENCES public.wh_products(id) ON DELETE SET NULL;


--
-- Name: wh_product_variations wh_product_variations_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_product_variations
    ADD CONSTRAINT wh_product_variations_type_id_fkey FOREIGN KEY (type_id) REFERENCES public.wh_product_types(id);


--
-- Name: wh_products wh_products_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_products
    ADD CONSTRAINT wh_products_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: wh_settings wh_settings_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_settings
    ADD CONSTRAINT wh_settings_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: wh_spec_files wh_spec_files_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_spec_files
    ADD CONSTRAINT wh_spec_files_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.wh_orders(id) ON DELETE CASCADE;


--
-- Name: wh_spec_files wh_spec_files_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_spec_files
    ADD CONSTRAINT wh_spec_files_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: wh_stages wh_stages_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_stages
    ADD CONSTRAINT wh_stages_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: wh_stages wh_stages_system_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_stages
    ADD CONSTRAINT wh_stages_system_id_fkey FOREIGN KEY (system_id) REFERENCES public.wh_systems(id) ON DELETE CASCADE;


--
-- Name: wh_systems wh_systems_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_systems
    ADD CONSTRAINT wh_systems_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: wh_team_members wh_team_members_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_team_members
    ADD CONSTRAINT wh_team_members_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: wh_team_members wh_team_members_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_team_members
    ADD CONSTRAINT wh_team_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: wh_variation_colors wh_variation_colors_color_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_variation_colors
    ADD CONSTRAINT wh_variation_colors_color_id_fkey FOREIGN KEY (color_id) REFERENCES public.wh_colors(id) ON DELETE CASCADE;


--
-- Name: wh_variation_colors wh_variation_colors_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_variation_colors
    ADD CONSTRAINT wh_variation_colors_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: wh_variation_colors wh_variation_colors_variation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wh_variation_colors
    ADD CONSTRAINT wh_variation_colors_variation_id_fkey FOREIGN KEY (variation_id) REFERENCES public.wh_product_variations(id) ON DELETE CASCADE;


--
-- Name: work_order_activity work_order_activity_work_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.work_order_activity
    ADD CONSTRAINT work_order_activity_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES public.work_orders(id) ON DELETE CASCADE;


--
-- Name: work_order_agreements work_order_agreements_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.work_order_agreements
    ADD CONSTRAINT work_order_agreements_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: work_order_agreements work_order_agreements_void_cascade_source_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.work_order_agreements
    ADD CONSTRAINT work_order_agreements_void_cascade_source_id_fkey FOREIGN KEY (void_cascade_source_id) REFERENCES public.work_orders(id);


--
-- Name: work_order_agreements work_order_agreements_work_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.work_order_agreements
    ADD CONSTRAINT work_order_agreements_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES public.work_orders(id) ON DELETE CASCADE;


--
-- Name: work_orders work_orders_estimate_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.work_orders
    ADD CONSTRAINT work_orders_estimate_id_fkey FOREIGN KEY (estimate_id) REFERENCES public.estimates(id);


--
-- Name: work_orders work_orders_job_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.work_orders
    ADD CONSTRAINT work_orders_job_id_fkey FOREIGN KEY (job_id) REFERENCES public.jobs(id);


--
-- Name: work_orders work_orders_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.work_orders
    ADD CONSTRAINT work_orders_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organizations(id);


--
-- Name: work_orders work_orders_predecessor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.work_orders
    ADD CONSTRAINT work_orders_predecessor_id_fkey FOREIGN KEY (predecessor_id) REFERENCES public.work_orders(id);


--
-- Name: work_orders work_orders_void_cascade_source_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.work_orders
    ADD CONSTRAINT work_orders_void_cascade_source_id_fkey FOREIGN KEY (void_cascade_source_id) REFERENCES public.work_orders(id);


--
-- Name: audit_leads Allow anon insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Allow anon insert" ON public.audit_leads FOR INSERT TO anon WITH CHECK (true);


--
-- Name: wh_categories Authenticated read wh_categories; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated read wh_categories" ON public.wh_categories FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: wh_category_products Authenticated read wh_category_products; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated read wh_category_products" ON public.wh_category_products FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: wh_colors Authenticated read wh_colors; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated read wh_colors" ON public.wh_colors FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: wh_product_colors Authenticated read wh_product_colors; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated read wh_product_colors" ON public.wh_product_colors FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: wh_products Authenticated read wh_products; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated read wh_products" ON public.wh_products FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: wh_stages Authenticated read wh_stages; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated read wh_stages" ON public.wh_stages FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: wh_systems Authenticated read wh_systems; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated read wh_systems" ON public.wh_systems FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: audit_leads; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.audit_leads ENABLE ROW LEVEL SECURITY;

--
-- Name: audits; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.audits ENABLE ROW LEVEL SECURITY;

--
-- Name: check_ins; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.check_ins ENABLE ROW LEVEL SECURITY;

--
-- Name: client_roadmaps; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.client_roadmaps ENABLE ROW LEVEL SECURITY;

--
-- Name: work_order_activity crew cannot reach master activity; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "crew cannot reach master activity" ON public.work_order_activity AS RESTRICTIVE USING (public.can_view_master_work_order(org_id));


--
-- Name: work_order_agreements crew cannot reach master agreements; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "crew cannot reach master agreements" ON public.work_order_agreements AS RESTRICTIVE USING (public.can_view_master_work_order(org_id)) WITH CHECK (public.can_view_master_work_order(org_id));


--
-- Name: work_orders crew cannot reach master work orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "crew cannot reach master work orders" ON public.work_orders AS RESTRICTIVE USING (((kind = 'trade'::text) OR public.can_view_master_work_order(org_id))) WITH CHECK (((kind = 'trade'::text) OR public.can_view_master_work_order(org_id)));


--
-- Name: deal_activity; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.deal_activity ENABLE ROW LEVEL SECURITY;

--
-- Name: deal_notes; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.deal_notes ENABLE ROW LEVEL SECURITY;

--
-- Name: deals; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.deals ENABLE ROW LEVEL SECURITY;

--
-- Name: engagement_checkins; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.engagement_checkins ENABLE ROW LEVEL SECURITY;

--
-- Name: engagement_levels; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.engagement_levels ENABLE ROW LEVEL SECURITY;

--
-- Name: engagement_milestones; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.engagement_milestones ENABLE ROW LEVEL SECURITY;

--
-- Name: engagements; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.engagements ENABLE ROW LEVEL SECURITY;

--
-- Name: estimate_line_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.estimate_line_items ENABLE ROW LEVEL SECURITY;

--
-- Name: estimate_number_counters; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.estimate_number_counters ENABLE ROW LEVEL SECURITY;

--
-- Name: estimates; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.estimates ENABLE ROW LEVEL SECURITY;

--
-- Name: follow_ups; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.follow_ups ENABLE ROW LEVEL SECURITY;

--
-- Name: client_roadmaps insert roadmap; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "insert roadmap" ON public.client_roadmaps FOR INSERT TO anon WITH CHECK (true);


--
-- Name: jobs; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.jobs ENABLE ROW LEVEL SECURITY;

--
-- Name: lead_activity; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.lead_activity ENABLE ROW LEVEL SECURITY;

--
-- Name: lead_appointments; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.lead_appointments ENABLE ROW LEVEL SECURITY;

--
-- Name: lead_notes; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.lead_notes ENABLE ROW LEVEL SECURITY;

--
-- Name: leads; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.leads ENABLE ROW LEVEL SECURITY;

--
-- Name: material_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.material_items ENABLE ROW LEVEL SECURITY;

--
-- Name: tickets member create tickets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member create tickets" ON public.tickets FOR INSERT TO authenticated WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: check_ins member delete own check_ins; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member delete own check_ins" ON public.check_ins FOR DELETE USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: estimate_line_items member delete own estimate_line_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member delete own estimate_line_items" ON public.estimate_line_items FOR DELETE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.has_capability(org_id, 'view_estimates'::text)));


--
-- Name: material_items member delete own material_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member delete own material_items" ON public.material_items FOR DELETE USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: production_packets member delete own production_packets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member delete own production_packets" ON public.production_packets FOR DELETE USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: schedule_blocks member delete own schedule_blocks; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member delete own schedule_blocks" ON public.schedule_blocks FOR DELETE USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: check_ins member insert own check_ins; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member insert own check_ins" ON public.check_ins FOR INSERT WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.work_order_is_my_trade(work_order_id)));


--
-- Name: deal_activity member insert own deal_activity; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member insert own deal_activity" ON public.deal_activity FOR INSERT WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: deal_notes member insert own deal_notes; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member insert own deal_notes" ON public.deal_notes FOR INSERT WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: deals member insert own deals; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member insert own deals" ON public.deals FOR INSERT WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: estimate_line_items member insert own estimate_line_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member insert own estimate_line_items" ON public.estimate_line_items FOR INSERT WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.has_capability(org_id, 'view_estimates'::text)));


--
-- Name: estimates member insert own estimates; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member insert own estimates" ON public.estimates FOR INSERT WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.has_capability(org_id, 'view_estimates'::text)));


--
-- Name: follow_ups member insert own follow_ups; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member insert own follow_ups" ON public.follow_ups FOR INSERT WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: jobs member insert own jobs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member insert own jobs" ON public.jobs FOR INSERT WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: material_items member insert own material_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member insert own material_items" ON public.material_items FOR INSERT WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.work_order_is_my_trade(work_order_id)));


--
-- Name: production_packets member insert own production_packets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member insert own production_packets" ON public.production_packets FOR INSERT WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.work_order_is_my_trade(work_order_id)));


--
-- Name: roadmap_items member insert own roadmap_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member insert own roadmap_items" ON public.roadmap_items FOR INSERT WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: roadmap_projects member insert own roadmap_projects; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member insert own roadmap_projects" ON public.roadmap_projects FOR INSERT WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: schedule_blocks member insert own schedule_blocks; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member insert own schedule_blocks" ON public.schedule_blocks FOR INSERT WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.work_order_is_my_trade(work_order_id)));


--
-- Name: signatures member insert own signatures; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member insert own signatures" ON public.signatures FOR INSERT WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.has_capability(org_id, 'view_estimates'::text)));


--
-- Name: tracker_items member insert own tracker_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member insert own tracker_items" ON public.tracker_items FOR INSERT WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: tracker_projects member insert own tracker_projects; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member insert own tracker_projects" ON public.tracker_projects FOR INSERT WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: work_order_agreements member insert own work_order_agreements; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member insert own work_order_agreements" ON public.work_order_agreements FOR INSERT WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: work_orders member insert own work_orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member insert own work_orders" ON public.work_orders FOR INSERT WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: ticket_messages member post ticket messages; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member post ticket messages" ON public.ticket_messages FOR INSERT TO authenticated WITH CHECK ((ticket_id IN ( SELECT tickets.id
   FROM public.tickets
  WHERE (tickets.org_id IN ( SELECT public.my_org_ids() AS my_org_ids)))));


--
-- Name: audit_leads member read own audit_leads; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own audit_leads" ON public.audit_leads FOR SELECT USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: check_ins member read own check_ins; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own check_ins" ON public.check_ins FOR SELECT USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: deal_activity member read own deal_activity; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own deal_activity" ON public.deal_activity FOR SELECT USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: deal_notes member read own deal_notes; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own deal_notes" ON public.deal_notes FOR SELECT USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: deals member read own deals; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own deals" ON public.deals FOR SELECT USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: engagement_checkins member read own engagement_checkins; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own engagement_checkins" ON public.engagement_checkins FOR SELECT TO authenticated USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: engagement_levels member read own engagement_levels; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own engagement_levels" ON public.engagement_levels FOR SELECT TO authenticated USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: engagement_milestones member read own engagement_milestones; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own engagement_milestones" ON public.engagement_milestones FOR SELECT TO authenticated USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: engagements member read own engagements; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own engagements" ON public.engagements FOR SELECT TO authenticated USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: estimate_line_items member read own estimate_line_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own estimate_line_items" ON public.estimate_line_items FOR SELECT USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.has_capability(org_id, 'view_estimates'::text)));


--
-- Name: estimates member read own estimates; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own estimates" ON public.estimates FOR SELECT USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.has_capability(org_id, 'view_estimates'::text)));


--
-- Name: follow_ups member read own follow_ups; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own follow_ups" ON public.follow_ups FOR SELECT USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: org_invoices member read own invoices; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own invoices" ON public.org_invoices FOR SELECT TO authenticated USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: jobs member read own jobs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own jobs" ON public.jobs FOR SELECT USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: material_items member read own material_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own material_items" ON public.material_items FOR SELECT USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: org_members member read own members; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own members" ON public.org_members FOR SELECT TO authenticated USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: organizations member read own org; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own org" ON public.organizations FOR SELECT TO authenticated USING ((id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: production_packets member read own production_packets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own production_packets" ON public.production_packets FOR SELECT USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: roadmap_items member read own roadmap_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own roadmap_items" ON public.roadmap_items FOR SELECT USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: roadmap_projects member read own roadmap_projects; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own roadmap_projects" ON public.roadmap_projects FOR SELECT USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: client_roadmaps member read own roadmaps; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own roadmaps" ON public.client_roadmaps FOR SELECT TO authenticated USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: schedule_blocks member read own schedule_blocks; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own schedule_blocks" ON public.schedule_blocks FOR SELECT USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: signatures member read own signatures; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own signatures" ON public.signatures FOR SELECT USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.has_capability(org_id, 'view_estimates'::text)));


--
-- Name: org_systems member read own systems; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own systems" ON public.org_systems FOR SELECT TO authenticated USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: tenant_modules member read own tenant_modules; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own tenant_modules" ON public.tenant_modules FOR SELECT USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: ticket_messages member read own ticket messages; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own ticket messages" ON public.ticket_messages FOR SELECT TO authenticated USING ((ticket_id IN ( SELECT tickets.id
   FROM public.tickets
  WHERE (tickets.org_id IN ( SELECT public.my_org_ids() AS my_org_ids)))));


--
-- Name: tickets member read own tickets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own tickets" ON public.tickets FOR SELECT TO authenticated USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: tracker_items member read own tracker_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own tracker_items" ON public.tracker_items FOR SELECT USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: tracker_projects member read own tracker_projects; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own tracker_projects" ON public.tracker_projects FOR SELECT USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: work_order_activity member read own work_order_activity; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own work_order_activity" ON public.work_order_activity FOR SELECT USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: work_order_agreements member read own work_order_agreements; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own work_order_agreements" ON public.work_order_agreements FOR SELECT USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: work_orders member read own work_orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member read own work_orders" ON public.work_orders FOR SELECT USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: check_ins member update own check_ins; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member update own check_ins" ON public.check_ins FOR UPDATE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.work_order_is_my_trade(work_order_id))) WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.work_order_is_my_trade(work_order_id)));


--
-- Name: engagement_milestones member update own client milestones; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member update own client milestones" ON public.engagement_milestones FOR UPDATE TO authenticated USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (owner = 'client'::text))) WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (owner = 'client'::text)));


--
-- Name: deal_notes member update own deal_notes; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member update own deal_notes" ON public.deal_notes FOR UPDATE USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids))) WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: deals member update own deals; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member update own deals" ON public.deals FOR UPDATE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.is_org_manager(org_id) OR (owner_id = auth.uid()) OR public.has_capability(org_id, 'edit_leads'::text)))) WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.is_org_manager(org_id) OR (owner_id = auth.uid()) OR public.has_capability(org_id, 'edit_leads'::text))));


--
-- Name: estimate_line_items member update own estimate_line_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member update own estimate_line_items" ON public.estimate_line_items FOR UPDATE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.has_capability(org_id, 'view_estimates'::text))) WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.has_capability(org_id, 'view_estimates'::text)));


--
-- Name: estimates member update own estimates; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member update own estimates" ON public.estimates FOR UPDATE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.has_capability(org_id, 'view_estimates'::text))) WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.has_capability(org_id, 'view_estimates'::text)));


--
-- Name: follow_ups member update own follow_ups; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member update own follow_ups" ON public.follow_ups FOR UPDATE USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids))) WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: jobs member update own jobs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member update own jobs" ON public.jobs FOR UPDATE USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids))) WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: material_items member update own material_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member update own material_items" ON public.material_items FOR UPDATE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.work_order_is_my_trade(work_order_id))) WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.work_order_is_my_trade(work_order_id)));


--
-- Name: production_packets member update own production_packets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member update own production_packets" ON public.production_packets FOR UPDATE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.work_order_is_my_trade(work_order_id))) WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.work_order_is_my_trade(work_order_id)));


--
-- Name: roadmap_items member update own roadmap_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member update own roadmap_items" ON public.roadmap_items FOR UPDATE USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids))) WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: roadmap_projects member update own roadmap_projects; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member update own roadmap_projects" ON public.roadmap_projects FOR UPDATE USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids))) WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: client_roadmaps member update own roadmaps; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member update own roadmaps" ON public.client_roadmaps FOR UPDATE TO authenticated USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids))) WITH CHECK (true);


--
-- Name: schedule_blocks member update own schedule_blocks; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member update own schedule_blocks" ON public.schedule_blocks FOR UPDATE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.work_order_is_my_trade(work_order_id))) WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND public.work_order_is_my_trade(work_order_id)));


--
-- Name: tracker_items member update own tracker_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member update own tracker_items" ON public.tracker_items FOR UPDATE USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids))) WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: tracker_projects member update own tracker_projects; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member update own tracker_projects" ON public.tracker_projects FOR UPDATE USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids))) WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: work_order_agreements member update own work_order_agreements; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member update own work_order_agreements" ON public.work_order_agreements FOR UPDATE USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids))) WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: work_orders member update own work_orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "member update own work_orders" ON public.work_orders FOR UPDATE USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids))) WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: migration_bmr_activity_raw; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.migration_bmr_activity_raw ENABLE ROW LEVEL SECURITY;

--
-- Name: migration_bmr_id_map; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.migration_bmr_id_map ENABLE ROW LEVEL SECURITY;

--
-- Name: migration_bmr_leads_raw; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.migration_bmr_leads_raw ENABLE ROW LEVEL SECURITY;

--
-- Name: migration_bmr_notes_raw; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.migration_bmr_notes_raw ENABLE ROW LEVEL SECURITY;

--
-- Name: migration_bmr_users_raw; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.migration_bmr_users_raw ENABLE ROW LEVEL SECURITY;

--
-- Name: deals no dollars in the field - deals; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "no dollars in the field - deals" ON public.deals AS RESTRICTIVE USING (public.can_view_financials(org_id)) WITH CHECK (public.can_view_financials(org_id));


--
-- Name: estimate_line_items no dollars in the field - estimate_line_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "no dollars in the field - estimate_line_items" ON public.estimate_line_items AS RESTRICTIVE USING (public.can_view_financials(org_id)) WITH CHECK (public.can_view_financials(org_id));


--
-- Name: estimates no dollars in the field - estimates; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "no dollars in the field - estimates" ON public.estimates AS RESTRICTIVE USING (public.can_view_financials(org_id)) WITH CHECK (public.can_view_financials(org_id));


--
-- Name: org_invites; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.org_invites ENABLE ROW LEVEL SECURITY;

--
-- Name: org_invoices; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.org_invoices ENABLE ROW LEVEL SECURITY;

--
-- Name: org_members; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.org_members ENABLE ROW LEVEL SECURITY;

--
-- Name: org_systems; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.org_systems ENABLE ROW LEVEL SECURITY;

--
-- Name: organizations; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

--
-- Name: pipeline_invites; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.pipeline_invites ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles pipeline_profiles_update_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY pipeline_profiles_update_own ON public.profiles FOR UPDATE TO authenticated USING ((id = auth.uid()));


--
-- Name: audits platform admin all audits; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "platform admin all audits" ON public.audits USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());


--
-- Name: proposals platform admin all proposals; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "platform admin all proposals" ON public.proposals USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());


--
-- Name: prospects platform admin all prospects; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "platform admin all prospects" ON public.prospects USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());


--
-- Name: tenant_modules platform admin manage tenant_modules; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "platform admin manage tenant_modules" ON public.tenant_modules USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());


--
-- Name: production_packets; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.production_packets ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles profiles_select_self_or_org; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY profiles_select_self_or_org ON public.profiles FOR SELECT USING (((id = auth.uid()) OR (id IN ( SELECT om.user_id
   FROM public.org_members om
  WHERE (om.org_id IN ( SELECT public.my_org_ids() AS my_org_ids))))));


--
-- Name: proposals; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.proposals ENABLE ROW LEVEL SECURITY;

--
-- Name: prospects; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.prospects ENABLE ROW LEVEL SECURITY;

--
-- Name: client_roadmaps read roadmap by token; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "read roadmap by token" ON public.client_roadmaps FOR SELECT USING (true);


--
-- Name: roadmap_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.roadmap_items ENABLE ROW LEVEL SECURITY;

--
-- Name: roadmap_projects; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.roadmap_projects ENABLE ROW LEVEL SECURITY;

--
-- Name: schedule_blocks; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.schedule_blocks ENABLE ROW LEVEL SECURITY;

--
-- Name: signatures; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.signatures ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_leads staff all audit_leads; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all audit_leads" ON public.audit_leads TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: deal_activity staff all deal_activity; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all deal_activity" ON public.deal_activity TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: deal_notes staff all deal_notes; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all deal_notes" ON public.deal_notes TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: deals staff all deals; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all deals" ON public.deals TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: engagement_checkins staff all engagement_checkins; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all engagement_checkins" ON public.engagement_checkins TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: engagement_levels staff all engagement_levels; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all engagement_levels" ON public.engagement_levels TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: engagement_milestones staff all engagement_milestones; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all engagement_milestones" ON public.engagement_milestones TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: engagements staff all engagements; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all engagements" ON public.engagements TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: follow_ups staff all follow_ups; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all follow_ups" ON public.follow_ups TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: lead_activity staff all lead_activity; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all lead_activity" ON public.lead_activity USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: lead_appointments staff all lead_appointments; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all lead_appointments" ON public.lead_appointments USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: lead_notes staff all lead_notes; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all lead_notes" ON public.lead_notes USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: leads staff all leads; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all leads" ON public.leads USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: org_invites staff all org_invites; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all org_invites" ON public.org_invites TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: org_invoices staff all org_invoices; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all org_invoices" ON public.org_invoices TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: org_members staff all org_members; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all org_members" ON public.org_members TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: org_systems staff all org_systems; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all org_systems" ON public.org_systems TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: organizations staff all organizations; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all organizations" ON public.organizations TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: pipeline_invites staff all pipeline_invites; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all pipeline_invites" ON public.pipeline_invites USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: staff_invites staff all staff_invites; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all staff_invites" ON public.staff_invites TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: staff_users staff all staff_users; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all staff_users" ON public.staff_users TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: ticket_messages staff all ticket_messages; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all ticket_messages" ON public.ticket_messages TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: tickets staff all tickets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "staff all tickets" ON public.tickets TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: staff_invites; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.staff_invites ENABLE ROW LEVEL SECURITY;

--
-- Name: staff_users; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.staff_users ENABLE ROW LEVEL SECURITY;

--
-- Name: structtech_state; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.structtech_state ENABLE ROW LEVEL SECURITY;

--
-- Name: tenant_modules; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.tenant_modules ENABLE ROW LEVEL SECURITY;

--
-- Name: tg_agenda_card; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.tg_agenda_card ENABLE ROW LEVEL SECURITY;

--
-- Name: tg_agenda_contact; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.tg_agenda_contact ENABLE ROW LEVEL SECURITY;

--
-- Name: tg_agenda_group; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.tg_agenda_group ENABLE ROW LEVEL SECURITY;

--
-- Name: tg_agenda_sender; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.tg_agenda_sender ENABLE ROW LEVEL SECURITY;

--
-- Name: tg_agenda_session; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.tg_agenda_session ENABLE ROW LEVEL SECURITY;

--
-- Name: tg_agenda_update; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.tg_agenda_update ENABLE ROW LEVEL SECURITY;

--
-- Name: ticket_messages; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.ticket_messages ENABLE ROW LEVEL SECURITY;

--
-- Name: tickets; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.tickets ENABLE ROW LEVEL SECURITY;

--
-- Name: tracker_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.tracker_items ENABLE ROW LEVEL SECURITY;

--
-- Name: tracker_projects; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.tracker_projects ENABLE ROW LEVEL SECURITY;

--
-- Name: client_roadmaps update roadmap milestones; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "update roadmap milestones" ON public.client_roadmaps FOR UPDATE USING (true) WITH CHECK (true);


--
-- Name: wh_categories; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.wh_categories ENABLE ROW LEVEL SECURITY;

--
-- Name: wh_categories wh_categories admin delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_categories admin delete" ON public.wh_categories FOR DELETE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = 'admin'::text)));


--
-- Name: wh_categories wh_categories anon read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_categories anon read" ON public.wh_categories FOR SELECT TO anon USING ((active = true));


--
-- Name: wh_categories wh_categories role insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_categories role insert" ON public.wh_categories FOR INSERT WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));


--
-- Name: wh_categories wh_categories role update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_categories role update" ON public.wh_categories FOR UPDATE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text])))) WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));


--
-- Name: wh_category_products; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.wh_category_products ENABLE ROW LEVEL SECURITY;

--
-- Name: wh_category_products wh_category_products anon read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_category_products anon read" ON public.wh_category_products FOR SELECT TO anon USING (true);


--
-- Name: wh_category_products wh_category_products org delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_category_products org delete" ON public.wh_category_products FOR DELETE TO authenticated USING ((category_id IN ( SELECT c.id
   FROM public.wh_categories c
  WHERE (c.org_id IN ( SELECT public.my_org_ids() AS my_org_ids)))));


--
-- Name: wh_category_products wh_category_products org insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_category_products org insert" ON public.wh_category_products FOR INSERT TO authenticated WITH CHECK ((category_id IN ( SELECT c.id
   FROM public.wh_categories c
  WHERE (c.org_id IN ( SELECT public.my_org_ids() AS my_org_ids)))));


--
-- Name: wh_category_products wh_category_products org update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_category_products org update" ON public.wh_category_products FOR UPDATE TO authenticated USING ((category_id IN ( SELECT c.id
   FROM public.wh_categories c
  WHERE (c.org_id IN ( SELECT public.my_org_ids() AS my_org_ids))))) WITH CHECK ((category_id IN ( SELECT c.id
   FROM public.wh_categories c
  WHERE (c.org_id IN ( SELECT public.my_org_ids() AS my_org_ids)))));


--
-- Name: wh_colors; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.wh_colors ENABLE ROW LEVEL SECURITY;

--
-- Name: wh_colors wh_colors admin delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_colors admin delete" ON public.wh_colors FOR DELETE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = 'admin'::text)));


--
-- Name: wh_colors wh_colors anon read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_colors anon read" ON public.wh_colors FOR SELECT TO anon USING ((active = true));


--
-- Name: wh_colors wh_colors role insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_colors role insert" ON public.wh_colors FOR INSERT WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));


--
-- Name: wh_colors wh_colors role update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_colors role update" ON public.wh_colors FOR UPDATE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text])))) WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));


--
-- Name: wh_drivers; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.wh_drivers ENABLE ROW LEVEL SECURITY;

--
-- Name: wh_drivers wh_drivers org all; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_drivers org all" ON public.wh_drivers TO authenticated USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids))) WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: wh_order_line_items wh_line_items org read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_line_items org read" ON public.wh_order_line_items FOR SELECT TO authenticated USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: wh_order_line_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.wh_order_line_items ENABLE ROW LEVEL SECURITY;

--
-- Name: wh_orders; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.wh_orders ENABLE ROW LEVEL SECURITY;

--
-- Name: wh_orders wh_orders org read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_orders org read" ON public.wh_orders FOR SELECT TO authenticated USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: wh_orders wh_orders org update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_orders org update" ON public.wh_orders FOR UPDATE TO authenticated USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids))) WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: wh_price_history; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.wh_price_history ENABLE ROW LEVEL SECURITY;

--
-- Name: wh_price_history wh_price_history admin delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_price_history admin delete" ON public.wh_price_history FOR DELETE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = 'admin'::text)));


--
-- Name: wh_price_history wh_price_history auth read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_price_history auth read" ON public.wh_price_history FOR SELECT USING (((auth.role() = 'authenticated'::text) AND (org_id IN ( SELECT public.my_org_ids() AS my_org_ids))));


--
-- Name: wh_price_history wh_price_history role insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_price_history role insert" ON public.wh_price_history FOR INSERT WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));


--
-- Name: wh_price_history wh_price_history role update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_price_history role update" ON public.wh_price_history FOR UPDATE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text])))) WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));


--
-- Name: wh_product_colors; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.wh_product_colors ENABLE ROW LEVEL SECURITY;

--
-- Name: wh_product_colors wh_product_colors anon read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_colors anon read" ON public.wh_product_colors FOR SELECT TO anon USING (true);


--
-- Name: wh_product_colors wh_product_colors org delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_colors org delete" ON public.wh_product_colors FOR DELETE TO authenticated USING ((product_id IN ( SELECT p.id
   FROM public.wh_products p
  WHERE (p.org_id IN ( SELECT public.my_org_ids() AS my_org_ids)))));


--
-- Name: wh_product_colors wh_product_colors org insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_colors org insert" ON public.wh_product_colors FOR INSERT TO authenticated WITH CHECK ((product_id IN ( SELECT p.id
   FROM public.wh_products p
  WHERE (p.org_id IN ( SELECT public.my_org_ids() AS my_org_ids)))));


--
-- Name: wh_product_colors wh_product_colors org update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_colors org update" ON public.wh_product_colors FOR UPDATE TO authenticated USING ((product_id IN ( SELECT p.id
   FROM public.wh_products p
  WHERE (p.org_id IN ( SELECT public.my_org_ids() AS my_org_ids))))) WITH CHECK ((product_id IN ( SELECT p.id
   FROM public.wh_products p
  WHERE (p.org_id IN ( SELECT public.my_org_ids() AS my_org_ids)))));


--
-- Name: wh_product_families; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.wh_product_families ENABLE ROW LEVEL SECURITY;

--
-- Name: wh_product_families wh_product_families admin delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_families admin delete" ON public.wh_product_families FOR DELETE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = 'admin'::text)));


--
-- Name: wh_product_families wh_product_families anon read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_families anon read" ON public.wh_product_families FOR SELECT TO anon USING ((status = 'live'::text));


--
-- Name: wh_product_families wh_product_families auth read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_families auth read" ON public.wh_product_families FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: wh_product_families wh_product_families role insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_families role insert" ON public.wh_product_families FOR INSERT WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));


--
-- Name: wh_product_families wh_product_families role update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_families role update" ON public.wh_product_families FOR UPDATE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text])))) WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));


--
-- Name: wh_product_roles; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.wh_product_roles ENABLE ROW LEVEL SECURITY;

--
-- Name: wh_product_roles wh_product_roles admin delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_roles admin delete" ON public.wh_product_roles FOR DELETE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = 'admin'::text)));


--
-- Name: wh_product_roles wh_product_roles anon read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_roles anon read" ON public.wh_product_roles FOR SELECT TO anon USING (true);


--
-- Name: wh_product_roles wh_product_roles auth read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_roles auth read" ON public.wh_product_roles FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: wh_product_roles wh_product_roles role insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_roles role insert" ON public.wh_product_roles FOR INSERT WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));


--
-- Name: wh_product_roles wh_product_roles role update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_roles role update" ON public.wh_product_roles FOR UPDATE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text])))) WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));


--
-- Name: wh_product_types; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.wh_product_types ENABLE ROW LEVEL SECURITY;

--
-- Name: wh_product_types wh_product_types admin delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_types admin delete" ON public.wh_product_types FOR DELETE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = 'admin'::text)));


--
-- Name: wh_product_types wh_product_types anon read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_types anon read" ON public.wh_product_types FOR SELECT TO anon USING (true);


--
-- Name: wh_product_types wh_product_types auth read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_types auth read" ON public.wh_product_types FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: wh_product_types wh_product_types role insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_types role insert" ON public.wh_product_types FOR INSERT WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));


--
-- Name: wh_product_types wh_product_types role update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_types role update" ON public.wh_product_types FOR UPDATE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text])))) WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));


--
-- Name: wh_product_variations; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.wh_product_variations ENABLE ROW LEVEL SECURITY;

--
-- Name: wh_product_variations wh_product_variations admin delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_variations admin delete" ON public.wh_product_variations FOR DELETE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = 'admin'::text)));


--
-- Name: wh_product_variations wh_product_variations anon read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_variations anon read" ON public.wh_product_variations FOR SELECT TO anon USING ((status = 'live'::text));


--
-- Name: wh_product_variations wh_product_variations auth read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_variations auth read" ON public.wh_product_variations FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: wh_product_variations wh_product_variations role insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_variations role insert" ON public.wh_product_variations FOR INSERT WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));


--
-- Name: wh_product_variations wh_product_variations role update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_product_variations role update" ON public.wh_product_variations FOR UPDATE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text])))) WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));


--
-- Name: wh_products; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.wh_products ENABLE ROW LEVEL SECURITY;

--
-- Name: wh_products wh_products admin delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_products admin delete" ON public.wh_products FOR DELETE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = 'admin'::text)));


--
-- Name: wh_products wh_products anon read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_products anon read" ON public.wh_products FOR SELECT TO anon USING ((active = true));


--
-- Name: wh_products wh_products role insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_products role insert" ON public.wh_products FOR INSERT WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));


--
-- Name: wh_products wh_products role update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_products role update" ON public.wh_products FOR UPDATE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text])))) WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));


--
-- Name: wh_settings; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.wh_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: wh_settings wh_settings anon read whitelist; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_settings anon read whitelist" ON public.wh_settings FOR SELECT TO anon USING (((org_id = '1084baa8-0355-4298-9b98-b876a7581173'::uuid) AND (key = ANY (ARRAY['stripe_publishable_key'::text, 'maintenance_mode'::text]))));


--
-- Name: wh_settings wh_settings org all; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_settings org all" ON public.wh_settings TO authenticated USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids))) WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: wh_spec_files; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.wh_spec_files ENABLE ROW LEVEL SECURITY;

--
-- Name: wh_spec_files wh_spec_files org read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_spec_files org read" ON public.wh_spec_files FOR SELECT TO authenticated USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: wh_stages; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.wh_stages ENABLE ROW LEVEL SECURITY;

--
-- Name: wh_stages wh_stages anon read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_stages anon read" ON public.wh_stages FOR SELECT TO anon USING ((active = true));


--
-- Name: wh_stages wh_stages org delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_stages org delete" ON public.wh_stages FOR DELETE TO authenticated USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: wh_stages wh_stages org insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_stages org insert" ON public.wh_stages FOR INSERT TO authenticated WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: wh_stages wh_stages org update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_stages org update" ON public.wh_stages FOR UPDATE TO authenticated USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids))) WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: wh_systems; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.wh_systems ENABLE ROW LEVEL SECURITY;

--
-- Name: wh_systems wh_systems anon read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_systems anon read" ON public.wh_systems FOR SELECT TO anon USING ((active = true));


--
-- Name: wh_systems wh_systems org delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_systems org delete" ON public.wh_systems FOR DELETE TO authenticated USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: wh_systems wh_systems org insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_systems org insert" ON public.wh_systems FOR INSERT TO authenticated WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: wh_systems wh_systems org update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_systems org update" ON public.wh_systems FOR UPDATE TO authenticated USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids))) WITH CHECK ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: wh_team_members; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.wh_team_members ENABLE ROW LEVEL SECURITY;

--
-- Name: wh_team_members wh_team_members admin delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_team_members admin delete" ON public.wh_team_members FOR DELETE TO authenticated USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = 'admin'::text)));


--
-- Name: wh_team_members wh_team_members admin insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_team_members admin insert" ON public.wh_team_members FOR INSERT TO authenticated WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = 'admin'::text)));


--
-- Name: wh_team_members wh_team_members admin update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_team_members admin update" ON public.wh_team_members FOR UPDATE TO authenticated USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = 'admin'::text))) WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = 'admin'::text)));


--
-- Name: wh_team_members wh_team_members org read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_team_members org read" ON public.wh_team_members FOR SELECT TO authenticated USING ((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)));


--
-- Name: wh_variation_colors; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.wh_variation_colors ENABLE ROW LEVEL SECURITY;

--
-- Name: wh_variation_colors wh_variation_colors admin delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_variation_colors admin delete" ON public.wh_variation_colors FOR DELETE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = 'admin'::text)));


--
-- Name: wh_variation_colors wh_variation_colors anon read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_variation_colors anon read" ON public.wh_variation_colors FOR SELECT TO anon USING (true);


--
-- Name: wh_variation_colors wh_variation_colors auth read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_variation_colors auth read" ON public.wh_variation_colors FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: wh_variation_colors wh_variation_colors role insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_variation_colors role insert" ON public.wh_variation_colors FOR INSERT WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));


--
-- Name: wh_variation_colors wh_variation_colors role update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wh_variation_colors role update" ON public.wh_variation_colors FOR UPDATE USING (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text])))) WITH CHECK (((org_id IN ( SELECT public.my_org_ids() AS my_org_ids)) AND (public.my_wh_role() = ANY (ARRAY['admin'::text, 'assistant'::text]))));


--
-- Name: work_order_activity; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.work_order_activity ENABLE ROW LEVEL SECURITY;

--
-- Name: work_order_agreements; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.work_order_agreements ENABLE ROW LEVEL SECURITY;

--
-- Name: work_orders; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.work_orders ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION accept_invite(p_token text, p_full_name text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.accept_invite(p_token text, p_full_name text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.accept_invite(p_token text, p_full_name text) TO authenticated;
GRANT ALL ON FUNCTION public.accept_invite(p_token text, p_full_name text) TO service_role;


--
-- Name: FUNCTION accept_pipeline_invite(p_token text, p_full_name text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.accept_pipeline_invite(p_token text, p_full_name text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.accept_pipeline_invite(p_token text, p_full_name text) TO authenticated;
GRANT ALL ON FUNCTION public.accept_pipeline_invite(p_token text, p_full_name text) TO service_role;


--
-- Name: FUNCTION accept_staff_invite(p_token text, p_full_name text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.accept_staff_invite(p_token text, p_full_name text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.accept_staff_invite(p_token text, p_full_name text) TO authenticated;
GRANT ALL ON FUNCTION public.accept_staff_invite(p_token text, p_full_name text) TO service_role;


--
-- Name: FUNCTION add_check_in_photo(p_check_in_id uuid, p_photo_data_url text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.add_check_in_photo(p_check_in_id uuid, p_photo_data_url text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.add_check_in_photo(p_check_in_id uuid, p_photo_data_url text) TO authenticated;
GRANT ALL ON FUNCTION public.add_check_in_photo(p_check_in_id uuid, p_photo_data_url text) TO service_role;


--
-- Name: FUNCTION add_deal_note(p_deal_id uuid, p_content text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.add_deal_note(p_deal_id uuid, p_content text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.add_deal_note(p_deal_id uuid, p_content text) TO authenticated;
GRANT ALL ON FUNCTION public.add_deal_note(p_deal_id uuid, p_content text) TO service_role;


--
-- Name: FUNCTION add_estimate_line_item(p_estimate_id uuid, p_description text, p_quantity numeric, p_unit_price numeric, p_product_id uuid, p_sort_order integer, p_unit text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.add_estimate_line_item(p_estimate_id uuid, p_description text, p_quantity numeric, p_unit_price numeric, p_product_id uuid, p_sort_order integer, p_unit text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.add_estimate_line_item(p_estimate_id uuid, p_description text, p_quantity numeric, p_unit_price numeric, p_product_id uuid, p_sort_order integer, p_unit text) TO authenticated;
GRANT ALL ON FUNCTION public.add_estimate_line_item(p_estimate_id uuid, p_description text, p_quantity numeric, p_unit_price numeric, p_product_id uuid, p_sort_order integer, p_unit text) TO service_role;


--
-- Name: FUNCTION add_material_item(p_work_order_id uuid, p_name text, p_quantity numeric, p_ready_by date, p_sort_order integer); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.add_material_item(p_work_order_id uuid, p_name text, p_quantity numeric, p_ready_by date, p_sort_order integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.add_material_item(p_work_order_id uuid, p_name text, p_quantity numeric, p_ready_by date, p_sort_order integer) TO authenticated;
GRANT ALL ON FUNCTION public.add_material_item(p_work_order_id uuid, p_name text, p_quantity numeric, p_ready_by date, p_sort_order integer) TO service_role;


--
-- Name: FUNCTION add_org_member(p_org_id uuid, p_user_id uuid, p_role text, p_full_name text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.add_org_member(p_org_id uuid, p_user_id uuid, p_role text, p_full_name text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.add_org_member(p_org_id uuid, p_user_id uuid, p_role text, p_full_name text) TO authenticated;
GRANT ALL ON FUNCTION public.add_org_member(p_org_id uuid, p_user_id uuid, p_role text, p_full_name text) TO service_role;


--
-- Name: FUNCTION add_production_packet_callout(p_production_packet_id uuid, p_label text, p_detail text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.add_production_packet_callout(p_production_packet_id uuid, p_label text, p_detail text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.add_production_packet_callout(p_production_packet_id uuid, p_label text, p_detail text) TO authenticated;
GRANT ALL ON FUNCTION public.add_production_packet_callout(p_production_packet_id uuid, p_label text, p_detail text) TO service_role;


--
-- Name: FUNCTION add_schedule_block(p_work_order_id uuid, p_crew_name text, p_start_date date, p_end_date date); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.add_schedule_block(p_work_order_id uuid, p_crew_name text, p_start_date date, p_end_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.add_schedule_block(p_work_order_id uuid, p_crew_name text, p_start_date date, p_end_date date) TO authenticated;
GRANT ALL ON FUNCTION public.add_schedule_block(p_work_order_id uuid, p_crew_name text, p_start_date date, p_end_date date) TO service_role;


--
-- Name: FUNCTION archive_deal(p_deal_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.archive_deal(p_deal_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.archive_deal(p_deal_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.archive_deal(p_deal_id uuid) TO service_role;


--
-- Name: FUNCTION archive_tracker_item(p_item_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.archive_tracker_item(p_item_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.archive_tracker_item(p_item_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.archive_tracker_item(p_item_id uuid) TO service_role;


--
-- Name: FUNCTION archive_tracker_project(p_project_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.archive_tracker_project(p_project_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.archive_tracker_project(p_project_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.archive_tracker_project(p_project_id uuid) TO service_role;


--
-- Name: FUNCTION assert_work_order_level(p_work_order_id uuid, p_expected_kind text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.assert_work_order_level(p_work_order_id uuid, p_expected_kind text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assert_work_order_level(p_work_order_id uuid, p_expected_kind text) TO service_role;


--
-- Name: FUNCTION assign_deal_owner(p_deal_id uuid, p_owner_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.assign_deal_owner(p_deal_id uuid, p_owner_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assign_deal_owner(p_deal_id uuid, p_owner_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.assign_deal_owner(p_deal_id uuid, p_owner_id uuid) TO service_role;


--
-- Name: FUNCTION auto_create_deal(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.auto_create_deal() FROM PUBLIC;
GRANT ALL ON FUNCTION public.auto_create_deal() TO authenticated;
GRANT ALL ON FUNCTION public.auto_create_deal() TO service_role;


--
-- Name: FUNCTION auto_create_roadmap(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.auto_create_roadmap() FROM PUBLIC;
GRANT ALL ON FUNCTION public.auto_create_roadmap() TO authenticated;
GRANT ALL ON FUNCTION public.auto_create_roadmap() TO service_role;


--
-- Name: FUNCTION bmr_ticket_touch(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.bmr_ticket_touch() TO anon;
GRANT ALL ON FUNCTION public.bmr_ticket_touch() TO authenticated;
GRANT ALL ON FUNCTION public.bmr_ticket_touch() TO service_role;


--
-- Name: FUNCTION build_roadmap_levels(p_answers jsonb, p_crew integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.build_roadmap_levels(p_answers jsonb, p_crew integer) TO anon;
GRANT ALL ON FUNCTION public.build_roadmap_levels(p_answers jsonb, p_crew integer) TO authenticated;
GRANT ALL ON FUNCTION public.build_roadmap_levels(p_answers jsonb, p_crew integer) TO service_role;


--
-- Name: FUNCTION can_view_financials(p_org_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.can_view_financials(p_org_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.can_view_financials(p_org_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.can_view_financials(p_org_id uuid) TO service_role;


--
-- Name: FUNCTION can_view_master_work_order(p_org_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.can_view_master_work_order(p_org_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.can_view_master_work_order(p_org_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.can_view_master_work_order(p_org_id uuid) TO service_role;


--
-- Name: FUNCTION complete_site_survey(p_deal_id uuid, p_completed_at timestamp with time zone); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.complete_site_survey(p_deal_id uuid, p_completed_at timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.complete_site_survey(p_deal_id uuid, p_completed_at timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION public.complete_site_survey(p_deal_id uuid, p_completed_at timestamp with time zone) TO service_role;


--
-- Name: FUNCTION create_check_in(p_work_order_id uuid, p_crew_name text, p_schedule_block_id uuid, p_check_in_date date, p_hours numeric, p_materials_used text, p_blockers text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.create_check_in(p_work_order_id uuid, p_crew_name text, p_schedule_block_id uuid, p_check_in_date date, p_hours numeric, p_materials_used text, p_blockers text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_check_in(p_work_order_id uuid, p_crew_name text, p_schedule_block_id uuid, p_check_in_date date, p_hours numeric, p_materials_used text, p_blockers text) TO authenticated;
GRANT ALL ON FUNCTION public.create_check_in(p_work_order_id uuid, p_crew_name text, p_schedule_block_id uuid, p_check_in_date date, p_hours numeric, p_materials_used text, p_blockers text) TO service_role;


--
-- Name: FUNCTION create_deal(p_org_id uuid, p_contact_name text, p_company text, p_email text, p_phone text, p_value numeric, p_trade text, p_crew_size integer, p_source text, p_lead_type text, p_project_address text, p_billing_address text, p_first_name text, p_last_name text, p_secondary_phone text, p_remodel_or_new_construction text, p_existing_roof_type text[], p_roof_type_requested text[], p_service_address_street text, p_service_address_city text, p_service_address_state text, p_service_address_zip text, p_referral_name text, p_owner_id uuid, p_tags text[]); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.create_deal(p_org_id uuid, p_contact_name text, p_company text, p_email text, p_phone text, p_value numeric, p_trade text, p_crew_size integer, p_source text, p_lead_type text, p_project_address text, p_billing_address text, p_first_name text, p_last_name text, p_secondary_phone text, p_remodel_or_new_construction text, p_existing_roof_type text[], p_roof_type_requested text[], p_service_address_street text, p_service_address_city text, p_service_address_state text, p_service_address_zip text, p_referral_name text, p_owner_id uuid, p_tags text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_deal(p_org_id uuid, p_contact_name text, p_company text, p_email text, p_phone text, p_value numeric, p_trade text, p_crew_size integer, p_source text, p_lead_type text, p_project_address text, p_billing_address text, p_first_name text, p_last_name text, p_secondary_phone text, p_remodel_or_new_construction text, p_existing_roof_type text[], p_roof_type_requested text[], p_service_address_street text, p_service_address_city text, p_service_address_state text, p_service_address_zip text, p_referral_name text, p_owner_id uuid, p_tags text[]) TO authenticated;
GRANT ALL ON FUNCTION public.create_deal(p_org_id uuid, p_contact_name text, p_company text, p_email text, p_phone text, p_value numeric, p_trade text, p_crew_size integer, p_source text, p_lead_type text, p_project_address text, p_billing_address text, p_first_name text, p_last_name text, p_secondary_phone text, p_remodel_or_new_construction text, p_existing_roof_type text[], p_roof_type_requested text[], p_service_address_street text, p_service_address_city text, p_service_address_state text, p_service_address_zip text, p_referral_name text, p_owner_id uuid, p_tags text[]) TO service_role;


--
-- Name: FUNCTION create_engagement_from_roadmap(p_deal_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.create_engagement_from_roadmap(p_deal_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_engagement_from_roadmap(p_deal_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.create_engagement_from_roadmap(p_deal_id uuid) TO service_role;


--
-- Name: FUNCTION create_estimate_from_deal(p_deal_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.create_estimate_from_deal(p_deal_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_estimate_from_deal(p_deal_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.create_estimate_from_deal(p_deal_id uuid) TO service_role;


--
-- Name: FUNCTION create_job_from_estimate(p_estimate_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.create_job_from_estimate(p_estimate_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_job_from_estimate(p_estimate_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.create_job_from_estimate(p_estimate_id uuid) TO service_role;


--
-- Name: FUNCTION create_organization(p_name text, p_tenant_type text, p_trade text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.create_organization(p_name text, p_tenant_type text, p_trade text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_organization(p_name text, p_tenant_type text, p_trade text) TO authenticated;
GRANT ALL ON FUNCTION public.create_organization(p_name text, p_tenant_type text, p_trade text) TO service_role;


--
-- Name: FUNCTION create_roadmap_item(p_org_id uuid, p_project_id uuid, p_phase text, p_section text, p_feature text, p_status text, p_notes text, p_sort_order integer); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.create_roadmap_item(p_org_id uuid, p_project_id uuid, p_phase text, p_section text, p_feature text, p_status text, p_notes text, p_sort_order integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_roadmap_item(p_org_id uuid, p_project_id uuid, p_phase text, p_section text, p_feature text, p_status text, p_notes text, p_sort_order integer) TO authenticated;
GRANT ALL ON FUNCTION public.create_roadmap_item(p_org_id uuid, p_project_id uuid, p_phase text, p_section text, p_feature text, p_status text, p_notes text, p_sort_order integer) TO service_role;


--
-- Name: FUNCTION create_roadmap_project(p_org_id uuid, p_key text, p_name text, p_sort_order integer); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.create_roadmap_project(p_org_id uuid, p_key text, p_name text, p_sort_order integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_roadmap_project(p_org_id uuid, p_key text, p_name text, p_sort_order integer) TO authenticated;
GRANT ALL ON FUNCTION public.create_roadmap_project(p_org_id uuid, p_key text, p_name text, p_sort_order integer) TO service_role;


--
-- Name: FUNCTION create_tracker_item(p_org_id uuid, p_project_id uuid, p_title text, p_type text, p_priority text, p_description text, p_status text, p_assignee_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.create_tracker_item(p_org_id uuid, p_project_id uuid, p_title text, p_type text, p_priority text, p_description text, p_status text, p_assignee_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_tracker_item(p_org_id uuid, p_project_id uuid, p_title text, p_type text, p_priority text, p_description text, p_status text, p_assignee_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.create_tracker_item(p_org_id uuid, p_project_id uuid, p_title text, p_type text, p_priority text, p_description text, p_status text, p_assignee_id uuid) TO service_role;


--
-- Name: FUNCTION create_tracker_project(p_org_id uuid, p_name text, p_description text, p_linked_org_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.create_tracker_project(p_org_id uuid, p_name text, p_description text, p_linked_org_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_tracker_project(p_org_id uuid, p_name text, p_description text, p_linked_org_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.create_tracker_project(p_org_id uuid, p_name text, p_description text, p_linked_org_id uuid) TO service_role;


--
-- Name: FUNCTION create_trade_work_order(p_master_work_order_id uuid, p_trade text, p_assignee_type text, p_assignee_ref text, p_predecessor_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.create_trade_work_order(p_master_work_order_id uuid, p_trade text, p_assignee_type text, p_assignee_ref text, p_predecessor_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_trade_work_order(p_master_work_order_id uuid, p_trade text, p_assignee_type text, p_assignee_ref text, p_predecessor_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.create_trade_work_order(p_master_work_order_id uuid, p_trade text, p_assignee_type text, p_assignee_ref text, p_predecessor_id uuid) TO service_role;


--
-- Name: FUNCTION create_wh_order(p_order jsonb, p_line_items jsonb, p_spec_files jsonb, p_org_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.create_wh_order(p_order jsonb, p_line_items jsonb, p_spec_files jsonb, p_org_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_wh_order(p_order jsonb, p_line_items jsonb, p_spec_files jsonb, p_org_id uuid) TO anon;
GRANT ALL ON FUNCTION public.create_wh_order(p_order jsonb, p_line_items jsonb, p_spec_files jsonb, p_org_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.create_wh_order(p_order jsonb, p_line_items jsonb, p_spec_files jsonb, p_org_id uuid) TO service_role;


--
-- Name: FUNCTION create_work_order_agreement(p_work_order_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.create_work_order_agreement(p_work_order_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_work_order_agreement(p_work_order_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.create_work_order_agreement(p_work_order_id uuid) TO service_role;


--
-- Name: FUNCTION crm_follow_up_cadence_days(p_org_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.crm_follow_up_cadence_days(p_org_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.crm_follow_up_cadence_days(p_org_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.crm_follow_up_cadence_days(p_org_id uuid) TO service_role;


--
-- Name: FUNCTION crm_stage_config(p_org_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.crm_stage_config(p_org_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.crm_stage_config(p_org_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.crm_stage_config(p_org_id uuid) TO service_role;


--
-- Name: FUNCTION crm_stage_entry(p_org_id uuid, p_stage_key text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.crm_stage_entry(p_org_id uuid, p_stage_key text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.crm_stage_entry(p_org_id uuid, p_stage_key text) TO authenticated;
GRANT ALL ON FUNCTION public.crm_stage_entry(p_org_id uuid, p_stage_key text) TO service_role;


--
-- Name: FUNCTION deal_stage_side_effects(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.deal_stage_side_effects() FROM PUBLIC;
GRANT ALL ON FUNCTION public.deal_stage_side_effects() TO authenticated;
GRANT ALL ON FUNCTION public.deal_stage_side_effects() TO service_role;


--
-- Name: FUNCTION delete_check_in(p_check_in_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.delete_check_in(p_check_in_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_check_in(p_check_in_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_check_in(p_check_in_id uuid) TO service_role;


--
-- Name: FUNCTION delete_estimate(p_estimate_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.delete_estimate(p_estimate_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_estimate(p_estimate_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_estimate(p_estimate_id uuid) TO service_role;


--
-- Name: FUNCTION delete_estimate_line_item(p_line_item_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.delete_estimate_line_item(p_line_item_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_estimate_line_item(p_line_item_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_estimate_line_item(p_line_item_id uuid) TO service_role;


--
-- Name: FUNCTION delete_material_item(p_material_item_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.delete_material_item(p_material_item_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_material_item(p_material_item_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_material_item(p_material_item_id uuid) TO service_role;


--
-- Name: FUNCTION delete_production_packet(p_production_packet_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.delete_production_packet(p_production_packet_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_production_packet(p_production_packet_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_production_packet(p_production_packet_id uuid) TO service_role;


--
-- Name: FUNCTION delete_production_packet_callout(p_production_packet_id uuid, p_callout_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.delete_production_packet_callout(p_production_packet_id uuid, p_callout_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_production_packet_callout(p_production_packet_id uuid, p_callout_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_production_packet_callout(p_production_packet_id uuid, p_callout_id uuid) TO service_role;


--
-- Name: FUNCTION delete_roadmap_item(p_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.delete_roadmap_item(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_roadmap_item(p_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_roadmap_item(p_id uuid) TO service_role;


--
-- Name: FUNCTION delete_roadmap_project(p_project_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.delete_roadmap_project(p_project_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_roadmap_project(p_project_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_roadmap_project(p_project_id uuid) TO service_role;


--
-- Name: FUNCTION delete_schedule_block(p_schedule_block_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.delete_schedule_block(p_schedule_block_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_schedule_block(p_schedule_block_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_schedule_block(p_schedule_block_id uuid) TO service_role;


--
-- Name: FUNCTION delete_tracker_item(p_item_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.delete_tracker_item(p_item_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_tracker_item(p_item_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_tracker_item(p_item_id uuid) TO service_role;


--
-- Name: FUNCTION delete_tracker_project(p_project_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.delete_tracker_project(p_project_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_tracker_project(p_project_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_tracker_project(p_project_id uuid) TO service_role;


--
-- Name: FUNCTION delete_work_order(p_work_order_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.delete_work_order(p_work_order_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_work_order(p_work_order_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_work_order(p_work_order_id uuid) TO service_role;


--
-- Name: FUNCTION derive_level_status(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.derive_level_status() FROM PUBLIC;
GRANT ALL ON FUNCTION public.derive_level_status() TO authenticated;
GRANT ALL ON FUNCTION public.derive_level_status() TO service_role;


--
-- Name: FUNCTION estimate_line_items_sync_subtotal(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.estimate_line_items_sync_subtotal() FROM PUBLIC;
GRANT ALL ON FUNCTION public.estimate_line_items_sync_subtotal() TO authenticated;
GRANT ALL ON FUNCTION public.estimate_line_items_sync_subtotal() TO service_role;


--
-- Name: TABLE check_ins; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.check_ins TO anon;
GRANT ALL ON TABLE public.check_ins TO authenticated;
GRANT ALL ON TABLE public.check_ins TO service_role;


--
-- Name: FUNCTION fetch_check_in(p_check_in_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.fetch_check_in(p_check_in_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.fetch_check_in(p_check_in_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.fetch_check_in(p_check_in_id uuid) TO service_role;


--
-- Name: TABLE deals; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.deals TO anon;
GRANT ALL ON TABLE public.deals TO authenticated;
GRANT ALL ON TABLE public.deals TO service_role;


--
-- Name: FUNCTION fetch_deal(p_deal_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.fetch_deal(p_deal_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.fetch_deal(p_deal_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.fetch_deal(p_deal_id uuid) TO service_role;


--
-- Name: TABLE estimates; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.estimates TO anon;
GRANT ALL ON TABLE public.estimates TO authenticated;
GRANT ALL ON TABLE public.estimates TO service_role;


--
-- Name: FUNCTION fetch_estimate(p_estimate_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.fetch_estimate(p_estimate_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.fetch_estimate(p_estimate_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.fetch_estimate(p_estimate_id uuid) TO service_role;


--
-- Name: FUNCTION fetch_field_jobs(p_org_id uuid, p_today date); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.fetch_field_jobs(p_org_id uuid, p_today date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.fetch_field_jobs(p_org_id uuid, p_today date) TO authenticated;
GRANT ALL ON FUNCTION public.fetch_field_jobs(p_org_id uuid, p_today date) TO service_role;


--
-- Name: FUNCTION fetch_membership_context(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.fetch_membership_context() FROM PUBLIC;
GRANT ALL ON FUNCTION public.fetch_membership_context() TO authenticated;
GRANT ALL ON FUNCTION public.fetch_membership_context() TO service_role;


--
-- Name: TABLE organizations; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.organizations TO anon;
GRANT ALL ON TABLE public.organizations TO authenticated;
GRANT ALL ON TABLE public.organizations TO service_role;


--
-- Name: FUNCTION fetch_organization(p_org_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.fetch_organization(p_org_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.fetch_organization(p_org_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.fetch_organization(p_org_id uuid) TO service_role;


--
-- Name: TABLE production_packets; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.production_packets TO anon;
GRANT ALL ON TABLE public.production_packets TO authenticated;
GRANT ALL ON TABLE public.production_packets TO service_role;


--
-- Name: FUNCTION fetch_production_packet(p_production_packet_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.fetch_production_packet(p_production_packet_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.fetch_production_packet(p_production_packet_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.fetch_production_packet(p_production_packet_id uuid) TO service_role;


--
-- Name: TABLE tracker_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tracker_items TO anon;
GRANT ALL ON TABLE public.tracker_items TO authenticated;
GRANT ALL ON TABLE public.tracker_items TO service_role;


--
-- Name: FUNCTION fetch_tracker_item(p_item_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.fetch_tracker_item(p_item_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.fetch_tracker_item(p_item_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.fetch_tracker_item(p_item_id uuid) TO service_role;


--
-- Name: TABLE tracker_projects; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tracker_projects TO anon;
GRANT ALL ON TABLE public.tracker_projects TO authenticated;
GRANT ALL ON TABLE public.tracker_projects TO service_role;


--
-- Name: FUNCTION fetch_tracker_project(p_project_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.fetch_tracker_project(p_project_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.fetch_tracker_project(p_project_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.fetch_tracker_project(p_project_id uuid) TO service_role;


--
-- Name: TABLE work_orders; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.work_orders TO anon;
GRANT ALL ON TABLE public.work_orders TO authenticated;
GRANT ALL ON TABLE public.work_orders TO service_role;


--
-- Name: FUNCTION fetch_work_order(p_work_order_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.fetch_work_order(p_work_order_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.fetch_work_order(p_work_order_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.fetch_work_order(p_work_order_id uuid) TO service_role;


--
-- Name: TABLE work_order_agreements; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.work_order_agreements TO anon;
GRANT ALL ON TABLE public.work_order_agreements TO authenticated;
GRANT ALL ON TABLE public.work_order_agreements TO service_role;


--
-- Name: FUNCTION fetch_work_order_agreement(p_work_order_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.fetch_work_order_agreement(p_work_order_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.fetch_work_order_agreement(p_work_order_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.fetch_work_order_agreement(p_work_order_id uuid) TO service_role;


--
-- Name: FUNCTION fetch_work_order_tree(p_work_order_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.fetch_work_order_tree(p_work_order_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.fetch_work_order_tree(p_work_order_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.fetch_work_order_tree(p_work_order_id uuid) TO service_role;


--
-- Name: FUNCTION generate_roadmap_for_lead(p_lead_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.generate_roadmap_for_lead(p_lead_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.generate_roadmap_for_lead(p_lead_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.generate_roadmap_for_lead(p_lead_id uuid) TO service_role;


--
-- Name: FUNCTION get_or_create_production_packet(p_work_order_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.get_or_create_production_packet(p_work_order_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_or_create_production_packet(p_work_order_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_or_create_production_packet(p_work_order_id uuid) TO service_role;


--
-- Name: FUNCTION get_wh_order(p_order_number text, p_email text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.get_wh_order(p_order_number text, p_email text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_wh_order(p_order_number text, p_email text) TO anon;
GRANT ALL ON FUNCTION public.get_wh_order(p_order_number text, p_email text) TO authenticated;
GRANT ALL ON FUNCTION public.get_wh_order(p_order_number text, p_email text) TO service_role;


--
-- Name: FUNCTION handle_new_user(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC;
GRANT ALL ON FUNCTION public.handle_new_user() TO authenticated;
GRANT ALL ON FUNCTION public.handle_new_user() TO service_role;


--
-- Name: FUNCTION has_capability(p_org_id uuid, p_capability text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.has_capability(p_org_id uuid, p_capability text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.has_capability(p_org_id uuid, p_capability text) TO authenticated;
GRANT ALL ON FUNCTION public.has_capability(p_org_id uuid, p_capability text) TO service_role;


--
-- Name: FUNCTION is_org_manager(p_org_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.is_org_manager(p_org_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.is_org_manager(p_org_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.is_org_manager(p_org_id uuid) TO service_role;


--
-- Name: FUNCTION is_pipeline_manager(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.is_pipeline_manager() FROM PUBLIC;
GRANT ALL ON FUNCTION public.is_pipeline_manager() TO authenticated;
GRANT ALL ON FUNCTION public.is_pipeline_manager() TO service_role;


--
-- Name: FUNCTION is_pipeline_user(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.is_pipeline_user() FROM PUBLIC;
GRANT ALL ON FUNCTION public.is_pipeline_user() TO authenticated;
GRANT ALL ON FUNCTION public.is_pipeline_user() TO service_role;


--
-- Name: FUNCTION is_platform_admin(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.is_platform_admin() FROM PUBLIC;
GRANT ALL ON FUNCTION public.is_platform_admin() TO authenticated;
GRANT ALL ON FUNCTION public.is_platform_admin() TO service_role;


--
-- Name: FUNCTION is_staff(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.is_staff() FROM PUBLIC;
GRANT ALL ON FUNCTION public.is_staff() TO authenticated;
GRANT ALL ON FUNCTION public.is_staff() TO service_role;


--
-- Name: FUNCTION job_master_sign_off(p_work_order_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.job_master_sign_off(p_work_order_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.job_master_sign_off(p_work_order_id uuid) TO service_role;


--
-- Name: FUNCTION list_org_members(p_org_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.list_org_members(p_org_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.list_org_members(p_org_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.list_org_members(p_org_id uuid) TO service_role;


--
-- Name: FUNCTION my_active_lead_count(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.my_active_lead_count() FROM PUBLIC;
GRANT ALL ON FUNCTION public.my_active_lead_count() TO authenticated;
GRANT ALL ON FUNCTION public.my_active_lead_count() TO service_role;


--
-- Name: FUNCTION my_avg_cycle_days(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.my_avg_cycle_days() FROM PUBLIC;
GRANT ALL ON FUNCTION public.my_avg_cycle_days() TO authenticated;
GRANT ALL ON FUNCTION public.my_avg_cycle_days() TO service_role;


--
-- Name: FUNCTION my_closes_this_month(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.my_closes_this_month() FROM PUBLIC;
GRANT ALL ON FUNCTION public.my_closes_this_month() TO authenticated;
GRANT ALL ON FUNCTION public.my_closes_this_month() TO service_role;


--
-- Name: FUNCTION my_open_pipeline_value(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.my_open_pipeline_value() FROM PUBLIC;
GRANT ALL ON FUNCTION public.my_open_pipeline_value() TO authenticated;
GRANT ALL ON FUNCTION public.my_open_pipeline_value() TO service_role;


--
-- Name: FUNCTION my_org_ids(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.my_org_ids() FROM PUBLIC;
GRANT ALL ON FUNCTION public.my_org_ids() TO authenticated;
GRANT ALL ON FUNCTION public.my_org_ids() TO service_role;


--
-- Name: FUNCTION my_wh_role(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.my_wh_role() FROM PUBLIC;
GRANT ALL ON FUNCTION public.my_wh_role() TO authenticated;
GRANT ALL ON FUNCTION public.my_wh_role() TO service_role;


--
-- Name: FUNCTION my_win_rate(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.my_win_rate() FROM PUBLIC;
GRANT ALL ON FUNCTION public.my_win_rate() TO authenticated;
GRANT ALL ON FUNCTION public.my_win_rate() TO service_role;


--
-- Name: FUNCTION order_scope(p_deal_id uuid, p_ordered_at timestamp with time zone); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.order_scope(p_deal_id uuid, p_ordered_at timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.order_scope(p_deal_id uuid, p_ordered_at timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION public.order_scope(p_deal_id uuid, p_ordered_at timestamp with time zone) TO service_role;


--
-- Name: FUNCTION present_estimate(p_estimate_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.present_estimate(p_estimate_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.present_estimate(p_estimate_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.present_estimate(p_estimate_id uuid) TO service_role;


--
-- Name: FUNCTION present_quote(p_deal_id uuid, p_presented_at timestamp with time zone); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.present_quote(p_deal_id uuid, p_presented_at timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.present_quote(p_deal_id uuid, p_presented_at timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION public.present_quote(p_deal_id uuid, p_presented_at timestamp with time zone) TO service_role;


--
-- Name: FUNCTION protect_roadmap_columns(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.protect_roadmap_columns() TO anon;
GRANT ALL ON FUNCTION public.protect_roadmap_columns() TO authenticated;
GRANT ALL ON FUNCTION public.protect_roadmap_columns() TO service_role;


--
-- Name: FUNCTION record_work_order_sign_off(p_work_order_id uuid, p_notes text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.record_work_order_sign_off(p_work_order_id uuid, p_notes text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.record_work_order_sign_off(p_work_order_id uuid, p_notes text) TO authenticated;
GRANT ALL ON FUNCTION public.record_work_order_sign_off(p_work_order_id uuid, p_notes text) TO service_role;


--
-- Name: FUNCTION remove_check_in_photo(p_check_in_id uuid, p_photo_data_url text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.remove_check_in_photo(p_check_in_id uuid, p_photo_data_url text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.remove_check_in_photo(p_check_in_id uuid, p_photo_data_url text) TO authenticated;
GRANT ALL ON FUNCTION public.remove_check_in_photo(p_check_in_id uuid, p_photo_data_url text) TO service_role;


--
-- Name: FUNCTION reorder_estimate_line_items(p_estimate_id uuid, p_line_item_ids uuid[]); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.reorder_estimate_line_items(p_estimate_id uuid, p_line_item_ids uuid[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.reorder_estimate_line_items(p_estimate_id uuid, p_line_item_ids uuid[]) TO authenticated;
GRANT ALL ON FUNCTION public.reorder_estimate_line_items(p_estimate_id uuid, p_line_item_ids uuid[]) TO service_role;


--
-- Name: FUNCTION restore_deal(p_deal_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.restore_deal(p_deal_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.restore_deal(p_deal_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.restore_deal(p_deal_id uuid) TO service_role;


--
-- Name: FUNCTION restore_tracker_item(p_item_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.restore_tracker_item(p_item_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.restore_tracker_item(p_item_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.restore_tracker_item(p_item_id uuid) TO service_role;


--
-- Name: FUNCTION restore_tracker_project(p_project_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.restore_tracker_project(p_project_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.restore_tracker_project(p_project_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.restore_tracker_project(p_project_id uuid) TO service_role;


--
-- Name: FUNCTION restore_work_order(p_work_order_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.restore_work_order(p_work_order_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.restore_work_order(p_work_order_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.restore_work_order(p_work_order_id uuid) TO service_role;


--
-- Name: FUNCTION roadmap_playbook(q text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.roadmap_playbook(q text) TO anon;
GRANT ALL ON FUNCTION public.roadmap_playbook(q text) TO authenticated;
GRANT ALL ON FUNCTION public.roadmap_playbook(q text) TO service_role;


--
-- Name: FUNCTION set_tenant_module(p_org_id uuid, p_module_key text, p_enabled boolean, p_config jsonb); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.set_tenant_module(p_org_id uuid, p_module_key text, p_enabled boolean, p_config jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_tenant_module(p_org_id uuid, p_module_key text, p_enabled boolean, p_config jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.set_tenant_module(p_org_id uuid, p_module_key text, p_enabled boolean, p_config jsonb) TO service_role;


--
-- Name: FUNCTION sign_estimate(p_estimate_id uuid, p_signer_name text, p_signer_role text, p_signature_data text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.sign_estimate(p_estimate_id uuid, p_signer_name text, p_signer_role text, p_signature_data text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sign_estimate(p_estimate_id uuid, p_signer_name text, p_signer_role text, p_signature_data text) TO authenticated;
GRANT ALL ON FUNCTION public.sign_estimate(p_estimate_id uuid, p_signer_name text, p_signer_role text, p_signature_data text) TO service_role;


--
-- Name: FUNCTION touch_leads_updated_at(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.touch_leads_updated_at() TO anon;
GRANT ALL ON FUNCTION public.touch_leads_updated_at() TO authenticated;
GRANT ALL ON FUNCTION public.touch_leads_updated_at() TO service_role;


--
-- Name: FUNCTION tracker_status_config(p_org_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.tracker_status_config(p_org_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.tracker_status_config(p_org_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.tracker_status_config(p_org_id uuid) TO service_role;


--
-- Name: FUNCTION tracker_type_config(p_org_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.tracker_type_config(p_org_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.tracker_type_config(p_org_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.tracker_type_config(p_org_id uuid) TO service_role;


--
-- Name: FUNCTION update_check_in(p_check_in_id uuid, p_crew_name text, p_check_in_date date, p_hours numeric, p_materials_used text, p_blockers text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.update_check_in(p_check_in_id uuid, p_crew_name text, p_check_in_date date, p_hours numeric, p_materials_used text, p_blockers text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_check_in(p_check_in_id uuid, p_crew_name text, p_check_in_date date, p_hours numeric, p_materials_used text, p_blockers text) TO authenticated;
GRANT ALL ON FUNCTION public.update_check_in(p_check_in_id uuid, p_crew_name text, p_check_in_date date, p_hours numeric, p_materials_used text, p_blockers text) TO service_role;


--
-- Name: FUNCTION update_deal_fields(p_deal_id uuid, p_patch jsonb); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.update_deal_fields(p_deal_id uuid, p_patch jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_deal_fields(p_deal_id uuid, p_patch jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.update_deal_fields(p_deal_id uuid, p_patch jsonb) TO service_role;


--
-- Name: FUNCTION update_deal_stage(p_deal_id uuid, p_new_stage text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.update_deal_stage(p_deal_id uuid, p_new_stage text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_deal_stage(p_deal_id uuid, p_new_stage text) TO authenticated;
GRANT ALL ON FUNCTION public.update_deal_stage(p_deal_id uuid, p_new_stage text) TO service_role;


--
-- Name: FUNCTION update_estimate_build_mode(p_estimate_id uuid, p_build_mode text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.update_estimate_build_mode(p_estimate_id uuid, p_build_mode text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_estimate_build_mode(p_estimate_id uuid, p_build_mode text) TO authenticated;
GRANT ALL ON FUNCTION public.update_estimate_build_mode(p_estimate_id uuid, p_build_mode text) TO service_role;


--
-- Name: FUNCTION update_estimate_contact(p_estimate_id uuid, p_contact_name text, p_company text, p_phone text, p_email text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.update_estimate_contact(p_estimate_id uuid, p_contact_name text, p_company text, p_phone text, p_email text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_estimate_contact(p_estimate_id uuid, p_contact_name text, p_company text, p_phone text, p_email text) TO authenticated;
GRANT ALL ON FUNCTION public.update_estimate_contact(p_estimate_id uuid, p_contact_name text, p_company text, p_phone text, p_email text) TO service_role;


--
-- Name: FUNCTION update_estimate_details(p_estimate_id uuid, p_squares numeric, p_pitch text, p_site_address text, p_estimate_date date, p_valid_until date, p_tax_rate numeric, p_notes_terms text, p_clear_valid_until boolean, p_clear_tax_rate boolean); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.update_estimate_details(p_estimate_id uuid, p_squares numeric, p_pitch text, p_site_address text, p_estimate_date date, p_valid_until date, p_tax_rate numeric, p_notes_terms text, p_clear_valid_until boolean, p_clear_tax_rate boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_estimate_details(p_estimate_id uuid, p_squares numeric, p_pitch text, p_site_address text, p_estimate_date date, p_valid_until date, p_tax_rate numeric, p_notes_terms text, p_clear_valid_until boolean, p_clear_tax_rate boolean) TO authenticated;
GRANT ALL ON FUNCTION public.update_estimate_details(p_estimate_id uuid, p_squares numeric, p_pitch text, p_site_address text, p_estimate_date date, p_valid_until date, p_tax_rate numeric, p_notes_terms text, p_clear_valid_until boolean, p_clear_tax_rate boolean) TO service_role;


--
-- Name: FUNCTION update_estimate_line_item(p_line_item_id uuid, p_description text, p_quantity numeric, p_unit_price numeric, p_sort_order integer, p_unit text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.update_estimate_line_item(p_line_item_id uuid, p_description text, p_quantity numeric, p_unit_price numeric, p_sort_order integer, p_unit text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_estimate_line_item(p_line_item_id uuid, p_description text, p_quantity numeric, p_unit_price numeric, p_sort_order integer, p_unit text) TO authenticated;
GRANT ALL ON FUNCTION public.update_estimate_line_item(p_line_item_id uuid, p_description text, p_quantity numeric, p_unit_price numeric, p_sort_order integer, p_unit text) TO service_role;


--
-- Name: FUNCTION update_intake_checklist_field(p_deal_id uuid, p_field_path text[], p_value jsonb); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.update_intake_checklist_field(p_deal_id uuid, p_field_path text[], p_value jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_intake_checklist_field(p_deal_id uuid, p_field_path text[], p_value jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.update_intake_checklist_field(p_deal_id uuid, p_field_path text[], p_value jsonb) TO service_role;


--
-- Name: FUNCTION update_material_item(p_material_item_id uuid, p_name text, p_quantity numeric, p_ready_by date, p_sort_order integer); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.update_material_item(p_material_item_id uuid, p_name text, p_quantity numeric, p_ready_by date, p_sort_order integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_material_item(p_material_item_id uuid, p_name text, p_quantity numeric, p_ready_by date, p_sort_order integer) TO authenticated;
GRANT ALL ON FUNCTION public.update_material_item(p_material_item_id uuid, p_name text, p_quantity numeric, p_ready_by date, p_sort_order integer) TO service_role;


--
-- Name: FUNCTION update_production_packet_callout(p_production_packet_id uuid, p_callout_id uuid, p_label text, p_detail text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.update_production_packet_callout(p_production_packet_id uuid, p_callout_id uuid, p_label text, p_detail text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_production_packet_callout(p_production_packet_id uuid, p_callout_id uuid, p_label text, p_detail text) TO authenticated;
GRANT ALL ON FUNCTION public.update_production_packet_callout(p_production_packet_id uuid, p_callout_id uuid, p_label text, p_detail text) TO service_role;


--
-- Name: FUNCTION update_production_packet_notes(p_production_packet_id uuid, p_notes text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.update_production_packet_notes(p_production_packet_id uuid, p_notes text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_production_packet_notes(p_production_packet_id uuid, p_notes text) TO authenticated;
GRANT ALL ON FUNCTION public.update_production_packet_notes(p_production_packet_id uuid, p_notes text) TO service_role;


--
-- Name: FUNCTION update_roadmap_fields(p_id uuid, p_patch jsonb); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.update_roadmap_fields(p_id uuid, p_patch jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_roadmap_fields(p_id uuid, p_patch jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.update_roadmap_fields(p_id uuid, p_patch jsonb) TO service_role;


--
-- Name: FUNCTION update_roadmap_project(p_project_id uuid, p_name text, p_sort_order integer); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.update_roadmap_project(p_project_id uuid, p_name text, p_sort_order integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_roadmap_project(p_project_id uuid, p_name text, p_sort_order integer) TO authenticated;
GRANT ALL ON FUNCTION public.update_roadmap_project(p_project_id uuid, p_name text, p_sort_order integer) TO service_role;


--
-- Name: FUNCTION update_schedule_block(p_schedule_block_id uuid, p_crew_name text, p_start_date date, p_end_date date); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.update_schedule_block(p_schedule_block_id uuid, p_crew_name text, p_start_date date, p_end_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_schedule_block(p_schedule_block_id uuid, p_crew_name text, p_start_date date, p_end_date date) TO authenticated;
GRANT ALL ON FUNCTION public.update_schedule_block(p_schedule_block_id uuid, p_crew_name text, p_start_date date, p_end_date date) TO service_role;


--
-- Name: FUNCTION update_tracker_item(p_item_id uuid, p_title text, p_description text, p_type text, p_status text, p_priority text, p_assignee_id uuid, p_clear_assignee boolean, p_position integer); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.update_tracker_item(p_item_id uuid, p_title text, p_description text, p_type text, p_status text, p_priority text, p_assignee_id uuid, p_clear_assignee boolean, p_position integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_tracker_item(p_item_id uuid, p_title text, p_description text, p_type text, p_status text, p_priority text, p_assignee_id uuid, p_clear_assignee boolean, p_position integer) TO authenticated;
GRANT ALL ON FUNCTION public.update_tracker_item(p_item_id uuid, p_title text, p_description text, p_type text, p_status text, p_priority text, p_assignee_id uuid, p_clear_assignee boolean, p_position integer) TO service_role;


--
-- Name: FUNCTION update_tracker_project(p_project_id uuid, p_name text, p_description text, p_status text, p_linked_org_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.update_tracker_project(p_project_id uuid, p_name text, p_description text, p_status text, p_linked_org_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_tracker_project(p_project_id uuid, p_name text, p_description text, p_status text, p_linked_org_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.update_tracker_project(p_project_id uuid, p_name text, p_description text, p_status text, p_linked_org_id uuid) TO service_role;


--
-- Name: FUNCTION upsert_estimate_scope_line_items(p_estimate_id uuid, p_items jsonb); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.upsert_estimate_scope_line_items(p_estimate_id uuid, p_items jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.upsert_estimate_scope_line_items(p_estimate_id uuid, p_items jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.upsert_estimate_scope_line_items(p_estimate_id uuid, p_items jsonb) TO service_role;


--
-- Name: FUNCTION void_estimate(p_estimate_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.void_estimate(p_estimate_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.void_estimate(p_estimate_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.void_estimate(p_estimate_id uuid) TO service_role;


--
-- Name: FUNCTION void_work_order(p_work_order_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.void_work_order(p_work_order_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.void_work_order(p_work_order_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.void_work_order(p_work_order_id uuid) TO service_role;


--
-- Name: FUNCTION wh_save_catalog_family(p_family jsonb, p_variations jsonb); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.wh_save_catalog_family(p_family jsonb, p_variations jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.wh_save_catalog_family(p_family jsonb, p_variations jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.wh_save_catalog_family(p_family jsonb, p_variations jsonb) TO service_role;


--
-- Name: FUNCTION work_order_is_my_trade(p_work_order_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.work_order_is_my_trade(p_work_order_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.work_order_is_my_trade(p_work_order_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.work_order_is_my_trade(p_work_order_id uuid) TO service_role;


--
-- Name: TABLE wh_colors_backup_20260814; Type: ACL; Schema: archive; Owner: postgres
--

GRANT ALL ON TABLE archive.wh_colors_backup_20260814 TO service_role;


--
-- Name: TABLE wh_product_colors_backup_20260814; Type: ACL; Schema: archive; Owner: postgres
--

GRANT ALL ON TABLE archive.wh_product_colors_backup_20260814 TO service_role;


--
-- Name: TABLE audit_leads; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.audit_leads TO anon;
GRANT ALL ON TABLE public.audit_leads TO authenticated;
GRANT ALL ON TABLE public.audit_leads TO service_role;


--
-- Name: TABLE audits; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.audits TO anon;
GRANT ALL ON TABLE public.audits TO authenticated;
GRANT ALL ON TABLE public.audits TO service_role;


--
-- Name: TABLE client_roadmaps; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.client_roadmaps TO anon;
GRANT ALL ON TABLE public.client_roadmaps TO authenticated;
GRANT ALL ON TABLE public.client_roadmaps TO service_role;


--
-- Name: TABLE deal_activity; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.deal_activity TO anon;
GRANT ALL ON TABLE public.deal_activity TO authenticated;
GRANT ALL ON TABLE public.deal_activity TO service_role;


--
-- Name: TABLE deal_notes; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.deal_notes TO anon;
GRANT ALL ON TABLE public.deal_notes TO authenticated;
GRANT ALL ON TABLE public.deal_notes TO service_role;


--
-- Name: TABLE engagement_checkins; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.engagement_checkins TO anon;
GRANT ALL ON TABLE public.engagement_checkins TO authenticated;
GRANT ALL ON TABLE public.engagement_checkins TO service_role;


--
-- Name: TABLE engagement_levels; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.engagement_levels TO anon;
GRANT ALL ON TABLE public.engagement_levels TO authenticated;
GRANT ALL ON TABLE public.engagement_levels TO service_role;


--
-- Name: TABLE engagement_milestones; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.engagement_milestones TO anon;
GRANT ALL ON TABLE public.engagement_milestones TO authenticated;
GRANT ALL ON TABLE public.engagement_milestones TO service_role;


--
-- Name: TABLE engagements; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.engagements TO anon;
GRANT ALL ON TABLE public.engagements TO authenticated;
GRANT ALL ON TABLE public.engagements TO service_role;


--
-- Name: TABLE estimate_line_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.estimate_line_items TO anon;
GRANT ALL ON TABLE public.estimate_line_items TO authenticated;
GRANT ALL ON TABLE public.estimate_line_items TO service_role;


--
-- Name: TABLE estimate_number_counters; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.estimate_number_counters TO anon;
GRANT ALL ON TABLE public.estimate_number_counters TO authenticated;
GRANT ALL ON TABLE public.estimate_number_counters TO service_role;


--
-- Name: TABLE follow_ups; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.follow_ups TO anon;
GRANT ALL ON TABLE public.follow_ups TO authenticated;
GRANT ALL ON TABLE public.follow_ups TO service_role;


--
-- Name: TABLE jobs; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.jobs TO anon;
GRANT ALL ON TABLE public.jobs TO authenticated;
GRANT ALL ON TABLE public.jobs TO service_role;


--
-- Name: TABLE lead_activity; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.lead_activity TO anon;
GRANT ALL ON TABLE public.lead_activity TO authenticated;
GRANT ALL ON TABLE public.lead_activity TO service_role;


--
-- Name: TABLE lead_appointments; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.lead_appointments TO anon;
GRANT ALL ON TABLE public.lead_appointments TO authenticated;
GRANT ALL ON TABLE public.lead_appointments TO service_role;


--
-- Name: TABLE lead_notes; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.lead_notes TO anon;
GRANT ALL ON TABLE public.lead_notes TO authenticated;
GRANT ALL ON TABLE public.lead_notes TO service_role;


--
-- Name: TABLE leads; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.leads TO anon;
GRANT ALL ON TABLE public.leads TO authenticated;
GRANT ALL ON TABLE public.leads TO service_role;


--
-- Name: TABLE material_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.material_items TO anon;
GRANT ALL ON TABLE public.material_items TO authenticated;
GRANT ALL ON TABLE public.material_items TO service_role;


--
-- Name: TABLE migration_bmr_activity_raw; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.migration_bmr_activity_raw TO anon;
GRANT ALL ON TABLE public.migration_bmr_activity_raw TO authenticated;
GRANT ALL ON TABLE public.migration_bmr_activity_raw TO service_role;


--
-- Name: TABLE migration_bmr_id_map; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.migration_bmr_id_map TO anon;
GRANT ALL ON TABLE public.migration_bmr_id_map TO authenticated;
GRANT ALL ON TABLE public.migration_bmr_id_map TO service_role;


--
-- Name: TABLE migration_bmr_leads_raw; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.migration_bmr_leads_raw TO anon;
GRANT ALL ON TABLE public.migration_bmr_leads_raw TO authenticated;
GRANT ALL ON TABLE public.migration_bmr_leads_raw TO service_role;


--
-- Name: TABLE migration_bmr_notes_raw; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.migration_bmr_notes_raw TO anon;
GRANT ALL ON TABLE public.migration_bmr_notes_raw TO authenticated;
GRANT ALL ON TABLE public.migration_bmr_notes_raw TO service_role;


--
-- Name: TABLE migration_bmr_users_raw; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.migration_bmr_users_raw TO anon;
GRANT ALL ON TABLE public.migration_bmr_users_raw TO authenticated;
GRANT ALL ON TABLE public.migration_bmr_users_raw TO service_role;


--
-- Name: TABLE org_invites; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.org_invites TO anon;
GRANT ALL ON TABLE public.org_invites TO authenticated;
GRANT ALL ON TABLE public.org_invites TO service_role;


--
-- Name: TABLE org_invoices; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.org_invoices TO anon;
GRANT ALL ON TABLE public.org_invoices TO authenticated;
GRANT ALL ON TABLE public.org_invoices TO service_role;


--
-- Name: TABLE org_members; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.org_members TO anon;
GRANT ALL ON TABLE public.org_members TO authenticated;
GRANT ALL ON TABLE public.org_members TO service_role;


--
-- Name: TABLE org_systems; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.org_systems TO anon;
GRANT ALL ON TABLE public.org_systems TO authenticated;
GRANT ALL ON TABLE public.org_systems TO service_role;


--
-- Name: TABLE pipeline_invites; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.pipeline_invites TO anon;
GRANT ALL ON TABLE public.pipeline_invites TO authenticated;
GRANT ALL ON TABLE public.pipeline_invites TO service_role;


--
-- Name: TABLE profiles; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.profiles TO anon;
GRANT ALL ON TABLE public.profiles TO authenticated;
GRANT ALL ON TABLE public.profiles TO service_role;


--
-- Name: TABLE proposals; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.proposals TO anon;
GRANT ALL ON TABLE public.proposals TO authenticated;
GRANT ALL ON TABLE public.proposals TO service_role;


--
-- Name: TABLE prospects; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.prospects TO anon;
GRANT ALL ON TABLE public.prospects TO authenticated;
GRANT ALL ON TABLE public.prospects TO service_role;


--
-- Name: TABLE roadmap_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.roadmap_items TO anon;
GRANT ALL ON TABLE public.roadmap_items TO authenticated;
GRANT ALL ON TABLE public.roadmap_items TO service_role;


--
-- Name: TABLE roadmap_projects; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.roadmap_projects TO anon;
GRANT ALL ON TABLE public.roadmap_projects TO authenticated;
GRANT ALL ON TABLE public.roadmap_projects TO service_role;


--
-- Name: TABLE schedule_blocks; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.schedule_blocks TO anon;
GRANT ALL ON TABLE public.schedule_blocks TO authenticated;
GRANT ALL ON TABLE public.schedule_blocks TO service_role;


--
-- Name: TABLE signatures; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.signatures TO anon;
GRANT ALL ON TABLE public.signatures TO authenticated;
GRANT ALL ON TABLE public.signatures TO service_role;


--
-- Name: TABLE staff_invites; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.staff_invites TO anon;
GRANT ALL ON TABLE public.staff_invites TO authenticated;
GRANT ALL ON TABLE public.staff_invites TO service_role;


--
-- Name: TABLE staff_users; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.staff_users TO anon;
GRANT ALL ON TABLE public.staff_users TO authenticated;
GRANT ALL ON TABLE public.staff_users TO service_role;


--
-- Name: TABLE structtech_state; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.structtech_state TO anon;
GRANT ALL ON TABLE public.structtech_state TO authenticated;
GRANT ALL ON TABLE public.structtech_state TO service_role;


--
-- Name: TABLE tenant_modules; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tenant_modules TO anon;
GRANT ALL ON TABLE public.tenant_modules TO authenticated;
GRANT ALL ON TABLE public.tenant_modules TO service_role;


--
-- Name: TABLE tg_agenda_card; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tg_agenda_card TO service_role;


--
-- Name: SEQUENCE tg_agenda_card_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.tg_agenda_card_id_seq TO anon;
GRANT ALL ON SEQUENCE public.tg_agenda_card_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.tg_agenda_card_id_seq TO service_role;


--
-- Name: TABLE tg_agenda_contact; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tg_agenda_contact TO service_role;


--
-- Name: SEQUENCE tg_agenda_contact_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.tg_agenda_contact_id_seq TO anon;
GRANT ALL ON SEQUENCE public.tg_agenda_contact_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.tg_agenda_contact_id_seq TO service_role;


--
-- Name: TABLE tg_agenda_group; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tg_agenda_group TO service_role;


--
-- Name: TABLE tg_agenda_sender; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tg_agenda_sender TO service_role;


--
-- Name: TABLE tg_agenda_session; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tg_agenda_session TO service_role;


--
-- Name: TABLE tg_agenda_update; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tg_agenda_update TO service_role;


--
-- Name: TABLE ticket_messages; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.ticket_messages TO anon;
GRANT ALL ON TABLE public.ticket_messages TO authenticated;
GRANT ALL ON TABLE public.ticket_messages TO service_role;


--
-- Name: TABLE tickets; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tickets TO anon;
GRANT ALL ON TABLE public.tickets TO authenticated;
GRANT ALL ON TABLE public.tickets TO service_role;


--
-- Name: TABLE wh_categories; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wh_categories TO anon;
GRANT ALL ON TABLE public.wh_categories TO authenticated;
GRANT ALL ON TABLE public.wh_categories TO service_role;


--
-- Name: TABLE wh_category_products; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wh_category_products TO anon;
GRANT ALL ON TABLE public.wh_category_products TO authenticated;
GRANT ALL ON TABLE public.wh_category_products TO service_role;


--
-- Name: TABLE wh_colors; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wh_colors TO anon;
GRANT ALL ON TABLE public.wh_colors TO authenticated;
GRANT ALL ON TABLE public.wh_colors TO service_role;


--
-- Name: TABLE wh_price_history; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wh_price_history TO anon;
GRANT ALL ON TABLE public.wh_price_history TO authenticated;
GRANT ALL ON TABLE public.wh_price_history TO service_role;


--
-- Name: TABLE wh_current_prices; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wh_current_prices TO anon;
GRANT ALL ON TABLE public.wh_current_prices TO authenticated;
GRANT ALL ON TABLE public.wh_current_prices TO service_role;


--
-- Name: TABLE wh_drivers; Type: ACL; Schema: public; Owner: postgres
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE public.wh_drivers TO anon;
GRANT ALL ON TABLE public.wh_drivers TO authenticated;
GRANT ALL ON TABLE public.wh_drivers TO service_role;


--
-- Name: TABLE wh_order_line_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE public.wh_order_line_items TO anon;
GRANT ALL ON TABLE public.wh_order_line_items TO authenticated;
GRANT ALL ON TABLE public.wh_order_line_items TO service_role;


--
-- Name: SEQUENCE wh_order_number_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.wh_order_number_seq TO anon;
GRANT ALL ON SEQUENCE public.wh_order_number_seq TO authenticated;
GRANT ALL ON SEQUENCE public.wh_order_number_seq TO service_role;


--
-- Name: TABLE wh_orders; Type: ACL; Schema: public; Owner: postgres
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE public.wh_orders TO anon;
GRANT ALL ON TABLE public.wh_orders TO authenticated;
GRANT ALL ON TABLE public.wh_orders TO service_role;


--
-- Name: TABLE wh_product_colors; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wh_product_colors TO anon;
GRANT ALL ON TABLE public.wh_product_colors TO authenticated;
GRANT ALL ON TABLE public.wh_product_colors TO service_role;


--
-- Name: TABLE wh_product_families; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wh_product_families TO anon;
GRANT ALL ON TABLE public.wh_product_families TO authenticated;
GRANT ALL ON TABLE public.wh_product_families TO service_role;


--
-- Name: TABLE wh_product_roles; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wh_product_roles TO anon;
GRANT ALL ON TABLE public.wh_product_roles TO authenticated;
GRANT ALL ON TABLE public.wh_product_roles TO service_role;


--
-- Name: TABLE wh_product_types; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wh_product_types TO anon;
GRANT ALL ON TABLE public.wh_product_types TO authenticated;
GRANT ALL ON TABLE public.wh_product_types TO service_role;


--
-- Name: TABLE wh_product_variations; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wh_product_variations TO anon;
GRANT ALL ON TABLE public.wh_product_variations TO authenticated;
GRANT ALL ON TABLE public.wh_product_variations TO service_role;


--
-- Name: TABLE wh_products; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wh_products TO anon;
GRANT ALL ON TABLE public.wh_products TO authenticated;
GRANT ALL ON TABLE public.wh_products TO service_role;


--
-- Name: TABLE wh_settings; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wh_settings TO anon;
GRANT ALL ON TABLE public.wh_settings TO authenticated;
GRANT ALL ON TABLE public.wh_settings TO service_role;


--
-- Name: TABLE wh_spec_files; Type: ACL; Schema: public; Owner: postgres
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE public.wh_spec_files TO anon;
GRANT ALL ON TABLE public.wh_spec_files TO authenticated;
GRANT ALL ON TABLE public.wh_spec_files TO service_role;


--
-- Name: TABLE wh_stages; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wh_stages TO anon;
GRANT ALL ON TABLE public.wh_stages TO authenticated;
GRANT ALL ON TABLE public.wh_stages TO service_role;


--
-- Name: TABLE wh_systems; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wh_systems TO anon;
GRANT ALL ON TABLE public.wh_systems TO authenticated;
GRANT ALL ON TABLE public.wh_systems TO service_role;


--
-- Name: TABLE wh_team_members; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wh_team_members TO anon;
GRANT ALL ON TABLE public.wh_team_members TO authenticated;
GRANT ALL ON TABLE public.wh_team_members TO service_role;


--
-- Name: TABLE wh_variation_colors; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wh_variation_colors TO anon;
GRANT ALL ON TABLE public.wh_variation_colors TO authenticated;
GRANT ALL ON TABLE public.wh_variation_colors TO service_role;


--
-- Name: TABLE work_order_activity; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.work_order_activity TO anon;
GRANT ALL ON TABLE public.work_order_activity TO authenticated;
GRANT ALL ON TABLE public.work_order_activity TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- PostgreSQL database dump complete
--

\unrestrict v65cSZxwHh7NPmbCQZP8bi13kGeUWfazdJdYsLdQFKqPobjBam6dSRfCeYx85Ia

