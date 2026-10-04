-- RESTORE: the two Track S fixtures Jacob named in BMR — purchase order
-- 1256ba02 ("TRACK S · A2 acceptance supplier") and material item 9616011e.
-- Written 2026-10-04, BEFORE anything was removed. Track S.
--
-- THESE ARE HARD DELETES, AND SAYING SO IS THE POINT. Unlike the Fake Lead
-- chain, neither of these objects has a soft form that removes it from the
-- screen:
--   · `material_items` has no archived_at, no voided_at. `delete_material_item`
--     is a hard delete and the only removal that exists.
--   · `purchase_orders` HAS a soft form — status 'cancelled' — and
--     `delete_purchase_order` REFUSES a non-draft PO by design:
--     "this purchase order is confirmed and cannot be deleted — a supplier has
--     already been told about it. Cancel it instead, which keeps the record and
--     its promise history."
--     A CANCELLED PO IS STILL ON THE PURCHASING SCREEN, carrying the words
--     "TRACK S · A2 acceptance supplier" into a client's workspace, which is the
--     thing being removed. So the PO is walked back to 'draft' through
--     `update_purchase_order` — an ordinary office action — and then deleted.
--     THAT IS DELIBERATELY ROUTING AROUND A GUARD, and it is defensible only
--     because no supplier was ever told: the supplier is a string I typed on
--     2026-09-10 for an acceptance run. It would NOT be defensible on a real PO.
--
-- WHAT THE DELETES TAKE WITH THEM, measured not assumed:
--   · purchase_order_lines and purchase_order_line_promises CASCADE from the PO
--     (confdeltype 'c' on both FKs) — 1 line and 2 promises.
--   · deleting the material fires AFTER DELETE `material_items_take_off_removed`,
--     which stamps `item_removed_at` / `item_removed_by` on the take-off decision
--     for estimate line e310eb90. That stamp is undone below; it is the one
--     side-effect outside the two objects named.
--
-- ONE OF THE TWO PROMISES IS JACOB'S OWN. `70c002a6` was recorded by him at
-- 2026-10-04 00:29:19 EDT while walking the product, promising 2026-10-04 — it
-- is what moved the material's ready_by off 2026-10-20. He named these fixtures
-- for removal today, so it goes with them, and it comes back with this file.
--
-- TIMESTAMPS ARE PINNED HERE, AND THAT IS THE OPPOSITE CALL FROM
-- 20261004_fake_lead_chain_restore.sql, ON PURPOSE. There, `deals.updated_at`
-- was left alone because that row was never deleted — the restoring UPDATE
-- genuinely happens at restore time, and a trigger overwrote the pin anyway.
-- Here the rows are GONE, and `created_at` / `recorded_at` are facts about the
-- rows that were removed. Re-asserting them is accurate; letting them default
-- to now() would invent a 2026-10-04 provenance for a 2026-09-10 fixture.
--
-- THERE IS NO UN-DELETE RPC. These are direct INSERTs, which is the same gap the
-- Fake Lead restore names. Run as a BMR manager, in one transaction, and read
-- the verification block before committing.
--
-- INSERT ORDER IS FK ORDER: material, then PO, then line (FKs both), then
-- promises. The values below were EMITTED FROM THE ROWS by format(%L), not
-- transcribed by hand.

begin;

-- 1 · THE MATERIAL.
--
-- DOCUMENTED DIVERGENCE, MEASURED AND NOT PREDICTED (migration rule 10). The
-- dry run compared all 16 columns of this row plus 5 other rows — 6 rows, 2
-- mismatches — and both are on this one object:
--     take_off_description   NULL  ->  'Ag panel: 26 ga black replacement. '
--     take_off_quantity      NULL  ->  1
-- The BEFORE INSERT guard `material_items_take_off_guard` re-derives provenance
-- from the take-off line, so a restored material comes back MORE populated than
-- the row that was deleted. `take_off_unit` stays NULL.
--
-- AND IT CANNOT BE PATCHED BACK. The same trigger fires BEFORE UPDATE, and on an
-- update that leaves estimate_line_item_id alone it explicitly copies the OLD
-- take_off_* values forward — so a follow-up `set take_off_description = null`
-- is silently ignored. NULL is unreachable here, the way `deals.updated_at` was
-- unreachable in the Fake Lead restore. Written down rather than papered over,
-- because an undocumented difference teaches the next reader to ignore
-- differences on this row.
insert into public.material_items (id, org_id, work_order_id, name, quantity, ready_by, sort_order, created_at, updated_at, estimate_line_item_id, product_id, unit, ready_by_source, take_off_description, take_off_quantity, take_off_unit) values ('9616011e-5177-45c1-b829-7cd8f51322c5','9d32b5a9-e11e-401b-8fa7-969065b004ce','195571d7-4161-4fa0-95cf-a1302c2561be','Ag panel: 26 ga black replacement.','1','2026-10-04','0','2026-09-10 22:19:10.092368+00','2026-10-04 04:29:24.975113+00','e310eb90-bab9-408f-a8d1-c81779ccee65',NULL,NULL,'purchase_order',NULL,NULL,NULL);

