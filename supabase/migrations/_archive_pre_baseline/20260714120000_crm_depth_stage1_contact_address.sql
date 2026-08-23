-- StructTech OS — CRM Depth Stage 1: contact & address data
--
-- NOT APPLIED. Author-only migration file — ask before applying, same as
-- every other migration in this repo. Depends on the management-controls
-- retrofit (20260713180000) already being applied — update_deal_details()
-- is CREATE OR REPLACE'd here, not created fresh.
--
-- Three new nullable columns on deals, no backfill — same "additive, no
-- forced migration of old rows" pattern as sign_off_at/voided_at. The 7
-- existing deals just have lead_type/project_address/billing_address = null
-- until someone edits them through the new form/panel.
--
-- Two things this migration deliberately does NOT do (both confirmed with
-- Jacob, both flagged for later rather than dropped):
--   1. project_address/billing_address are plain text, not structured
--      (street/city/state/zip) or geocoded. Matches the existing
--      estimates.site_address precedent (also free text). BACKLOG.md gets
--      a line that this wants to become structured/geocoded later — EagleView
--      aerial measurement (BUILD_PLAN/SCOPE §13 runner-up) needs a real
--      address to query, and crew routing wants coordinates, not a string.
--   2. No conditional "Company" field visibility keyed off lead_type. The
--      new-lead form always shows Company (labeled "if applicable") —
--      later polish, not blocking Stage 1, avoids needing a client
--      component for this form.
--
-- lead_type is a 2-value enum ('homeowner' | 'company') — "company" folds
-- in "contractor" per CLAUDE.md's own "(homeowner/company)" parenthetical,
-- not a third option.
--
-- phone stays phone, not renamed to cell_phone — the column already means
-- cell in this app (no landline concept), and renaming touches
-- create_deal/update_deal_details' signatures plus every caller for zero
-- functional gain. The UI just labels the field "Cell phone."
--
-- billing_address has no "same as project address" checkbox/JS — leave it
-- blank and every place billing address is displayed falls back to
-- project_address at the UI layer. Cheapest correct version of that
-- convenience.
--
-- Real bug caught in review, fixed here: CREATE OR REPLACE does NOT replace
-- a function whose argument list changed — Postgres matches "replace" by
-- the exact existing (type-only) signature, so adding 3 trailing params
-- would have created a second OVERLOAD sitting alongside the old 9-arg
-- create_deal / 8-arg update_deal_details, not replaced them. A caller
-- using named params (every app RPC call in this repo does) would then
-- match both overloads and Postgres would raise "function is not unique."
-- Fixed by explicitly DROPping the exact old signatures (each placed
-- immediately before its CREATE OR REPLACE in sections 2/3 below) —
-- confirmed against live pg_proc via pg_get_function_identity_arguments(),
-- not assumed from the source migration files. create_estimate_from_deal
-- keeps its original single-arg signature (only the body changed), so
-- plain CREATE OR REPLACE is correct there — no DROP needed, no overload
-- risk.

-- ============================================================================
-- 1. Schema
-- ============================================================================
alter table public.deals
  add column lead_type text check (lead_type in ('homeowner', 'company')),
  add column project_address text,
  add column billing_address text;

comment on column public.deals.lead_type is
  'homeowner or company (company folds in contractor — CLAUDE.md CRM Depth Stage 1). Nullable, no backfill.';
comment on column public.deals.project_address is
  'The job/service address. Free text for now — see migration header note 1 (structured/geocoded is future work, BACKLOG.md).';
comment on column public.deals.billing_address is
  'Nullable — falls back to project_address wherever displayed if unset. See migration header note.';

