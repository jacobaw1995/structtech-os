-- ============================================================================
-- X-W1.13 PHASE A GRADING — AS APPLIED BY TRACK S, AMENDED BY CONTROLLER RULINGS.
-- Applied 2026-09-14 (America/New_York) to the live database with execute_sql, in one DO block.
-- This file records exactly what ran. It is DATA, not schema, so it has no ledger row.
--
-- Source proposal: supabase/proposals/20260914_x_w1_13_build_module_phase_a_grading.sql on
-- origin/track-x (commit ee6b549), not yet on main.
--
-- AMENDMENTS (controller rulings 2026-09-14):
--   · #26 take-off: X graded SHIPPED -> applied as IN_PROGRESS ("a function that exists and is wrong
--     is not shipped"; stays in_progress until Track U's review surface exists).
--   · #27 purchase orders: -> in_progress (X and the ruling agree).
--   · #25 catalog and #30 Material Matrix integration LEAVE PHASE A ENTIRELY (phase -> 'later').
--     #25 keeps X's object grade (shipped); #30 stays planned.
--   · #33 assistant capability flags: X's grade (shipped) applied unamended.
--
-- MEASURED BEFORE (identical to X's header): A 5 shipped / 2 in_progress / 37 planned (44).
-- MEASURED AFTER:  A 6 shipped / 3 in_progress / 33 planned (42); later 1 shipped / 1 in_progress /
--                  18 planned (20); B 4, C 5, D 6, now 24 unchanged.
-- REPLAY: every move is keyed on the primary key AND the status and phase it was graded at, and raises
-- unless exactly one row changes, so replaying this against the board today raises on the first move.
-- ============================================================================

do $$
declare n int;
begin
  update public.roadmap_items
     set status = 'shipped',
         notes = coalesce(notes,'') || E'\n\n2026-09-14 (X-W1.13 graded by object; applied by Track S) — SHIPPED. set_member_capability() writes org_members.permissions; can_view_financials() gates restrictive "no dollars in the field" policies (4 when graded; 12 tables after Track S extended the guard the same day — 20260915003141); route /w/[orgId]/settings/permissions with MemberCapabilityEditor. Migration 20260911233218. No assistant member exists in production yet, so the 7/29 note''s real-login check has not happened — onboarding, not build.',
         updated_at = now()
   where id = '86244cac-c02d-4e1b-87f6-e678a6c6715b' and status = 'in_progress' and phase = 'A';
  get diagnostics n = row_count; if n <> 1 then raise exception '#33: expected 1 row, changed %', n; end if;

  update public.roadmap_items
     set status = 'in_progress',
         notes = coalesce(notes,'') || E'\n\n2026-09-14 (X-W1.13 graded SHIPPED by object; AMENDED by controller ruling, applied by Track S) — IN PROGRESS, NOT SHIPPED. A function that exists and is wrong is not shipped. Spine built and proved 2026-09-14 (20260914230647): take_off_decisions, take_off_lines, one material per estimate line, removal remembered, table guards; conditions 1-5 proved, edges listed NOT PROVED in the directive. One creation path (20260915005153): set_take_off_decision + materialize_take_off; generate_take_off is a compatibility entry to be dropped with the review surface. Stays in_progress until Track U''s review surface (undecided lines resolved by a human) exists.',
         updated_at = now()
   where id = '89a580fd-c3d8-4e90-84f9-c2ac8277a00f' and status = 'planned' and phase = 'A';
  get diagnostics n = row_count; if n <> 1 then raise exception '#26: expected 1 row, changed %', n; end if;

  update public.roadmap_items
     set status = 'in_progress',
         notes = coalesce(notes,'') || E'\n\n2026-09-14 (X-W1.13 graded by object; applied by Track S) — IN PROGRESS, NOT SHIPPED. Promise side built: purchase_orders, purchase_order_lines, purchase_order_line_promises; route /w/[orgId]/coordination/po/[poId]; migrations 20260907230009, 20260910215139, 20260911234338 (and 20260915002733 closed a TRUNCATE hole on all three tables). Actual side has no write path: purchase_order_lines.actual_date is referenced by zero functions and zero src files.',
         updated_at = now()
   where id = 'd60c5c1f-e91d-41ca-b075-2d1fa6e14f58' and status = 'planned' and phase = 'A';
  get diagnostics n = row_count; if n <> 1 then raise exception '#27: expected 1 row, changed %', n; end if;

  update public.roadmap_items
     set phase = 'later', status = 'shipped',
         notes = coalesce(notes,'') || E'\n\n2026-09-14 — LEAVES PHASE A ENTIRELY, by Jacob''s decision: catalog is out of this build. X-W1.13 graded it SHIPPED on objects (products; create/update/delete/list/fetch_product; add_estimate_line_item(p_product_id); /estimating/catalog; 20260825125737, 20260826132626); BMR has 0 products. Moved to phase later with that grade. Not acceptance-tested in Phase A.',
         updated_at = now()
   where id = 'eee2c75e-4371-415a-91d8-352dba70c2ff' and status = 'planned' and phase = 'A';
  get diagnostics n = row_count; if n <> 1 then raise exception '#25: expected 1 row, changed %', n; end if;

  update public.roadmap_items
     set phase = 'later',
         notes = coalesce(notes,'') || E'\n\n2026-09-14 — LEAVES PHASE A ENTIRELY, by Jacob''s decision: Material Matrix integration is out of this build and Material Matrix does not gate it. X-W1.13 graded NOT SHIPPED (no tenant_modules key, no OS surface). Stays planned, phase later.',
         updated_at = now()
   where id = 'cb7f9e21-de4f-4fd0-b4ac-5477ce3cc356' and status = 'planned' and phase = 'A';
  get diagnostics n = row_count; if n <> 1 then raise exception '#30: expected 1 row, changed %', n; end if;
end $$;
