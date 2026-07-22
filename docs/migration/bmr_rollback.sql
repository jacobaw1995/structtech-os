-- BMR data migration — UNDO script.
--
-- NOT APPLIED. Only run this if the loaded migration needs to be reversed
-- after COMMIT — ask before applying, same rule as every migration in this
-- repo. This is a one-time DATA operation, not a schema migration, so it
-- lives here (docs/migration/), not in supabase/migrations/.
--
-- Context: docs/reference/BMR_DATA_MIGRATION_PLAN.md §3 ("provenance +
-- idempotency"). migration_bmr_id_map is the exact record of every row this
-- migration created (entity + old_id -> new_id) — this script deletes only
-- those rows, by id, nowhere else. It can never touch:
--   - the ~8 pre-existing BMR deals (their ids are not in migration_bmr_id_map)
--   - anything Isaac creates after go-live (also not in the map)
--
-- Order matters: children before parents, so no FK violations —
-- deal_activity and deal_notes both reference deals.id.
--
-- HOW TO RUN: BEGIN; \i bmr_rollback.sql   inspect the row counts it prints,
-- then COMMIT (or ROLLBACK to abort). Re-running after a successful rollback
-- is a no-op (the deletes just match zero rows the second time).

-- ============================================================================
-- 1. deal_activity (child — references deals.id)
-- ============================================================================
delete from public.deal_activity
where id in (
  select new_id from public.migration_bmr_id_map where entity = 'activity'
);

-- ============================================================================
-- 2. deal_notes (child — references deals.id)
-- ============================================================================
delete from public.deal_notes
where id in (
  select new_id from public.migration_bmr_id_map where entity = 'note'
);

-- ============================================================================
-- 3. deals (parent)
-- ============================================================================
delete from public.deals
where id in (
  select new_id from public.migration_bmr_id_map where entity = 'lead'
);

-- ============================================================================
-- 4. Verify — should all read 0 before clearing the map.
-- ============================================================================
select
  (select count(*) from public.deals d join public.migration_bmr_id_map m on m.entity = 'lead' and m.new_id = d.id) as remaining_deals,
  (select count(*) from public.deal_notes n join public.migration_bmr_id_map m on m.entity = 'note' and m.new_id = n.id) as remaining_notes,
  (select count(*) from public.deal_activity a join public.migration_bmr_id_map m on m.entity = 'activity' and m.new_id = a.id) as remaining_activity;

-- ============================================================================
-- 5. Optional — clear the id_map rows for lead/note/activity once the above
--    all read 0. Leaves the 'user' identity-map rows intact (harmless,
--    reusable if the migration is re-run later) unless you want a fully
--    clean slate, in which case delete those too (uncomment the last line).
-- ============================================================================
delete from public.migration_bmr_id_map where entity in ('lead', 'note', 'activity');
-- delete from public.migration_bmr_id_map where entity = 'user';
