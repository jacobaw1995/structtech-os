# A2 ACCEPTANCE — EVIDENCE

> ## ▶ G2 DAY UPDATE — 2026-09-10 (Track S). READ THIS BLOCK FIRST.
>
> **G2 DECISION: NOT ACCEPTED — EXACTLY ONE CLAUSE OUTSTANDING, AND IT IS A BROWSER CHECK THAT IS JACOB'S.**
> Every A2 *Done when* clause that can be graded by the database is PASS. **A2.1c's "prices an
> estimate line with no re-entry" has NOT been run** — there is no record of it in the repo or the
> directive — and per the gate's own instruction its absence is **not** a pass. Run it, record it,
> and A2 accepts on what is already on `main`.
>
> **WHAT CHANGED SINCE THE 9/09 PRE-FLIGHT:**
>
> 1. **Yesterday's BLOCKER IS CLEARED.** The 9/09 blocker was the Definition of Done: A2.3 created three
>    entities with no surface. **Track U shipped the surface and it is on `main` and DEPLOYED**, measured:
>    `/api/health` reports production at **`5deb9b0` = `origin/main`** (the first time the deployed SHA was
>    MEASURED rather than UNAVAILABLE), and `/w/<uuid>/coordination/po/<uuid>` answers **307→login** while a
>    nonsense sibling **404s**. SCOPE §2.6 re-checked against the code on `main`:
>
>    | Entity | Create | Edit | Delete / archive / **void** | §2.6 |
>    |---|---|---|---|---|
>    | `purchase_orders` | `createPurchaseOrder` | `updatePurchaseOrder` (supplier, status) | **"Cancel this order"** → `status='cancelled'` — **VOID** | **MEETS** (void, not delete) |
>    | `purchase_order_lines` | `addPurchaseOrderLine` | `updatePurchaseOrderLine` | `deletePurchaseOrderLine` | **MEETS** |
>    | `purchase_order_line_promises` | implicit, via line add/update | — | — | **N/A BY RULING** — append-only history (ruling 1), never user-created |
>
>    **There is NO purchase-order DELETE anywhere in `src/`** — the RPC `delete_purchase_order` exists and nothing
>    calls it. My first grep said otherwise: `deletePurchaseOrder` is a **substring of** `deletePurchaseOrderLine`.
>    Rule 15's instrument lesson, again. §2.6 accepts *voided*, so this meets the standard; it is recorded so
>    nobody later assumes a delete exists. **What I verified is that the controls exist and are wired to RPCs that
>    work. I did not click through them in a browser** — that is a rendering check, the same class as A2.1c.
>
> 2. **A CROSS-TENANT WRITE DEFECT WAS FIXED FIRST** (`20260910215139`): `create_purchase_order`'s jobless branch
>    took `org_members … limit 1` with no `ORDER BY` — and for the one human in all three orgs it picked
>    **StructTech**, so a jobless PO drafted from the BMR workspace would have landed in the wrong tenant. Now
>    `p_org_id` is required. And `job_id` could never be set after insert, so the refusal's own advice
>    ("attach it to a job first") named an action the API did not implement; `update_purchase_order` now takes
>    `p_job_id`. 0 POs existed, so nothing was ever misfiled.
>
> 3. **CLAUSES 8, 10 AND 11 MOVED OFF ROLLED-BACK FIXTURES ONTO COMMITTED PRODUCTION ROWS** — see §6 below for
>    exactly what, and the honest limit on what "live" means here.
>
> 4. **§5 A2.3 amended**: `enforce_stage_gating` lives in `organizations.policy`, not `tenant_modules.config`.
>
> ### THE REVISED DISTRIBUTION
>
> | Grade | 9/09 | **9/10** |
> |---|---|---|
> | PASS | 11 | **11** |
> | FAIL | 0 | **0** |
> | UNGRADED | 0 | **0** |
> | UNTESTABLE (browser) | 1 | **1 — A2.1c "no re-entry", NOT RUN** |
> | **of the passes, exercised by committed production rows** | **1** (a refusal) | **4** — clauses 8, 9, 10, 11 |

---

**Track S · 2026-09-09 · original pre-flight for the G2 gate on 2026-09-10.**
Every *Done when* below was read from `docs/STRUCTTECH_OS_DIRECTIVE.md` §5.2 itself —
not from the PO proposal, not from a summary, not from memory of what was built.

**All probes ran in ROLLED-BACK transactions against the live database. Zero residue,
re-counted after: products 0 · material_items 0 · schedule_blocks 0 · work_orders 2 (both
masters) · purchase_orders/lines/promises 0/0/0 · org_members 5 · organizations at
`policy = '{}'` 3 of 3 · no `example.invalid` users.**

---

