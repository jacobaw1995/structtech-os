-- ============================================================================
-- X-W1.13 · BUILD MODULE, PHASE A — GRADED BY OBJECT. PROPOSAL FOR TRACK S.
-- NOT APPLIED BY TRACK X. `roadmap_items` is core-schema data; writes are S's.
-- ============================================================================
-- Graded 2026-09-14 (America/New_York) against origin/main e1b6677 and the live
-- database. Project "StructTech OS" (87ce7cbb-20a0-44c3-8560-b688d53fed27).
-- Last write to any of its 101 items before this: 2026-08-20 13:43:59 UTC.
--
-- Counts before this proposal (measured, and they match the directive exactly):
--   now 24 shipped · A 5 shipped / 2 in_progress / 37 planned (44)
--   B 4 planned · C 5 planned · D 6 planned · later 17 planned / 1 in_progress
--
-- ── RESULT ──────────────────────────────────────────────────────────────────
--   PROVED SHIPPED      8   (5 already shipped and confirmed; 3 move to shipped)
--   PROVED NOT SHIPPED 36   (34 with the required objects absent; 2 partial)
--   UNGRADED            0
--
--   Moves proposed: 4.   #25 #26 #33 -> shipped.   #27 planned -> in_progress.
--   After:  A  8 shipped · 2 in_progress · 34 planned  (44)
--   (#33 leaves in_progress as #27 joins it, so in_progress nets to 2. An earlier
--   draft of this header said 8/3/33; a rolled-back dry run of the block below
--   returned 8/2/34 and caught it. The dry run also confirmed each move changes
--   exactly 1 row and that replaying a move changes 0 — which the guard raises on.)
--
-- ── METHOD ──────────────────────────────────────────────────────────────────
-- No item was moved because a directive, an end-of-day report or its own notes
-- said it shipped. Each grade rests on an object: a migration id in
-- supabase_migrations.schema_migrations, a function in pg_proc, a column in
-- information_schema, a policy in pg_policies, a route under src/app, or a row
-- count. "Not shipped" was established BY PROPERTY — a keyword sweep of every
-- public column, every function body and every file in src/ — and every sweep
-- carried a positive control that had to hit before its zeros were trusted
-- (columns: work_orders.predecessor_id, purchase_order_lines.promised_date;
-- functions and src: purchase_order, take_off).
--
-- Three instruments were wrong during grading and were replaced, not trusted:
--   · a src grep using `--include=*.ts` errored under zsh and the `|| echo none`
--     after it printed a false "none"; redone without the glob, with a control;
--   · a regex substring around `actual_date` returned NULL although the same
--     bodies had matched — and the match itself turned out to come from another
--     term in the OR (`purchase_order_line_promises`); position() shows
--     `actual_date` appears in NEITHER purchase-order-line function;
--   · the generic-blind construction pattern from 9/13 (see X-W1.12).
--
-- ── ALL 44, WITH THE EVIDENCE ───────────────────────────────────────────────
--  #  item (id prefix)                              now          grade
--  -- -------------------------------------------- ------------ ----------------
--  20 Job entity above work orders (d1849f51)       shipped      SHIPPED — table jobs (deal_id, estimate_id, service address); create_job_from_estimate(); a1_1 20260816172215, a1_2 20260817151709; 2 BMR jobs
--  21 Master work order (2379ef4b)                  shipped      SHIPPED* — work_orders.kind='master' (2 rows); fetch_work_order_tree(); record_work_order_sign_off(); route coordination/[workOrderId]. *See FLAG 1: the homeowner-SIGNED agreement its title names has no object.
--  22 Trade work orders to crew/dept/sub (b86ff214) shipped      SHIPPED — CHECK assignee_type IN (crew, department, subcontractor); assignee_ref; create_trade_work_order(); 1 trade row
--  23 Trade WO predecessor field (73e503a5)         shipped      SHIPPED — work_orders.predecessor_id; create_trade_work_order(p_predecessor_id). Field only, as named; 0 rows use it.
--  24 Migrate existing WOs onto jobs (d93a0c0b)     shipped      SHIPPED — 3 work_orders, 0 with job_id NULL
--  25 Tenant product catalog (eee2c75e)             planned      SHIPPED — products (15 cols); create/update/delete/list/fetch_product(); add_estimate_line_item(p_product_id); route estimating/catalog linked from estimating; a2_1 20260825125737, a2_1c 20260826132626. BMR products = 0 (built, not yet used). See FLAG 2.
--  26 Take-off from estimate lines (89a580fd)       planned      SHIPPED — generate_take_off(); material_items.estimate_line_item_id/product_id/ready_by_source; MasterTakeOffCard mounted on coordination/[workOrderId]; a2_2 20260828124735; 1 BMR material item
--  33 Assistant role capability flags (86244cac)    in_progress  SHIPPED — set_member_capability() writes org_members.permissions; can_view_financials() called by 4 RESTRICTIVE "no dollars in the field" policies (deals, estimates, estimate_line_items, products); route settings/permissions + MemberCapabilityEditor; 20260911233218. No assistant member exists yet (roles present: agency_admin, member, owner) — onboarding, not build.
--
--  27 Purchase orders, promise vs actual (d60c5c1f) planned      PARTIAL -> in_progress — purchase_orders, purchase_order_lines, purchase_order_line_promises; route coordination/po/[poId], PurchaseOrderList; 20260907230009, 20260910215139, 20260911234338. BUT purchase_order_lines.actual_date is referenced by ZERO functions (position()=0 in add_ and update_purchase_order_line) and ZERO files in src; 0 of 1 line carries one. The PROMISE is recordable; the ACTUAL is not.
--   5 Real homeowner sign-off + signed doc (459bb855) in_progress PARTIAL, stays in_progress — its own notes plan 6 chunks; only chunk 1 has objects (work_order_agreements, create_/fetch_work_order_agreement). NO function writes colors_finishes; the ONLY function writing signature_data is sign_estimate; work_order_agreements has 0 rows; sign_token_hash and sent_at are referenced by nothing.
--
--   1 Milestone comms (eed82966)                    planned      NOT SHIPPED — no email-sending code or dependency in src/package.json; no milestone/notification object for jobs
--   2 Decision authority (45205c97)                 planned      NOT SHIPPED — no authority/decision column or function
--   3 Written confirmation of verbal decisions      planned      NOT SHIPPED — no confirm column; `verbal` only in roadmap_playbook prose
--   4 Education documents (176a027f)                planned      NOT SHIPPED — no object
--   6 Third-party inspection record (57de5d6f)      planned      NOT SHIPPED — no inspect column, function or src file
--   7 Office-side roof-data/photo upload (fb9c4f6f) planned      NOT SHIPPED — org-files bucket has 0 storage policies (authenticated cannot write); uploadOrgFile() has 0 callers outside src/lib/storage
--   8 Per-role file permissions (4b4d153e)          planned      NOT SHIPPED — 0 storage policies on org-files; no file table
--   9 Daily objective per trade WO (82633bd0)       planned      NOT SHIPPED — no objective column; production_packets is one-per-work-order with no date
--  10 Special-trip / exception log (f6ea4ef8)       planned      NOT SHIPPED — check_ins.blockers is free text; no reason code or trip object
--  11 QC items (b1735208)                           planned      NOT SHIPPED — no qc/rivet/required-photo object
--  12 Production packet v2 (9d146cc1)               planned      NOT SHIPPED — production_packets columns are notes, callouts only; ProductionPacketView.tsx:125 renders "Trim map / boot-vent placement layer — deferred"
--  13 Crew acknowledgment (0a277ce8)                planned      NOT SHIPPED — no acknowledg/opened column
--  14 Crew/person model (75d8a6e5)                  planned      NOT SHIPPED — no skill/language/vehicle/availability; schedule_blocks.crew_name is text
--  15 Invoice from signed estimate (e9c48534)       planned      NOT SHIPPED — no invoice function/src; org_invoices is StructTech's own billing (no estimate or job column)
--  16 Deposits + payment schedule (abce25ca)        planned      NOT SHIPPED — no deposit/payment object
--  17 Payment status + receivables (1a330c5a)       planned      NOT SHIPPED — no receivable object
--  18 Job cost lines (c6fd6cac)                     planned      NOT SHIPPED — only cost column is products.cost (catalog); no job cost object
--  19 Margin per job + retro (4f2bd617)             planned      NOT SHIPPED — no margin object (`margin` appears only in pdf layout and catalog price maths)
--  28 Shop stock + reservation (acfa1ca6)           planned      NOT SHIPPED — no stock/reservation/consumption object
--  29 Delivery record + receipt check (cf118b4a)    planned      NOT SHIPPED — no delivery/receipt/received object; actual_date unwritable (#27)
--  30 Material Matrix integration (cb7f9e21)        planned      NOT SHIPPED — no tenant_modules key for it (9 keys, none MM); no OS surface. See FLAG 2.
--  31 Dashboard / home view (ed0a2c7a)              planned      NOT SHIPPED — /w/[orgId] renders module-launcher links only, zero data queries
--  32 Golden path acceptance test (64819bc5)        planned      NOT SHIPPED — "every table non-zero" measured FALSE for BMR: work_order_agreements 0, products 0, check_ins 0, production_packets 0
--  34 Remote / email signing link (bbc9ba9a)        planned      NOT SHIPPED — signatures.sign_token and work_order_agreements.sign_token_hash exist; ZERO function or src references; 0 rows populated
--  35 Auto-emailed signed copy (bc04806a)           planned      NOT SHIPPED — no email-sending path
--  36 Transactional email (bd14baf7)                planned      NOT SHIPPED — no email library, dependency or send path in src/package.json
--  37 Self-serve password reset (8dea89d2)          planned      NOT SHIPPED — no resetPasswordForEmail/updateUser call; no reset or recover route
--  38 Standards library baseline (fde1f681)         planned      NOT SHIPPED — no standard object (src `standard` = pdf-lib StandardFonts)
--  39 Tenant overlay (f02814d4)                     planned      NOT SHIPPED — no overlay object
--  40 Job-level exception (13eb2c62)                planned      NOT SHIPPED — no exception object
--  41 Standard states (127c4338)                    planned      NOT SHIPPED — no object
--  42 Provenance on every standard (f5c08270)       planned      NOT SHIPPED — `provenance` exists only as take-off provenance (#26)
--  43 Checklist taxonomy (7f2bd923)                 planned      NOT SHIPPED — no object (deals.intake_checklist is CRM intake)
--  44 Voice/transcript -> draft standard (f69fc53c) planned      NOT SHIPPED — no object
--
-- ============================================================================
-- THE PROPOSAL. One transaction. Each move is keyed on the primary key as a
-- literal AND on the status it was graded at, and refuses unless exactly one
-- row changes — so a replay against a board someone has already edited fails
-- loudly instead of silently overwriting (CLAUDE.md rule 10). Notes are
-- APPENDED, never replaced: they are Jacob's input channel. updated_at is set
-- to now(); no audit field is pinned to a historical value.
-- ============================================================================

begin;

do $$
declare n int;
begin
  -- #25 Tenant product/service catalog — planned -> shipped
  update public.roadmap_items
     set status = 'shipped',
         notes = coalesce(notes,'') || E'\n\n2026-09-14 (X-W1.13, graded by object) — SHIPPED. products table (15 cols); create/update/delete/list/fetch_product(); add_estimate_line_item(p_product_id); route /w/[orgId]/estimating/catalog, linked from /estimating. Migrations 20260825125737 (a2_1), 20260826132626 (a2_1c). BMR has 0 products — built, not yet used. Ruling 2026-09-14: catalog is out of this build — disposition for Track S.',
         updated_at = now()
   where id = 'eee2c75e-4371-415a-91d8-352dba70c2ff' and status = 'planned';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'X-W1.13 #25: expected 1 row at status=planned, changed %', n; end if;

  -- #26 Material take-off from estimate lines — planned -> shipped
  update public.roadmap_items
     set status = 'shipped',
         notes = coalesce(notes,'') || E'\n\n2026-09-14 (X-W1.13, graded by object) — SHIPPED. generate_take_off(p_work_order_id, p_estimate_line_item_ids); material_items.estimate_line_item_id / product_id / ready_by_source (provenance); MasterTakeOffCard mounted on /w/[orgId]/coordination/[workOrderId]; server action src/lib/coordination/actions.ts. Migration 20260828124735 (a2_2). 1 BMR material item.',
         updated_at = now()
   where id = '89a580fd-c3d8-4e90-84f9-c2ac8277a00f' and status = 'planned';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'X-W1.13 #26: expected 1 row at status=planned, changed %', n; end if;

  -- #33 Assistant role — capability flags (hide $) — in_progress -> shipped
  update public.roadmap_items
     set status = 'shipped',
         notes = coalesce(notes,'') || E'\n\n2026-09-14 (X-W1.13, graded by object) — SHIPPED. set_member_capability() writes org_members.permissions; can_view_financials() is called by 4 RESTRICTIVE policies ("no dollars in the field" on deals, estimates, estimate_line_items, products); route /w/[orgId]/settings/permissions with MemberCapabilityEditor. Migration 20260911233218 (permissions_write_path). NOT DONE AND NOT BUILD WORK: no assistant member exists in production (roles present: agency_admin, member, owner), so the 7/29 note''s "verify real login matches synthetic probes" has not happened.',
         updated_at = now()
   where id = '86244cac-c02d-4e1b-87f6-e678a6c6715b' and status = 'in_progress';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'X-W1.13 #33: expected 1 row at status=in_progress, changed %', n; end if;

  -- #27 Purchase orders with committed date (promise vs actual) — planned -> in_progress
  update public.roadmap_items
     set status = 'in_progress',
         notes = coalesce(notes,'') || E'\n\n2026-09-14 (X-W1.13, graded by object) — IN PROGRESS, NOT SHIPPED. PROMISE side built: purchase_orders, purchase_order_lines, purchase_order_line_promises (promise history); route /w/[orgId]/coordination/po/[poId]; migrations 20260907230009 (a2_3), 20260910215139, 20260911234338. ACTUAL side has no write path: purchase_order_lines.actual_date is referenced by zero functions (absent from add_ and update_purchase_order_line) and zero files in src; 0 of 1 line has one. Promise vs actual cannot be compared until something can record the actual.',
         updated_at = now()
   where id = 'd60c5c1f-e91d-41ca-b075-2d1fa6e14f58' and status = 'planned';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'X-W1.13 #27: expected 1 row at status=planned, changed %', n; end if;
end $$;

-- Verify before committing: Phase A should read 8 shipped / 2 in_progress / 34 planned.
select status, count(*) from public.roadmap_items
 where project_id = '87ce7cbb-20a0-44c3-8560-b688d53fed27' and phase = 'A'
 group by status order by status;

commit;

-- ============================================================================
-- FLAGS — NOT STATUS MOVES. Each needs a decision that is not Track X's.
-- ============================================================================
-- FLAG 1 · #21's title over-promises. "Master work order — full production scope,
--   homeowner sign-off" is shipped for the master and its scope. The homeowner
--   sign-off it names exists only as record_work_order_sign_off(), which stores a
--   timestamp and notes written by the office user; nothing captures a homeowner
--   signature on an agreement (no function writes colors_finishes; the only
--   signature_data writer is sign_estimate; 0 agreements). The A1 acceptance of
--   2026-08-22 did not assert a signature either. The signature is tracked by #5,
--   correctly in_progress — so the board is not wrong about signatures overall,
--   but #21's title reads as if they shipped. Suggest rewording #21, not
--   regressing it.
-- FLAG 2 · "Catalog and Material Matrix are out of this build" (ruling in the
--   2026-09-14 Track X directive; not yet in docs/STRUCTTECH_OS_DIRECTIVE.md on
--   main). #25 grades SHIPPED and #30 NOT SHIPPED on objects. Whether either
--   leaves Phase A (phase 'later'?) is a disposition, not a grade.
-- FLAG 3 · #5's measured state is chunk 1 of 6. Tomorrow's remote signing work
--   lands on #5, #34 and #35 together.
