-- StructTech OS — P0.5 proper fix: update_deal_fields(uuid, jsonb)
--
-- NOT APPLIED. Author-only migration file — ask before applying, same as
-- every other migration in this repo. This one especially: touches
-- Isaac's live CRM data path.
--
-- Replaces update_deal_details' 24-scalar-parameter, coalesce-based design
-- (confirmed live-broken, BACKLOG.md P0.5, 7/23 — clearing email/phone/
-- most scalar fields silently no-ops) with a single jsonb patch: key
-- ABSENT means untouched, key PRESENT (including explicit JSON null or
-- '') means write it — clearing finally works.
--
-- ============================================================================
-- SECURITY — the part to review before anything else
-- ============================================================================
-- The patch is a jsonb blob from the client. Without an allowlist, a
-- caller could include "org_id" and move a deal into another tenant, or
-- "owner_id" and bypass assign_deal_owner's dedicated authorization path,
-- or "id"/"created_at" and corrupt the row's identity/history. v_allowed
-- below is the only thing standing between "patch my email" and "patch
-- any column on this table." Enforcement is a hard loop over
-- jsonb_object_keys(p_patch): ANY key not in v_allowed raises and aborts
-- the whole call — no partial-apply, no silent drop of the bad key. This
-- is deliberately a reject, not a filter: a patch containing an
-- unexpected key is either a client bug or an attack, and both should
-- fail loudly.
--
-- v_allowed is exactly the column set update_deal_details already exposed
-- (nothing added, nothing removed) — this migration fixes clear semantics,
-- it does not expand what's editable:
--   contact_name, company, email, phone, value, trade, crew_size,
--   lead_type, project_address, billing_address, first_name, last_name,
--   secondary_phone, remodel_or_new_construction, existing_roof_type,
--   roof_type_requested, service_address_street, service_address_city,
--   service_address_state, service_address_zip, referral_name, tags
--
-- Explicitly NEVER in the allowlist, on purpose: org_id, id, owner_id
-- (ownership changes stay on assign_deal_owner, same rule the old RPC
-- enforced), created_at/updated_at, stage (has its own update_deal_stage
-- RPC), archived_at, lost_reason, proposal_tier, proposal_notes,
-- site_survey_complete_at/roof_scope_ordered_at/quote_presented_at,
-- intake_checklist, source.
--
-- ============================================================================
-- contact_name special case — flagging, not hiding
-- ============================================================================
-- Every OTHER field in the allowlist follows the letter of "present +
-- empty/null = clear." contact_name does not, on purpose, to avoid a real
-- regression: the old RPC treated an empty p_contact_name as "not
-- provided" (nullif(trim(p_contact_name), '')) and derived it from
-- first_name/last_name instead — that's what lets the Lead Control
-- Center's inline first-name/last-name edits (which never touch
-- contact_name directly) keep the display name in sync. If I made
-- contact_name a plain "present-empty-means-clear" field, clearing it
-- would just blank it instead of re-deriving, and the one place that
-- matters — EditLeadDetailsForm's "Contact name (override)" field — is
-- explicitly labeled as an override, implying "empty means fall back,"
-- not "empty means gone." So: non-empty patch.contact_name wins outright;
-- an empty/absent patch.contact_name (with first_name or last_name
-- touched) falls back to re-deriving from the (possibly just-updated)
-- first/last name, same as before. This is the one field where I chose
-- fidelity to existing behavior over the letter of the new convention —
-- flagging it explicitly rather than let it slide as an implementation
-- detail.
--
-- ============================================================================
-- Arrays (existing_roof_type/roof_type_requested/tags) — reported, not
-- guessed, per instruction. Already confirmed correct under the OLD RPC:
--   - tagList() (src/lib/crm/actions.ts) never returns undefined, only a
--     real array (possibly []) — so it never hit the coalesce-swallows-it
--     bug scalars did.
--   - coalesce('{}'::text[], existing) returns '{}' unchanged (confirmed
--     live, 7/24) — coalesce only falls through on true SQL NULL, and an
--     empty array isn't one.
-- So arrays were already clearable under the old RPC. This migration
-- preserves that AND adds a real three-way distinction the old RPC
-- couldn't express: patch key absent (untouched) vs JSON null (column set
-- to SQL NULL) vs JSON [] (column set to '{}'::text[], a real empty
-- array — NULL and '{}' read identically in every UI today, but they are
-- not the same value, and this migration doesn't collapse them). Whether
-- the LCC's multi-select should ever SEND null vs [] is a UI decision
-- left to you — the RPC just stops being unable to express the
-- difference.
--
-- ============================================================================
-- Casting — no implicit jsonb coercion
-- ============================================================================
-- value/crew_size go through nullif(p_patch->>'key', '')::type rather than
-- a bare ::cast, so a stray empty string from a numeric input (distinct
-- from JSON null) doesn't raise "invalid input syntax" — treated the same
-- as null, i.e. clear. Every text field reads via ->>' (always text,
-- never relies on jsonb's own type coercion). Arrays go through
-- jsonb_typeof() to distinguish null from [] from a populated array before
-- touching jsonb_array_elements_text (which errors on a jsonb null input).
--
-- ============================================================================
-- Sequencing — same signed/org guards as update_deal_details, but does
-- NOT drop update_deal_details in this migration. That happens in a
-- follow-up migration only after both action-layer call sites (actually
-- FOUR, not two — see below) are confirmed rewired and verified working,
-- per the overload-safety discipline from the estimating migrations.
-- ============================================================================
--
-- CORRECTION to the original ask: the ask named two call sites
-- (updateDealColumnField, updateDealDetails) but grep found FOUR real
-- callers of update_deal_details in src/lib/crm/actions.ts:
--   1. updateDealDetails       — the "Edit lead details" full form
--   2. updateDealColumnField   — the LCC inline checklist row (Isaac's path)
--   3. updateDealTags          — the tags editor
--   4. updateDealServiceAddress — the composite 4-field address form
-- All four must move to update_deal_fields before update_deal_details can
-- be dropped, or #3/#4 break outright the moment it's gone.

create or replace function public.update_deal_fields(p_deal_id uuid, p_patch jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
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

  -- NULL-authorization gap (caught in review): v_owner_id is NULL on an
  -- unowned deal, so `v_owner_id = auth.uid()` evaluates to NULL rather
  -- than false for a non-manager — and PL/pgSQL treats a NULL IF condition
  -- as false, so `if not (false or NULL)` = `if not NULL` = `if NULL` skips
  -- the raise entirely. Any authenticated org member could edit an unowned
  -- deal. coalesce(..., false) forces the comparison to a real boolean.
  if not (public.is_org_manager(v_org_id) or coalesce(v_owner_id = auth.uid(), false)) then
    raise exception 'not authorized: only the deal owner or an org manager can edit this deal';
  end if;

  -- Allowlist enforcement — reject the whole patch on any unlisted key.
  for v_key in select jsonb_object_keys(p_patch) loop
    if not (v_key = any(v_allowed)) then
      raise exception 'field not writable via patch: %', v_key;
    end if;
  end loop;

  select id into v_actor_id from public.profiles where id = auth.uid();

  update public.deals
  set
    -- contact_name: see the header note above — the one field that keeps
    -- its old "empty falls back to derived" behavior rather than "empty
    -- clears," to preserve EditLeadDetailsForm's override semantics.
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

-- update_deal_details is UNTOUCHED here — still live, still called by all
-- four existing action-layer call sites, still has the coalesce bug. The
-- app-code rewiring (all four call sites) happens after this function
-- exists; update_deal_details gets dropped in a separate follow-up
-- migration once that rewiring is verified, never in the same step.
