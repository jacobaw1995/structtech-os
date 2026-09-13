# PROPOSAL — ready-by as two facts and a held disagreement (ruling b)

Track S · 2026-09-13 · **MEASUREMENT AND PROPOSAL ONLY. NOT MIGRATED.**

## The ruling, as issued (2026-09-12)

> A VENDOR'S PROMISED DATE AND A HUMAN'S TYPED DATE ARE TWO FACTS, NOT ONE FIELD.
> The system may not resolve a disagreement between them by substitution (today's
> behaviour), and may not record one under the other's name (the behaviour before
> yesterday). Both are silent, so both are wrong. THE DISAGREEMENT IS A STATE THE
> SYSTEM HOLDS AND DISPLAYS — never a value the system picks.

Conditions: reachable FROM THE TABLE, not only from the function; carries its own
before-measurement.

## 1 · Before-measurement (live, 2026-09-13)

**Container:** `material_items`, **1 row** — all Brothers Metal Roofing; it is Track S's
acceptance row `9616011e` (created 2026-09-10 by `generate_take_off`). "Live promise" =
a `purchase_order_lines` row with `promised_date is not null` on a `purchase_orders` row
whose status is not `cancelled`. Promises container: 1 PO line (on draft PO `1256ba02`),
1 row in `purchase_order_line_promises`.

| Question | Count | What makes it that number |
|---|---|---|
| Rows with BOTH a typed date AND a live promise | **UNANSWERABLE** | The schema holds **one** date column. When a live promise governs, `update_material_item` stamps the typed date and the derivation immediately overwrites it (since 2026-09-12); before that, the typed date was stored under the `purchase_order` label. **A typed date is not retained anywhere once a promise exists.** No audit column, and `work_order_activity` records typed dates only after sign-off: **0** such rows. |
| …of those, how many DISAGREE | **UNANSWERABLE** (same reason) | Proxy that *can* be counted: items with a live promise whose stored `ready_by` differs from the max live promise: **0 of 1**. That measures whether the derivation ran, not whether a human disagreed. |
| Rows with a typed date and NO live promise | **0** | `ready_by is not null` with no live promise (sources `manual` or `orphaned`): 0. |
| Rows with a live promise and NO typed date | **1 with a live promise; typed-date presence UNANSWERABLE** | 1 item has a live promise. Whether a human ever typed a date on it is not recorded. |

Also measured: `ready_by_source` distribution `{purchase_order: 1}`; items with no date
and no promise: 0.

**The denominator for Monday is effectively one synthetic row.** The design cannot be
validated against organic data that does not exist yet; it has to be validated by probes.

## 2 · What the table can be written by today (reachability)

- `material_items` has **direct INSERT/UPDATE policies** for members (`member insert own`,
  `member update own`). A direct `update material_items set ready_by = …` bypasses
  `update_material_item`'s stamp AND the recompute — the only trigger on the table is
  `material_items_trim_text`.
- Writers of `ready_by` in the database: `add_material_item`, `update_material_item`,
  `recompute_material_item_ready_by`. Readers: `add_schedule_block`,
  `update_schedule_block`, `schedule_blocks_ready_by_gate` (trigger),
  `create_work_order_agreement`.
- `purchase_order_lines` and `purchase_orders` also accept direct writes, and the
  recompute is called **only from RPCs** — a direct promise change moves no date
  (deferred 2026-09-12).
- App surfaces reading or writing ready-by (merged tree `eacaf48`):
  `src/lib/coordination/actions.ts` (262 — the call in the ruling),
  `src/components/coordination/MaterialItemRow.tsx` (typed input, prefilled, submits on blur),
  `src/components/coordination/AddMaterialItemForm.tsx`,
  `src/components/coordination/ScheduleBlockRow.tsx`,
  `src/components/purchasing/PoLineRow.tsx` (still renders anything not `purchase_order`
  as "set by hand" — `orphaned` unhandled on `main`),
  `src/app/w/[orgId]/coordination/po/[poId]/page.tsx`,
  `src/app/w/[orgId]/coordination/[workOrderId]/page.tsx`,
  `src/app/w/[orgId]/field/page.tsx`.

## 3 · Proposed shape

**Two stored facts, one derived state, no picked value.**

1. `material_items.ready_by_typed date null` + `ready_by_typed_at timestamptz` +
   `ready_by_typed_by uuid` — what a human said, and who, and when. Written only by a
   human action. Never overwritten by a promise.
2. `material_items.ready_by_promised date null` — max `promised_date` over live PO lines.
   **Maintained by triggers on `purchase_order_lines` (insert/update/delete) and on
   `purchase_orders` (status change)**, not by RPC calls, so a direct write to either PO
   table moves it. This replaces `recompute_material_item_ready_by`'s call sites.
3. `material_items.ready_by_state text not null` with CHECK in
   `none · typed · promised · agree · disagree`, **computed by a BEFORE INSERT OR UPDATE
   trigger on `material_items` that overwrites whatever a writer supplies** (the
   2026-09-13 `schedule_blocks` lesson: fire on every write, no column list).
   `disagree` = both present and not equal. The state is the thing displayed.
4. `ready_by_source` and `orphaned` become derivable (`orphaned` = no live promise but a
   promise history exists) — retire or keep as a view column; decide at build.

**What is deliberately NOT proposed:** a single "effective" date column. That column is
the substitution the ruling forbids, moved one column over.

## 4 · The decision this forces — needs a ruling before build

**The schedule gate needs an answer when the two facts disagree.** Today
`schedule_blocks_ready_by_gate` and both schedule RPCs read one `ready_by`. Options:

- **(i) Conflict against EITHER fact** — a block starting before the typed date OR the
  promised date is `ready_by_conflict`, and the reason names both dates and which one it
  is short of. Nothing is picked; the stricter test falls out of holding both. Under
  gating ON this refuses more than today.
- **(ii) Disagreement is its own conflict** — `ready_by_state = 'disagree'` marks every
  block on that trade as in conflict until a human resolves it, regardless of dates.
- **(iii)** Gate on the promised date only, display the disagreement. **This is a pick**
  and is listed only so it is visibly rejected.

Track S recommends **(i)**: it holds both facts and derives the conflict from both
without choosing one.

**Also open:** how a human RESOLVES a disagreement (clear the typed date? accept the
promise? record "vendor is wrong"?). Resolution must be an action with an actor, not a
state the system infers.

## 5 · Build-day before-measurement (to be re-run, not copied)

Re-run section 1 immediately before migrating, plus: count of `schedule_blocks` whose
`ready_by_conflict` would change under option (i) — that is the number of blocks the
change would newly refuse or flag, and it is the narrowing to name.
Callers to name on build day: every surface listed in section 2.
