-- StructTech OS — Phase A Week 1: assistant capability role, chunk 3 of 5.
--
-- NOT APPLIED. Author-only migration file — ask before applying.
--
-- Interaction 2 from the resolved design (roadmap "Assistant role —
-- capability flags (hide $)" / BACKLOG.md (c)): create_estimate_from_deal
-- rejects when !create_estimates. This is the DB half of chunk 3; the app
-- half (nav/route-guard capability filtering in getWorkspaceContext, the
-- split view_estimates/create_estimates gating in the CRM page + Lead
-- Control Center, and closing a pre-existing gap in the estimate PDF route
-- that had no module/capability check at all) is separate file diffs, not
-- migrations.
--
-- Verified live before writing this file: create_estimate_from_deal
-- currently has NO role/capability gate whatsoever — any org member can
-- call it. This migration adds the FIRST gate on it. Verified against
-- pg_proc that this is the only live overload (single uuid arg), so
-- CREATE OR REPLACE with the unchanged signature is safe, no drop-first
-- needed.
--
-- Safety check done before drafting this migration: queried live
-- org_members — only 3 rows exist today (Jacob as agency_admin/BMR +
-- owner/StructTech, Isaac as owner/BMR), all manager-tier. has_capability()
-- always returns true for manager-tier roles, so this gate is a true no-op
-- for every real user that exists right now. No non-manager ("office"/
-- "member") user is live yet to regress — the assistant hire this whole
-- feature is for hasn't been seeded (BACKLOG.md: seeding is the deliberately
-- held last step).
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

  -- Atomic claim: INSERT ... ON CONFLICT takes a row lock on the counter
  -- row, so two concurrent creates for the same org can't claim the same
  -- number. First-ever call for an org inserts next_number=2 and returns
  -- 2-1=1; every later call updates next_number=N+1 and returns (N+1)-1=N
  -- (the value the counter held before this call) — same claimed-value-
  -- then-bump semantics either way.
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