-- 2 · THE PURCHASE ORDER, ITS LINE, AND BOTH PROMISES.
insert into public.purchase_orders (id, org_id, job_id, supplier_name, supplier_org_id, status, reference, notes, created_at, updated_at, created_by) values ('1256ba02-18ae-42e9-beaf-46dd85a382a6','9d32b5a9-e11e-401b-8fa7-969065b004ce','83ff1534-8d79-4564-893a-8ca48c063080','TRACK S · A2 acceptance supplier',NULL,'confirmed',NULL,NULL,'2026-09-10 22:19:10.092368+00','2026-10-04 04:29:24.975113+00','09a25143-e069-401b-a49d-a6879fe43d7c');
insert into public.purchase_order_lines (id, org_id, purchase_order_id, material_item_id, quantity_ordered, promised_date, actual_date, created_at, updated_at) values ('8183c721-94a0-4f3a-bde5-bfc7a2053473','9d32b5a9-e11e-401b-8fa7-969065b004ce','1256ba02-18ae-42e9-beaf-46dd85a382a6','9616011e-5177-45c1-b829-7cd8f51322c5','1','2026-10-04',NULL,'2026-09-10 22:19:10.092368+00','2026-10-04 04:29:19.757953+00');
insert into public.purchase_order_line_promises (id, org_id, purchase_order_line_id, promised_date, recorded_at, recorded_by) values ('3ab416f6-e06a-46b5-8c6f-559dc0d9241e','9d32b5a9-e11e-401b-8fa7-969065b004ce','8183c721-94a0-4f3a-bde5-bfc7a2053473','2026-10-20','2026-09-10 22:19:10.092368+00','09a25143-e069-401b-a49d-a6879fe43d7c');
insert into public.purchase_order_line_promises (id, org_id, purchase_order_line_id, promised_date, recorded_at, recorded_by) values ('70c002a6-2055-4cfb-a89a-ceb93d43f4d5','9d32b5a9-e11e-401b-8fa7-969065b004ce','8183c721-94a0-4f3a-bde5-bfc7a2053473','2026-10-04','2026-10-04 04:29:19.757953+00','09a25143-e069-401b-a49d-a6879fe43d7c');

-- 3 · UNDO THE TAKE-OFF STAMP the AFTER DELETE trigger wrote.
update public.take_off_decisions
set item_removed_at = null, item_removed_by = null
where estimate_line_item_id = 'e310eb90-bab9-408f-a8d1-c81779ccee65';

-- 4 · VERIFY BEFORE COMMITTING (rule 3). Expect 1, 1, 1, 2, and a null stamp.
select 'material_items' obj, count(*) n from public.material_items where id='9616011e-5177-45c1-b829-7cd8f51322c5'
union all select 'purchase_orders', count(*) from public.purchase_orders where id='1256ba02-18ae-42e9-beaf-46dd85a382a6'
union all select 'purchase_order_lines', count(*) from public.purchase_order_lines where id='8183c721-94a0-4f3a-bde5-bfc7a2053473'
union all select 'purchase_order_line_promises', count(*) from public.purchase_order_line_promises where purchase_order_line_id='8183c721-94a0-4f3a-bde5-bfc7a2053473'
union all select 'take_off item_removed_at is null', count(*) from public.take_off_decisions where estimate_line_item_id='e310eb90-bab9-408f-a8d1-c81779ccee65' and item_removed_at is null;

-- commit;   -- uncomment deliberately
rollback;