-- ============================================================================
-- 2. create_deal — extended with the 3 new params, same coalesce-free
-- straight-insert pattern as the existing columns (this is a create RPC,
-- not an update, so there's nothing to coalesce against). DROP first — see
-- migration header; this is the exact live 9-arg signature per pg_proc.
-- ============================================================================
drop function if exists public.create_deal(uuid, text, text, text, text, numeric, text, int, text);

create or replace function public.create_deal(
  p_org_id uuid,
  p_contact_name text,
  p_company text default null,
  p_email text default null,
  p_phone text default null,
  p_value numeric default null,
  p_trade text default null,
  p_crew_size int default null,
  p_source text default 'manual',
  p_lead_type text default null,
  p_project_address text default null,
  p_billing_address text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deal_id uuid;
  v_first_stage text;
  v_cadence int[];
begin
  if p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of organization %', p_org_id;
  end if;

  select stages -> 0 ->> 'key'
  into v_first_stage
  from (select public.crm_stage_config(p_org_id) as stages) s;

  if v_first_stage is null then
    raise exception 'organization % has no crm stage config', p_org_id;
  end if;

  insert into public.deals
    (org_id, contact_name, company, email, phone, value, trade, crew_size, stage, source,
     lead_type, project_address, billing_address)
  values
    (p_org_id, p_contact_name, p_company, p_email, p_phone, p_value, p_trade, p_crew_size, v_first_stage, p_source,
     p_lead_type, p_project_address, p_billing_address)
  returning id into v_deal_id;

  insert into public.deal_activity (deal_id, org_id, action, to_value)
  values (v_deal_id, p_org_id, 'created', p_source);

  if p_email is not null and p_email like '%@%' then
    v_cadence := public.crm_follow_up_cadence_days(p_org_id);
    if coalesce(array_length(v_cadence, 1), 0) < 2 then
      v_cadence := array[2, 5];
    end if;

    insert into public.follow_ups (deal_id, org_id, send_at, to_email, subject, body) values
    (v_deal_id, p_org_id, now() + make_interval(days => v_cadence[1]), p_email,
     'Following up, ' || coalesce(split_part(p_contact_name,' ',1), ''),
     'Hey ' || coalesce(split_part(p_contact_name,' ',1),'there') || E',\n\nJust checking in on where things stand — happy to answer any questions.\n\n— StructTech'),
    (v_deal_id, p_org_id, now() + make_interval(days => v_cadence[2]), p_email,
     'Still here if you need anything',
     'Hey ' || coalesce(split_part(p_contact_name,' ',1),'there') || E',\n\nLast check-in from me for now — reach out whenever works.\n\n— StructTech');

    insert into public.deal_activity (deal_id, org_id, action, to_value)
    values (v_deal_id, p_org_id, 'followup_scheduled', 'day-' || v_cadence[1] || ' + day-' || v_cadence[2]);
  end if;

  return v_deal_id;
end;
$$;

comment on function public.create_deal(uuid, text, text, text, text, numeric, text, int, text, text, text, text) is
  'Pipeline insert RPC. Org-scoped from caller membership; stage defaults to the org''s configured first stage; schedules config-driven follow-ups (generic copy) if an email is given. Extended CRM Depth Stage 1 with lead_type/project_address/billing_address.';

-- ============================================================================
-- 3. update_deal_details — extended with the same 3 params, same
-- coalesce-against-current-value pattern as every other field here. DROP
-- first — exact live 8-arg signature per pg_proc.
-- ============================================================================
drop function if exists public.update_deal_details(uuid, text, text, text, text, numeric, text, int);

create or replace function public.update_deal_details(
  p_deal_id uuid,
  p_contact_name text default null,
  p_company text default null,
  p_email text default null,
  p_phone text default null,
  p_value numeric default null,
  p_trade text default null,
  p_crew_size int default null,
  p_lead_type text default null,
  p_project_address text default null,
  p_billing_address text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  update public.deals
  set contact_name = coalesce(p_contact_name, contact_name),
      company = coalesce(p_company, company),
      email = coalesce(p_email, email),
      phone = coalesce(p_phone, phone),
      value = coalesce(p_value, value),
      trade = coalesce(p_trade, trade),
      crew_size = coalesce(p_crew_size, crew_size),
      lead_type = coalesce(p_lead_type, lead_type),
      project_address = coalesce(p_project_address, project_address),
      billing_address = coalesce(p_billing_address, billing_address),
      updated_at = now()
  where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action)
  values (p_deal_id, v_org_id, 'details_updated');
end;
$$;

-- ============================================================================
-- 4. create_estimate_from_deal — ONE addition: also copy project_address
-- into the new estimate's site_address. Everything else about this
-- function is untouched from the Week 2 estimating migration. This is the
-- exact re-entry gap that migration's header called out ("estimates has no
-- address column at all... site_address is a new nullable field with
-- nothing to copy INTO it") — now there's something to copy.
-- ============================================================================
create or replace function public.create_estimate_from_deal(p_deal_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_contact_name text;
  v_company text;
  v_phone text;
  v_email text;
  v_project_address text;
  v_estimate_id uuid;
begin
  select org_id, contact_name, company, phone, email, project_address
  into v_org_id, v_contact_name, v_company, v_phone, v_email, v_project_address
  from public.deals
  where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  insert into public.estimates (org_id, deal_id, contact_name, company, phone, email, site_address)
  values (v_org_id, p_deal_id, v_contact_name, v_company, v_phone, v_email, v_project_address)
  returning id into v_estimate_id;

  return v_estimate_id;
end;
$$;
