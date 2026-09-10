# A2 ACCEPTANCE — PRE-FLIGHT EVIDENCE

**Track S · 2026-09-09 · for the G2 gate on 2026-09-10.**
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