## 0 · THE HEADLINE, BEFORE THE TABLE

**EVERY A2 *Done when* CLAUSE THAT CAN BE GRADED IN SQL PASSES. NONE FAILS.**

**But G2 CANNOT ACCEPT A2.3 ON SCHEMA ALONE, and the reason is not a failing clause —
it is the Definition of Done that sits above every *Done when*:**

> `CLAUDE.md` → *Definition of done (every phase)* → **"Full user CRUD (SCOPE §2.6): every
> entity the phase creates can be edited and deleted/archived/voided by the user in the UI."**

**A2.3 created THREE entities — `purchase_orders`, `purchase_order_lines`,
`purchase_order_line_promises` — and there is NO purchase-order surface in `src/`.**
Measured: the only file in the whole application that mentions a purchase order is
`src/lib/permissions/model.ts`, which is Track U's capability mirror registry, not a screen.
No route, no form, no list, no picker. **A user cannot create, edit or delete a purchase
order at all.** The nine RPCs work; nothing calls them.

**That is a surface gap, it is not Track S's to close, and it needs to be known tonight.**

---

## 1 · THE GRADE TABLE — 12 CLAUSES ACROSS 6 STAGES

Grades: **PASS** re-derived today with a failing-query and a live control · **FAIL** ·
**UNGRADED** could not have failed on live data · **UNTESTABLE** depends on a surface, a
human action, or something §5 does not define.

| # | Stage | *Done when* clause | Grade | Evidence, and WHAT WOULD HAVE MADE IT FAIL |
|---|---|---|---|---|
| 1 | **A2.0** | a member with **no `permissions` row** gets the SAME answer from `has_capability()`, `can_view_financials()`, `can_view_master_work_order()` — **and it is the CLOSED one** | **PASS** | Member at `'{}'`: **10 of 10 derived keys read false**, both wrappers agree with `has_capability`. **CONTROL in the same pass:** the BMR owner reads `true` from both, so the zeros are refusals, not silence. **FAILS IF** any key read true (fail-open) or a wrapper answered differently. |
| 2 | **A2.0b** | a role change re-derives `permissions` on **every** path, **including a direct UPDATE that touches no RPC** | **PASS** | `owner`→`field` by **direct UPDATE**, no RPC: strips to **3 of 10** true (the `field` default). **CONTROL:** `office`→`owner` by the same path raises to **10 of 10**. **FAILS IF** the demotion left the elevated set — i.e. the trigger fired only through the RPC. |
| 3 | **A2.1 (a)** | a tenant with **MM disabled** builds a catalog and prices an estimate line from it | **PASS** *(fixture)* | `create_product` → product; `add_estimate_line_item` carrying `p_product_id` → line at **465**. **"MM disabled" holds BY ABSENCE:** no MM entitlement key exists in `tenant_modules` for any tenant — A2.6 never shipped one. **FAILS IF** `create_product` refused, the line could not carry a `product_id`, or the price did not come across. **LIVE DATA COULD NOT HAVE EXERCISED THIS: `products` = 0 and editable estimates = 0 (all four are signed or void).** |
| 4 | **A2.1 (b)** | a crew-role probe reads **NO** catalog cost and **NO** catalog sell — gated by `can_view_financials()`, never by `has_capability()` | **PASS** *(synthetic member)* | Both layers: RLS direct select **0 rows**; definer RPC `list_products` **1 row, 0 with money**; `can_view_financials()` = **false**. **FAILS IF** either layer returned a non-null cost or sell, or the gate read true for a `field` member. **`role='field'` count live: 0**, so the member was constructed. |
| 5 | **A2.1c** | a catalog item prices an estimate line **with no re-entry** | **UNTESTABLE — SURFACE** | The data half is clause 3 above. **"No re-entry" is a rendering property: it asserts the user does not retype the price.** SQL cannot grade it. **The surface EXISTS** — the picker is in `src/components/estimating/LineItemsEditor.tsx` — so this is a browser check, not a build gap. A1.6's precedent: where a clause is about rendering, the browser is not a redundant check, it is the only check. |
| 6 | **A2.1c** | the line is a **SNAPSHOT** a later catalog price change cannot move | **PASS** *(fixture)* | Line priced 465; catalog `sell` moved **465 → 999**; line re-read at **465**. **FAILS IF** any read path joined `products` for money. |
| 7 | **A2.1c** | the crew gate still holds **through the estimate document path** | **PASS** *(synthetic member)* | Field member sees **0** `estimate_line_items` carrying a `unit_price` — refused at layer 1, so the document path exposes nothing the catalog path hides. **FAILS IF** the document path returned line money. |
| 8 | **A2.2 (a)** | a signed estimate produces a take-off with **zero manual entry**, and **the trade count is NAMED** | **PASS** *(fixture)* | `generate_take_off` returned `created: 1`, `live_trade_count: 2`, and `trades_with_take_off` present in the payload. **FAILS IF** `created = 0`, or the payload omitted either count. **LIVE DATA COULD NOT HAVE EXERCISED THIS: 0 trades exist**, so two were built in-transaction. |
| 9 | **A2.2 (b)** | a take-off against a job with **ZERO trades** is **REFUSED**, naming the zero count | **PASS — ON LIVE DATA** | Run against **both real production masters**, each at 0 trades — the exact state the clause describes. Both refused: *"this job has **0 trade work orders**, so a take-off has nowhere to land…"*. **FAILS IF** it proceeded, or refused without naming the zero. **This is the only A2 clause live data could exercise unaided.** |
| 10 | **A2.3 (1)** | a PO's committed date sets `material_items.ready_by` | **PASS** *(fixture)* | PO line with `promised_date` 2026-10-20 → `ready_by = 2026-10-20`, `ready_by_source = 'purchase_order'`. **FAILS IF** `ready_by` stayed null or the manual branch fired. |
| 11 | **A2.3 (2)** | a schedule block scheduled before its `ready_by` **raises a WARNING and still saves** | **PASS** *(fixture)* | Row **saved** (`count = 1`), `ready_by_conflict = true`, reason *"materials not ready until 2026-10-20 (Panels)"*. **FAILS IF** it refused (row absent) or saved with no warning flag. |
| 12 | **A2.3 (3)** | **BLOCKED only** for a tenant that has turned on `enforce_stage_gating`, default **off** | **PASS on the substance — §5's LOCATOR IS STALE** | Key **on**: refused, *"…This workspace enforces stage gating, so the schedule block was not saved."* Key **off** is clause 11 above, which saved. **FAILS IF** it saved with the key on, or refused with it off. **See §3 — §5 names the wrong table.** |

