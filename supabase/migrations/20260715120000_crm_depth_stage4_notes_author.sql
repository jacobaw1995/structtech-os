-- StructTech OS — CRM Depth Stage 4: Lead Notes author attribution
--
-- NOT APPLIED. Review before apply.
--
-- Reconciliation note: update_deal_details already carries every Stage-2
-- column (first_name/last_name/existing_roof_type/roof_type_requested/
-- remodel_or_new_construction/service_address_*/referral_name/owner_id/
-- tags) as of the Stage 2 migration — confirmed live via pg_proc before
-- writing this file. Stage 4's TS server actions just weren't calling it
-- with those params yet. So there is NO RPC signature change needed here,
-- and therefore no DROP FUNCTION — this migration only touches
-- add_deal_note, whose signature (p_deal_id, p_content) is unchanged, so
-- CREATE OR REPLACE is safe (same arg list = no overload).
--
-- deal_notes.created_by: nullable, per Jacob's explicit instruction —
-- verified live that auth.users (2 rows) and profiles (1 row) are NOT
-- 1:1 today (1 user has no profiles row). A NOT NULL / hard-required FK
-- would make add_deal_note fail outright for that user. Instead:
--   - column is a plain nullable FK to profiles(id), no default clause
--     that could itself fail.
--   - add_deal_note resolves created_by via
--     (select id from profiles where id = auth.uid()), which evaluates
--     to NULL (not an error) when the calling user has no profiles row —
--     the note still saves, just without attribution, instead of the
--     whole insert failing.
-- This starts recording real attribution now for users who DO have a
-- profile (today: the one seeded agency_admin), without requiring the
-- Stage 5 user-account work to land first, and needs no backfill once it
-- does.

alter table public.deal_notes
  add column created_by uuid references public.profiles(id);

create or replace function public.add_deal_note(p_deal_id uuid, p_content text)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_org_id uuid;
  v_note_id uuid;
  v_created_by uuid;
begin
  select org_id into v_org_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  select id into v_created_by from public.profiles where id = auth.uid();

  insert into public.deal_notes (deal_id, org_id, content, created_by)
  values (p_deal_id, v_org_id, p_content, v_created_by)
  returning id into v_note_id;

  insert into public.deal_activity (deal_id, org_id, action, to_value)
  values (p_deal_id, v_org_id, 'note_added', left(p_content, 140));

  return v_note_id;
end;
$function$;
