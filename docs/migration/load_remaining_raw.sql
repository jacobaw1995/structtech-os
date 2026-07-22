-- BMR migration — finish loading raw staging tables.
--
-- Status as of 7/19 (Claude's session): profiles (2/2) and lead_notes (171/171)
-- are fully loaded. lead_activity is partially loaded (240/587) — this script
-- re-loads the WHOLE file safely (idempotent via `on conflict do nothing`, so
-- the 240 already-loaded rows are silently skipped, not duplicated). leads
-- is not loaded at all yet.
--
-- HOW TO RUN: Supabase Studio (os.structek.com's project, ejlhrykcdfcyeooooodx)
-- -> SQL Editor -> paste ONE block below at a time -> replace
-- <PASTE lead_activity.json HERE> / <PASTE leads.json HERE> with the full,
-- exact contents of that file (open it in a text editor, select all, copy,
-- paste in place of the placeholder — keep the $json$ ... $json$ wrapper
-- around it) -> Run. Repeat for the other file. No chunking needed; the SQL
-- editor doesn't have the token limits I was hitting.
--
-- After both run, confirm counts:
--   select count(*) from public.migration_bmr_leads_raw;      -- expect 188
--   select count(*) from public.migration_bmr_activity_raw;   -- expect 587
-- Then bmr_transform.sql's dry run is ready to go.

-- ============================================================================
-- 1. Finish lead_activity (347 rows remaining, but safe to paste all 587)
-- ============================================================================
insert into public.migration_bmr_activity_raw (old_id, payload)
select (elem->>'id')::uuid, elem
from jsonb_array_elements($json$
<PASTE lead_activity.json HERE>
$json$::jsonb) as elem
on conflict (old_id) do nothing;

select count(*) from public.migration_bmr_activity_raw;

-- ============================================================================
-- 2. Load leads (188 rows, none loaded yet)
-- ============================================================================
insert into public.migration_bmr_leads_raw (old_id, payload)
select (elem->>'id')::uuid, elem
from jsonb_array_elements($json$
<PASTE leads.json HERE>
$json$::jsonb) as elem
on conflict (old_id) do nothing;

select count(*) from public.migration_bmr_leads_raw;
