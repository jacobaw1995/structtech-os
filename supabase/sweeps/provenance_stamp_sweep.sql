-- =============================================================================
-- PROVENANCE-STAMP SWEEP — "a write that changes no value must not change who decided it, when, or how".
-- Track S · first run 2026-09-15. READ-ONLY (sections 0-1). Safe against production.
--
-- THE RULE (controller, 2026-09-15, generalising §7.1 rule 8): A WRITE THAT CHANGES NO VALUE MUST NOT
-- CHANGE WHO DECIDED IT, WHEN, OR HOW. Fourth instance of the shape: catalog `sell` re-send (9/12),
-- material `ready_by` re-send (9/12), schedule block date re-send (9/14), take-off decision re-save (9/15).
--
-- THE INSTRUMENT DOES NOT GRADE. IT NARROWS. Section 1 finds every function that uses auth.uid()/now()
-- AND can touch an existing row or write an activity row. The grade below is from READING each body and,
-- where cheap, a rolled-back behavioural probe. `compares_old_new` is a hint, not a grade: a guard can be
-- written as `where accepted_at is null` or `coalesce(voided_at, now())` without the words DISTINCT FROM.
--
-- CALIBRATION TRAP, FOUND ON THE FIRST RUN: now() is the TRANSACTION timestamp. Calling a function twice
-- inside one rolled-back transaction and comparing its timestamp column is an EMPTY INSTRUMENT — it cannot
-- move. present_estimate read SAFE that way and BREAKS when the column is seeded to a past value first.
-- Probe a timestamp stamp by seeding the column to a past value; probe an actor stamp by counting rows.
--
-- FIRST RUN, 2026-09-15 — DENOMINATOR: 169 sql/plpgsql functions in public (not wh_*) · 88 use auth.uid()
-- or now() · 63 of those can change an existing row or write an activity row — THE POPULATION.
--
--  CLASS A · a decision/provenance column on an existing row (who/when/how decided)          19
--    FIXED   2   set_take_off_decision, generate_take_off   (20260915220533; proved before and after)
--    BREAKS  4   archive_deal (archived_at), archive_tracker_item, archive_tracker_project (archived_at),
--                present_estimate (presented_at — PROBED: seeded 2020, re-present rewrote to now)
--    SAFE   13   accept_invite, accept_pipeline_invite, accept_staff_invite (where accepted_at is null);
--                void_work_order (coalesce(voided_at, now())); record_work_order_sign_off (coalesce + distinct);
--                revoke_estimate_sign_link (if v_revoked is null); sign_estimate + signatures_guard_insert
--                (a second signature is refused); signatures_after_insert, create_estimate_sign_link,
--                material_items_take_off_removed, materialize_take_off (each writes on a real event only);
--                deal_stage_side_effects (closed_at and activity only when new.stage <> old.stage)
--  CLASS B · an activity row attributing an ACTOR to the call                                  13
--    BREAKS  7   assign_deal_owner (PROBED: assigning the current owner writes a new owner_assigned row),
--                update_deal_fields (PROBED: an empty patch writes details_updated), restore_deal,
--                complete_site_survey, order_scope, present_quote, update_material_item (after sign-off)
--    SAFE    6   add_deal_note, add_material_item, delete_material_item, auto_create_deal, create_deal
--                (each is a real insert/delete); update_purchase_order_line (promise row only when distinct)
--  CLASS C · only updated_at, bumped on every call including a no-op                          31
--    NOT GRADED AGAINST THE RULE — NEEDS A RULING: is updated_at "when it was decided"? Read literally, all
--    31 break it; read as "when the row was last written", none does. Named, not fixed.
--    add_check_in_photo, add_production_packet_callout, bmr_ticket_touch, delete_production_packet_callout,
--    estimate_line_items_sync_subtotal, products_touch_updated_at, protect_roadmap_columns,
--    recompute_material_item_ready_by, remove_check_in_photo, reorder_estimate_line_items,
--    restore_tracker_item, restore_tracker_project, restore_work_order, set_tenant_module, update_check_in,
--    update_deal_stage, update_estimate_build_mode, update_estimate_contact, update_estimate_details,
--    update_estimate_line_item, update_intake_checklist_field, update_production_packet_callout,
--    update_production_packet_notes, update_purchase_order, update_roadmap_fields, update_roadmap_project,
--    update_schedule_block, update_tracker_item, update_tracker_project, upsert_estimate_scope_line_items,
--    void_estimate
--  UNGRADED 0.
--
-- ============================== STATUS — SWEEP CLOSED 2026-09-17 ==============================
--  CLASS A  19: FIXED 6 (the 2 take-off functions, 20260915220533; archive_deal, archive_tracker_item,
--               archive_tracker_project, present_estimate, 20260916214749), SAFE 13. BREAKS 0.
--  CLASS B  13: BREAKS 7 — NOT DONE. Scheduled for the week of 2026-09-21 (controller, 2026-09-17), not "pending":
--               assign_deal_owner, update_deal_fields, restore_deal, complete_site_survey, order_scope,
--               present_quote, update_material_item. SAFE 6.
--  CLASS C  31: RULED OUT OF SCOPE (controller, 2026-09-17): updated_at is not provenance — UNLESS a surface
--               renders it to a human as "last changed by/at". Measured in src/ at f7a8509: TWO surfaces do —
--               the Build page (roadmap_items updated_by · updated_at; writer update_roadmap_fields) and the
--               client roadmap page ("Last updated"; writer protect_roadmap_columns). Both BROKE (proved,
--               synthetic, rolled back) and both are FIXED in 20260918004138. The other 29 are out of scope.
--               A new surface that renders updated_at to a person reopens this class for its writers.
--
-- LIVE EXPOSURE of the class-B BREAKS, measured: 330 owner_assigned rows, 0 with from_value = to_value
-- (so no no-op assignment has been recorded yet — the UI has not sent one); 21 details_updated rows,
-- whether any were no-ops is UNANSWERABLE (no before-values are stored); 0 archived / 0 restored rows.
-- =============================================================================