---

## 2 · DISTRIBUTION

| Grade | Count |
|---|---|
| **PASS** | **11** of 12 |
| **FAIL** | **0** |
| **UNGRADED** | **0** |
| **UNTESTABLE (surface)** | **1** — clause 5, A2.1c "no re-entry" |

**AND THE SECOND NUMBER, WHICH MATTERS MORE FOR AN ACCEPTANCE: of the 11 passes, ONE
(clause 9) was exercised by live production data. The other TEN required fixtures built
inside the probe, because the tables A2 fills are all at zero rows** — `products` 0,
`material_items` 0, `schedule_blocks` 0, trades 0, purchase orders 0, `role='field'` 0,
editable estimates 0.

**That is not a criticism of the fixtures — a fixture is what made each check able to fail,
and without one they would all be empty instruments.** It is the honest denominator: A2's
*Done when* clauses are proved against constructed state, and the first production use of
any of them will be the first time live data touches these paths.

---

## 3 · §5 AMENDMENT OWED BEFORE THE GATE READS IT

**A2.3's *Done when* says the key lives in "`tenant_modules.config`, read through
`command-center.ts`". Half of that is now false.**

- Measured: **`tenant_modules` carries `enforce_stage_gating` on ZERO rows.**
- The key lives in **`organizations.policy`**, moved there 2026-09-03 with controller
  authorisation, because it is a tenant policy and coordination became its second consumer.
- **"read through `command-center.ts`" is still TRUE** — that file still owns
  `parseEnforceStageGating()` — but it now reads `organizations.policy`.

**The clause's SUBSTANCE holds and is proved (clause 12). The parenthetical is a stale
locator, and a gate reading §5 literally would look in `tenant_modules.config`, find
nothing, and conclude the key was never wired.** §5.2's A2.3 parenthetical should be
corrected to `organizations.policy` before tomorrow.

---

## 4 · GAPS CARRIED IN DELIBERATELY, NOT DISCOVERED AT THE GATE

- **`accept_invite` is UNGRADED and it is a real user path.** It reads
  `default_permissions_for_role`, but its own *"invalid or used invite"* guard fires
  upstream of the deriver, so the referencing statement never executes. **What would make it
  gradeable:** a valid unconsumed invite whose email matches the calling JWT — a fixture
  worth building before a real invite is ever sent, not after.
- **The Material Matrix `member` row holds exactly ONE of ten keys** (`manage_purchasing:
  false`) after Monday's backfill. It was `'{}'`. Behaviour is identical — absent and false
  both resolve false — but **it is a partially-provisioned shape that did not exist before
  2026-09-08**, and it is no longer the clean "deliberately empty" control earlier probes
  used.
- **A crew member CAN read purchase orders.** The read policy is org-scoped with no
  capability. Measured with a synthetic `field` member; **0 exist live**. This is a
  controller ruling already taken, recorded here so the gate does not rediscover it.
