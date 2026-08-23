-- StructTech OS — CRM Depth Stage 2: full lead data model
--
-- NOT APPLIED. Author-only migration file — ask before applying, same as
-- every other migration in this repo. Depends on Stage 1 (20260714120000)
-- already being applied. No UI in this migration (CLAUDE.md Stage 4 owns
-- that) — Stage 1's live new-lead form and deal panel keep working
-- unchanged against this schema; nothing here breaks them.
--
-- Grounded in docs/reference/LEAD_CONTROL_CENTER_SPEC.md's "rich lead data
-- model we're missing" list. See the reconciliation note delivered in chat
-- alongside this file for how each new field relates to what Stage 1
-- already shipped — summarized here so the file stands on its own:
--
--   * homeowner_or_contractor -> REUSES deals.lead_type (Stage 1). Not a
--     new column. 'company' already folds in "contractor" per Stage 1's
--     own decision — still a 2-value check, not 3.
--   * company_name -> REUSES deals.company (Week 1, pre-existing).
--   * structured service address -> ADDITIVE. project_address (Stage 1,
--     free text, feeds create_estimate_from_deal today) is UNTOUCHED —
--     still what the live form/RPC read and write. The 4 new
--     service_address_* columns are independent for now, no auto-sync in
--     either direction. How they reconcile (project_address becomes a
--     display concat? a freeform override? deprecated?) is a Stage 4 UI
--     decision, not this migration's to make.
--   * billing address stays free text (deals.billing_address, Stage 1) —
--     not structured this stage, wasn't asked for.
--   * first_name/last_name -> ADDITIVE, nullable. deals.contact_name is
--     NOT NULL and load-bearing everywhere (deal cards, panel headers,
--     estimate/PDF contact copy, the follow-up email greeting via
--     split_part(contact_name,' ',1)) — it cannot become a generated
--     column without backfilling every existing deal's first/last, which
--     this migration deliberately does not do (same "additive, no forced
--     backfill" pattern as every prior nullable column here). Instead
--     create_deal/update_deal_details get precedence logic: an explicit
--     p_contact_name wins (Stage 1's form is unaffected byte-for-byte);
--     otherwise, if first/last are given, contact_name is DERIVED
--     (concatenated) so every downstream reader keeps working without
--     rewrite. See section 3/4 below.
--
-- intake_checklist (jsonb) and the three milestone timestamps get their
-- columns added here but NO RPC wiring — deliberately out of scope. They
-- get written incrementally, field-by-field, by Stage 3's command-stage
-- engine (not designed yet); bolting them onto create_deal/
-- update_deal_details now would guess at a shape that isn't decided.
--
-- existing_roof_type / roof_type_requested / tags are text[] (arrays),
-- not text — the spec calls roof type "type(s)" (plural) and describes
-- the field type as "roof_types (multi-section)"; tags are inherently
-- multi ("Homeowner / Remodel / Asphalt shingle").
--
-- owner_id references public.profiles(id), not org_members — org_members
-- has no single-column primary key (composite org_id+user_id), and
-- profiles already mirrors auth.users for exactly this kind of
-- "which user" reference. Nullable — rep assignment is Stage 5
-- (Ownership & attribution), this migration just gives it somewhere to
-- write.
--
-- Real bug fixed once already in Stage 1, same fix applied again here on
-- principle: CREATE OR REPLACE does not replace a function whose argument
-- list changed — it creates a second overload, and a caller using named
-- params (every RPC call in this repo) then hits "function is not
-- unique." Both create_deal and update_deal_details get an explicit DROP
-- of their exact current signature (confirmed against live pg_proc, not
-- assumed) immediately before each is recreated.

-- ============================================================================
-- 1. Schema — all nullable, no backfill, same additive pattern as every
-- prior stage.
-- ============================================================================
alter table public.deals
  add column first_name text,
  add column last_name text,
  add column secondary_phone text,
  add column remodel_or_new_construction text
    check (remodel_or_new_construction in ('remodel', 'new_construction')),
  add column existing_roof_type text[],
  add column roof_type_requested text[],
  add column service_address_street text,
  add column service_address_city text,
  add column service_address_state text,
  add column service_address_zip text,
  add column referral_name text,
  add column intake_checklist jsonb not null default '{}'::jsonb,
  add column site_survey_complete_at timestamptz,
  add column roof_scope_ordered_at timestamptz,
  add column quote_presented_at timestamptz,
  add column owner_id uuid references public.profiles(id),
  add column tags text[];

comment on column public.deals.first_name is
  'Split from contact_name (CRM Depth Stage 2). Nullable, no backfill — contact_name stays the load-bearing column; see migration header.';
comment on column public.deals.last_name is
  'Split from contact_name (CRM Depth Stage 2). Nullable, no backfill — see migration header.';
comment on column public.deals.service_address_street is
  'Structured service address (Stage 2) — independent of project_address (Stage 1, still live). See migration header note.';
comment on column public.deals.intake_checklist is
  'Written incrementally by Stage 3''s command-stage engine (not designed yet) — no RPC wiring in this migration.';
comment on column public.deals.owner_id is
  'Rep assignment — references profiles(id), not org_members (no single-column PK). Nullable; wiring is Stage 5 (Ownership & attribution).';

-- ============================================================================
-- 2. create_deal — DROP the exact live 12-arg signature first (confirmed
-- via pg_get_function_identity_arguments against live pg_proc), then
-- recreate with the new params appended.
-- ============================================================================
drop function if exists public.create_deal(uuid, text, text, text, text, numeric, text, int, text, text, text, text);

create or replace function public.create_deal(
  p_org_id uuid,
  p_contact_name text default null,
  p_company text default null,
  p_email text default null,
  p_phone text default null,
  p_value numeric default null,
  p_trade text default null,
  p_crew_size int default null,
  p_source text default 'manual',
  p_lead_type text default null,
  p_project_address text default null,
  p_billing_address text default null,
  p_first_name text default null,
  p_last_name text default null,
  p_secondary_phone text default null,
  p_remodel_or_new_construction text default null,
  p_existing_roof_type text[] default null,
  p_roof_type_requested text[] default null,
  p_service_address_street text default null,
  p_service_address_city text default null,
  p_service_address_state text default null,
  p_service_address_zip text default null,
  p_referral_name text default null,
  p_owner_id uuid default null,
  p_tags text[] default null
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
  v_contact_name text;
begin
  if p_org_id not in (select my_org_ids()) then
    raise exception 'not a member of organization %', p_org_id;
  end if;

  -- p_contact_name is now optional (was required) so a Stage 4 caller can
  -- supply only first/last — but the column itself is still NOT NULL, so
  -- one of the two paths has to resolve to a real value. Stage 1's form,
  -- which always sends p_contact_name, is unaffected: that branch wins
  -- whenever it's provided.
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

  insert into public.deal_activity (deal_id, org_id, action, to_value)
  values (v_deal_id, p_org_id, 'created', p_source);

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

    insert into public.deal_activity (deal_id, org_id, action, to_value)
    values (v_deal_id, p_org_id, 'followup_scheduled', 'day-' || v_cadence[1] || ' + day-' || v_cadence[2]);
  end if;

  return v_deal_id;
end;
$$;

comment on function public.create_deal(uuid, text, text, text, text, numeric, text, int, text, text, text, text, text, text, text, text, text[], text[], text, text, text, text, text, uuid, text[]) is
  'Pipeline insert RPC. p_contact_name is now optional (falls back to first_name+last_name; one of the two is required — the column is NOT NULL). Extended CRM Depth Stage 2 with the full lead data model minus intake_checklist/milestones (Stage 3''s job).';

-- ============================================================================
-- 3. update_deal_details — DROP the exact live 11-arg signature first,
-- then recreate with the new params appended. Same contact_name
-- precedence logic as create_deal.
-- ============================================================================
drop function if exists public.update_deal_details(uuid, text, text, text, text, numeric, text, int, text, text, text);

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
  p_billing_address text default null,
  p_first_name text default null,
  p_last_name text default null,
  p_secondary_phone text default null,
  p_remodel_or_new_construction text default null,
  p_existing_roof_type text[] default null,
  p_roof_type_requested text[] default null,
  p_service_address_street text default null,
  p_service_address_city text default null,
  p_service_address_state text default null,
  p_service_address_zip text default null,
  p_referral_name text default null,
  p_owner_id uuid default null,
  p_tags text[] default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_derived_contact_name text;
begin
  select org_id into v_org_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  -- Explicit p_contact_name wins (Stage 1's edit form sends only this —
  -- unaffected). Otherwise, if first/last are given, derive it. Otherwise
  -- leave contact_name as-is.
  v_derived_contact_name := coalesce(
    nullif(trim(p_contact_name), ''),
    nullif(trim(concat_ws(' ', p_first_name, p_last_name)), '')
  );

  update public.deals
  set contact_name = coalesce(v_derived_contact_name, contact_name),
      company = coalesce(p_company, company),
      email = coalesce(p_email, email),
      phone = coalesce(p_phone, phone),
      value = coalesce(p_value, value),
      trade = coalesce(p_trade, trade),
      crew_size = coalesce(p_crew_size, crew_size),
      lead_type = coalesce(p_lead_type, lead_type),
      project_address = coalesce(p_project_address, project_address),
      billing_address = coalesce(p_billing_address, billing_address),
      first_name = coalesce(p_first_name, first_name),
      last_name = coalesce(p_last_name, last_name),
      secondary_phone = coalesce(p_secondary_phone, secondary_phone),
      remodel_or_new_construction = coalesce(p_remodel_or_new_construction, remodel_or_new_construction),
      existing_roof_type = coalesce(p_existing_roof_type, existing_roof_type),
      roof_type_requested = coalesce(p_roof_type_requested, roof_type_requested),
      service_address_street = coalesce(p_service_address_street, service_address_street),
      service_address_city = coalesce(p_service_address_city, service_address_city),
      service_address_state = coalesce(p_service_address_state, service_address_state),
      service_address_zip = coalesce(p_service_address_zip, service_address_zip),
      referral_name = coalesce(p_referral_name, referral_name),
      owner_id = coalesce(p_owner_id, owner_id),
      tags = coalesce(p_tags, tags),
      updated_at = now()
  where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action)
  values (p_deal_id, v_org_id, 'details_updated');
end;
$$;
