-- StructTech OS — CRM Depth Stage 3: command-stage + checklist engine
--
-- NOT APPLIED. Author-only migration file — ask before applying, same as
-- every other migration in this repo. Depends on Stage 2 (20260714150000)
-- already being applied. No 3-panel UI in this migration (CLAUDE.md
-- Stage 4 owns that) — this is schema + RPC mechanism only. The pure
-- computation (job-path derivation, checklist completion, gating,
-- recommended next action) lives in client-safe TS
-- (src/lib/crm/command-center.ts / intake-checklist.ts / scope-fields.ts),
-- not duplicated here in SQL.
--
-- ============================================================================
-- 1. lead_type: homeowner/company -> 4-value customer type
-- ============================================================================
-- Confirmed against live pg_constraint before writing this: the existing
-- constraint is named deals_lead_type_check, current def
-- CHECK ((lead_type = ANY (ARRAY['homeowner'::text, 'company'::text]))).
-- Current data (checked live): 3 'homeowner', 6 null, 0 'company' — the
-- UPDATE below is a no-op today but stays in as a correct, defensive step
-- regardless of when this actually applies.
alter table public.deals drop constraint deals_lead_type_check;

update public.deals set lead_type = 'commercial' where lead_type = 'company';

alter table public.deals add constraint deals_lead_type_check
  check (lead_type in ('homeowner', 'contractor', 'property_management', 'commercial'));

comment on column public.deals.lead_type is
  'Customer type: homeowner | contractor | property_management | commercial. Widened from the Stage 1 2-value (homeowner/company) set — commercial absorbs the old ''company'' value. Labels (e.g. "Contractor (GC)") live in src/lib/crm/command-center.ts, not the DB.';

-- ============================================================================
-- 2. update_intake_checklist_field — the ONE generic RPC covering both
-- checklists (intake-call fields are top-level keys, e.g. ['main_issue'];
-- site-visit-scope and estimate-input fields are one level deeper, e.g.
-- ['site_visit_scope','roof_area_sqft']). jsonb_set with create_missing
-- means the first write to a not-yet-existing nested object (e.g.
-- site_visit_scope) creates it, rather than requiring it to pre-exist.
--
-- Deliberately does NOT log deal_activity — every field-blur during an
-- intake call would flood the activity log (14+ entries for one call);
-- matches how estimate/material line-item edits already don't log there.
--
-- p_field_path length is capped at 2 (a light defensive check, not a key
-- whitelist — the actual set of valid keys lives in the TS field registry,
-- deliberately not duplicated here to avoid the two drifting apart).
-- ============================================================================
create or replace function public.update_intake_checklist_field(
  p_deal_id uuid,
  p_field_path text[],
  p_value jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  if array_length(p_field_path, 1) is null or array_length(p_field_path, 1) not between 1 and 2 then
    raise exception 'p_field_path must have 1 or 2 elements, got %', p_field_path;
  end if;

  select org_id into v_org_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  update public.deals
  set intake_checklist = jsonb_set(intake_checklist, p_field_path, p_value, true),
      updated_at = now()
  where id = p_deal_id;
end;
$$;

comment on function public.update_intake_checklist_field(uuid, text[], jsonb) is
  'Incremental (field-by-field, not blob-overwrite) writer for deals.intake_checklist — the mechanism behind both the intake-call and site-visit-scope checklists. No deal_activity log (see header note).';

-- ============================================================================
-- 3. Milestone RPCs — complete_site_survey / order_scope / present_quote.
-- Each sets its own timestamp column, defaulting to now() when the param
-- is omitted, but CLEARING it if the param is explicitly passed as null
-- (PostgREST distinguishes "key absent" from "key present with JSON
-- null" — the former uses the SQL default, the latter overrides it). That
-- gives full set+clear CRUD in one RPC without a separate undo action.
--
-- None of these hard-gate on checklist completion (e.g. order_scope does
-- NOT check the scope checklist is 100%) — these are brand new RPCs with
-- no existing callers to break, so gating here would be safe, but there's
-- no UI yet to explain a rejection to the user. Gating stays computed-only
-- in the TS engine (canAdvance-style helpers) for Stage 4 to enforce.
-- Likewise, none of these touch deals.stage (the kanban column) or
-- update_deal_stage's behavior — that RPC is live and unrestricted today,
-- unchanged by this migration.
-- ============================================================================
create or replace function public.complete_site_survey(
  p_deal_id uuid,
  p_completed_at timestamptz default now()
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
  set site_survey_complete_at = p_completed_at,
      updated_at = now()
  where id = p_deal_id;
end;
$$;

create or replace function public.order_scope(
  p_deal_id uuid,
  p_ordered_at timestamptz default now()
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
  set roof_scope_ordered_at = p_ordered_at,
      updated_at = now()
  where id = p_deal_id;
end;
$$;

create or replace function public.present_quote(
  p_deal_id uuid,
  p_presented_at timestamptz default now()
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
  set quote_presented_at = p_presented_at,
      updated_at = now()
  where id = p_deal_id;
end;
$$;

comment on function public.complete_site_survey(uuid, timestamptz) is
  'Sets/clears deals.site_survey_complete_at. Explicit null param clears it; omitted param defaults to now(). No completion gating — see migration header.';
comment on function public.order_scope(uuid, timestamptz) is
  'Sets/clears deals.roof_scope_ordered_at. Explicit null param clears it; omitted param defaults to now(). No completion gating — see migration header.';
comment on function public.present_quote(uuid, timestamptz) is
  'Sets/clears deals.quote_presented_at. Explicit null param clears it; omitted param defaults to now(). No completion gating — see migration header.';