- **`view_field` is enforced at ZERO sites** — the last inert capability. A4 owes it.
  Deliberate: there is no field surface to gate, and a control nobody can test is not a
  control.

---

## 5 · BASELINE AS MEASURED TODAY

capabilities **10 derived / 10 enforced** · roles **7**, five distinct deriver answers
including the all-false `else` · `manage_purchasing` true for **owner · admin ·
agency_admin · office** · `schedule` **6** enforcement sites · `view_field` **0** ·
`org_members` **5**, `role='field'` **0** · `organizations` **3** · purchase-order tables
exist at **0 rows** · `material_items` **0** · `schedule_blocks` **0** · `work_orders` **2**,
both masters · advisors **238, 0 ERROR** · types **4 tables / 39 columns verified against
`information_schema`, zero mismatches**.


---

## 6 · LIVE DATA THROUGH A2 — 2026-09-10

**Created through the RPCs a user would use, as Jacob (BMR `agency_admin` — the honest identity for
StructTech operating in a client tenant; nothing is attributed to Isaac), and COMMITTED.** No step
refused. Re-read in a fresh query afterwards, not trusted from the committing transaction.

| Row | id | How |
|---|---|---|
| trade `work_orders` | `195571d7-4161-4fa0-95cf-a1302c2561be` | `create_trade_work_order` under master `0ffcb7d4`, trade **"TRACK S · A2 live acceptance (Fake Lead)"** |
| `material_items` | `9616011e-5177-45c1-b829-7cd8f51322c5` | `generate_take_off` from the signed estimate's own line `e310eb90` ("Ag panel: 26 ga black replacement.") — **zero manual entry** |
| `purchase_orders` | `1256ba02-18ae-42e9-beaf-46dd85a382a6` | `create_purchase_order(p_org_id=BMR, …, job=83ff1534)`, supplier **"TRACK S · A2 acceptance supplier"**, status `draft` |
| `purchase_order_lines` | `8183c721-94a0-4f3a-bde5-bfc7a2053473` | `add_purchase_order_line`, qty 1, promised **2026-10-20** |
| `purchase_order_line_promises` | `3ab416f6-e06a-46b5-8c6f-559dc0d9241e` | written by the line add |
| `schedule_blocks` | `7253dc37-7fe7-4c40-9af1-384c8df82de5` | `add_schedule_block`, crew **"TRACK S · acceptance crew"**, 2026-10-05→10-07 |

**WHY THIS PARENT AND NOT THE OTHER.** Brothers Metal Roofing has two jobs. `a5f569ed` belongs to
**Devin Carter / The Contracting Company** — a real customer — and was **not touched**. `83ff1534`
hangs off an estimate whose client is literally **"Fake Lead"**. A standing rule from Jacob forbids
test writes against a real BMR customer record, after it went wrong twice; this parent is the one
the rule does not reach.

**RE-GRADED AGAINST THE PERSISTED ROWS:**

| # | Clause | Now | Evidence |
|---|---|---|---|
| 8 | A2.2 (a) take-off, zero manual entry, trade count named | **PASS — committed rows** | `created: 1`, `trades_with_take_off: 1` of `live_trade_count: 1`, from a **signed** estimate |
| 10 | A2.3 (1) PO date sets `ready_by` | **PASS — committed rows** | `ready_by = 2026-10-20`, `ready_by_source = purchase_order` |
| 11 | A2.3 (2) warns and still saves | **PASS — committed rows** | block saved, `ready_by_conflict = true`, *"materials not ready until 2026-10-20 (Ag panel…)"* |

**THE HONEST LIMIT ON "LIVE".** These are committed production rows that went through the real
write path — the thing a rolled-back fixture cannot prove. **They are not organic customer data:
I created them, on a test lead, for this acceptance.** The step from *rolled-back fixture* to
*committed production row* is real; the step to *a customer's real work* has not happened and will
be taken the first time Isaac orders material for a real job.

**THEY PERSIST, AS INSTRUCTED — AND THEY ARE FULLY REVERSIBLE THROUGH USER RPCS, MEASURED BEFORE
WRITING:** `work_order_activity` is `ON DELETE CASCADE` from `work_orders`, and `delete_work_order`
does not refuse on activity. So: `delete_schedule_block` → `delete_purchase_order` (line and promise
cascade) → `delete_material_item` → `delete_work_order` on the now-childless trade, whose activity
cascades with it. **No activity row was written anywhere by these calls** (checked across all
`work_order_activity` in the window, including the master's), so nothing would be left behind.
**Isaac will see them** on the Fake Lead job in his coordination screen; every row is labelled
`TRACK S ·` so they cannot be mistaken for his work.
