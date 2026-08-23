-- StructTech OS — Estimate builder rebuild, Chunk 3: document-field RPC
--
-- NOT APPLIED. Author-only migration file — ask before applying, same as
-- every other migration in this repo.
--
-- Chunk 1 added estimate_date/valid_until/tax_rate/notes_terms as columns
-- but deliberately left them without a write path — that migration's scope
-- was line-item RPCs only. Chunk 3 (inline editing) now needs one: extends
-- update_estimate_details() rather than adding a new RPC, since it's
-- already the "edit estimate document fields" RPC (squares/pitch/
-- site_address) with the exact same signed/void-only gate these new
-- fields need.
--
-- OVERLOAD TRAP (same lesson as Chunk 1's add/update_estimate_line_item):
-- appending new parameters changes the signature, so CREATE OR REPLACE
-- alone would leave the old 4-arg version live as a second overload. Live
-- signature confirmed against pg_proc before writing this drop:
--   update_estimate_details(p_estimate_id uuid, p_squares numeric, p_pitch text, p_site_address text)
--
-- Same coalesce-based "null means no change" convention as every other
-- update RPC here — accepted for notes_terms (empty string and null render
-- identically, falling back to branding.terms either way) and estimate_date
-- (always set, no legitimate "clear to nothing" case). NOT accepted for
-- tax_rate/valid_until: these can be set and then never removed, only
-- changed to another value — a real SCOPE §2.6 violation on a
-- customer-facing money field once a tax rate is on the document. Same
-- root cause flagged system-wide in BACKLOG.md's new P0.5 (confirmed live
-- in update_deal_details, 7/23) — that item explicitly says "decide once
-- and apply consistently, don't fix it per-field forever," so this is a
-- narrow, justified exception for the two fields that are one-way doors
-- today, not a precedent for solving the general problem here.
--
-- p_clear_valid_until / p_clear_tax_rate: explicit boolean flags, matching
-- the fix-options convention BACKLOG.md itself names. Default false so
-- every existing call site (and every other field on this RPC) is
-- unaffected — only a caller that explicitly sets the flag can null the
-- column out.

drop function if exists public.update_estimate_details(uuid, numeric, text, text);

create or replace function public.update_estimate_details(
  p_estimate_id uuid,
  p_squares numeric default null,
  p_pitch text default null,
  p_site_address text default null,
  p_estimate_date date default null,
  p_valid_until date default null,
  p_tax_rate numeric default null,
  p_notes_terms text default null,
  p_clear_valid_until boolean default false,
  p_clear_tax_rate boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
