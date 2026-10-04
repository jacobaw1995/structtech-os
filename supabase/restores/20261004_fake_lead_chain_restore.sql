-- RESTORE: the "Fake Lead" chain in Brothers Metal Roofing.
-- Written 2026-10-04 ~01:0x EDT by Track S, BEFORE anything was changed, per the
-- controller's instruction: "A delete without a restore is not reversible and this
-- is a client's tenant."
--
-- WHAT WAS DONE, AND WHAT WAS NOT.
-- Nothing was deleted. Every object in this chain that the schema lets us remove
-- SOFTLY was removed softly (SCOPE §2.6), through the same RPCs a user clicks:
--   void_work_order(195571d7…)  trade  "TRACK S · A2 live acceptance (Fake Lead)"
--   void_work_order(0ffcb7d4…)  master
--   void_estimate(a8a435d2…)    signed → void
--   archive_deal(52eaf276…)     "Fake Lead", + its 2 pending follow_ups → cancelled
-- NOT TOUCHED, and the reason is in the report: job 83ff1534 (the `jobs` table has
-- no archived_at, no voided_at and no delete RPC — it cannot be soft-removed, and
-- hard-deleting it would CASCADE purchase_orders), the 6 `field_events` rows from
-- Jacob's 00:31–00:32 roofer session on this very work order, and the purchase
-- order / line / promises, which were proposed in the report rather than acted on.
--
-- WHY VOID AND NOT DELETE, beyond §2.6: `field_events.work_order_id` carries NO
-- foreign key. A hard delete of 195571d7 would have left six rows pointing at a
-- work order that no longer exists, silently, with nothing to cascade or refuse.
--
-- HOW TO RUN IT. As Jacob (BMR agency_admin, 09a25143-e069-401b-a49d-a6879fe43d7c)
-- or any BMR manager. The UPDATEs below are deliberate, direct table writes: there
-- is no un-void and no un-archive RPC in this build, which is itself worth a
-- backlog line. Run the whole thing in one transaction and read the verification
-- block at the end before committing.
--
-- VALUES ARE LITERAL AND WERE MEASURED, not reconstructed (migration rule 10).
-- `updated_at` is restored to its pre-void value on `work_orders` and `estimates`,
-- so a later diff does not read as a second edit: the void is what moved it and
-- un-voiding reverses that exact act. It is NOT restored on `deals`, and the
-- reason is in section 3 — a trigger makes it impossible, and pretending otherwise
-- is what the dry run caught.
--
-- THIS FILE WAS PROVED, NOT ASSERTED. The whole sequence — void, archive, then
-- this restore — was run in ONE transaction that was rolled back: 7 values
-- captured before, 7 compared after, and a control in the middle showing the void
-- had really taken effect (Anderson's phone went from one job to `[]`). The first
-- run returned 2 mismatches and that is what section 3 documents.

begin;

-- 1 · THE TWO WORK ORDERS.
-- Measured before the void: both had voided_at = NULL and
-- void_cascade_source_id = NULL. void_work_order on the MASTER cascades to every
-- unvoided trade on the same job_id and stamps void_cascade_source_id; voiding the
-- trade BY NAME first clears its own marker. Either way, NULL is the restore.
update public.work_orders
set voided_at = null,
    void_cascade_source_id = null,
    updated_at = '2026-09-10 22:19:10.092368+00'::timestamptz
where id = '195571d7-4161-4fa0-95cf-a1302c2561be';

update public.work_orders
set voided_at = null,
    void_cascade_source_id = null,
    updated_at = '2026-07-22 02:31:29.213963+00'::timestamptz
where id = '0ffcb7d4-64e5-48dd-98f8-127112b4755b';

-- 2 · THE ESTIMATE. Was 'signed'. Its 2 signatures, 2 signed_copy_records and
-- 1 line item were never touched — void_estimate only moves `status`.
update public.estimates
set status = 'signed',
    updated_at = '2026-07-22 02:30:55.553565+00'::timestamptz
where id = 'a8a435d2-6ed9-4aff-b6f2-e210f9054533';

-- The second estimate on this deal, 6188b695-63c5-41da-a6db-6d86260d18f2, was
-- ALREADY status 'void' (voided 2026-07-31) and was not altered. Nothing to undo.

-- 3 · THE DEAL. Was archived_at = NULL, stage 'new_lead' (stage was not changed).
--
-- DELIBERATE DIVERGENCE, DOCUMENTED (migration rule 10, second half). `updated_at`
-- is NOT pinned here and CANNOT be: `deals` carries a BEFORE UPDATE trigger,
-- `deal_stage_side_effects`, whose last statement is an unconditional
-- `new.updated_at := now()`. An explicit literal is overwritten by it. My first
-- draft of this file pinned 2026-07-22 02:29:44.162878+00 anyway; the dry run
-- compared 7 captured values and returned 2 mismatches, which is the only reason
-- this is written down instead of shipped. The deal's `updated_at` will read as
-- the moment of the restore. That is honest — the row WAS updated then.
-- The other three tables have no such trigger (checked in pg_trigger), so their
-- pins hold and were proved to hold.
update public.deals
set archived_at = null
where id = '52eaf276-5002-49c9-af43-b7f678e6802b';

-- archive_deal appends an 'archived' row to deal_activity. The deal had exactly 2
-- activity rows before (both 'created'/'followup_scheduled', 2026-07-21 22:29:44
-- ET, actor Jacob Walker). Remove only the row the archive wrote.
delete from public.deal_activity
where deal_id = '52eaf276-5002-49c9-af43-b7f678e6802b'
  and action = 'archived';

-- 4 · THE TWO FOLLOW-UPS, which archive_deal cancels. Both were 'pending', both
-- overdue since July 2026, both addressed to jacob@structtek.com.
update public.follow_ups set status = 'pending'
where id in ('cafd88be-298e-4656-b8ad-267b71b3856a',
             'db801ca1-cbb8-400c-8abe-08208244190c');

-- 5 · VERIFY BEFORE YOU COMMIT. Expected: 2 rows, both voided_at NULL; estimate
-- 'signed'; deal archived_at NULL with 2 activity rows; 2 pending follow_ups.
select 'work_orders' obj, id::text, voided_at::text from public.work_orders
  where id in ('195571d7-4161-4fa0-95cf-a1302c2561be','0ffcb7d4-64e5-48dd-98f8-127112b4755b')
union all select 'estimate', id::text, status from public.estimates
  where id = 'a8a435d2-6ed9-4aff-b6f2-e210f9054533'
union all select 'deal', id::text, coalesce(archived_at::text,'NOT ARCHIVED') from public.deals
  where id = '52eaf276-5002-49c9-af43-b7f678e6802b'
union all select 'deal_activity rows', count(*)::text, '' from public.deal_activity
  where deal_id = '52eaf276-5002-49c9-af43-b7f678e6802b'
union all select 'pending follow_ups', count(*)::text, '' from public.follow_ups
  where deal_id = '52eaf276-5002-49c9-af43-b7f678e6802b' and status = 'pending';

-- commit;   -- uncomment deliberately
rollback;