-- 0 · DENOMINATOR
with f as (
  select p.proname, regexp_replace(p.prosrc, '--[^\n]*', '', 'g') src
  from pg_proc p join pg_language l on l.oid = p.prolang join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and l.lanname in ('plpgsql','sql') and p.proname !~ '^wh_'
)
select count(*) as functions,
       count(*) filter (where src ~* '(auth\.uid\(\)|now\(\)|current_timestamp)') as use_actor_or_clock,
       count(*) filter (where src ~* '(auth\.uid\(\)|now\(\)|current_timestamp)'
                          and (src ~* '\mupdate\s+(public\.)?[a-z_]+\s+set'
                               or src ~* 'on\s+conflict[^;]*do\s+update'
                               or src ~* 'new\.[a-z_]+\s*:='
                               or src ~* 'insert\s+into\s+(public\.)?[a-z_]*activity')) as population
from f;

-- 1 · THE POPULATION, with the hints a reader needs
with f as (
  select p.proname, p.prorettype = 'trigger'::regtype as is_trigger,
         regexp_replace(p.prosrc, '--[^\n]*', '', 'g') src
  from pg_proc p join pg_language l on l.oid = p.prolang join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and l.lanname in ('plpgsql','sql') and p.proname !~ '^wh_'
)
select proname, is_trigger,
  (select array_agg(distinct m[1]) from regexp_matches(src,
     '(?i)\m([a-z_]*(?:_at|_by|actor_id|source))\M\s*(?:=|:=)\s*(?:now\(\)|auth\.uid\(\)|v_actor[a-z_]*|excluded\.[a-z_]+|''[a-z_]+'')', 'g') m) as stamped_columns,
  src ~* 'insert\s+into\s+(public\.)?[a-z_]*activity' as logs_activity,
  src ~* 'is\s+(not\s+)?distinct\s+from|coalesce\(\s*[a-z_]+_at\s*,|[a-z_]+_at\s+is\s+null' as has_a_guard_shape,
  case
    when (select array_agg(distinct m[1]) from regexp_matches(src, '(?i)\m([a-z_]*(?:_at|_by|actor_id|source))\M\s*(?:=|:=)', 'g') m)
         <@ array['updated_at'] then 'C — updated_at only'
    when src ~* 'insert\s+into\s+(public\.)?[a-z_]*activity'
         and not (src ~* '\m(decided|revoked|archived|presented|accepted|voided|signed|closed|item_removed|used)_(at|by)\M') then 'B — activity actor'
    else 'A — decision/provenance'
  end as class_hint
from f
where src ~* '(auth\.uid\(\)|now\(\)|current_timestamp)'
  and (src ~* '\mupdate\s+(public\.)?[a-z_]+\s+set' or src ~* 'on\s+conflict[^;]*do\s+update'
       or src ~* 'new\.[a-z_]+\s*:=' or src ~* 'insert\s+into\s+(public\.)?[a-z_]*activity')
order by class_hint, proname;
