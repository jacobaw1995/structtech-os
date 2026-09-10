import { formatDateOnly } from "@/lib/coordination/stage";
import type { PurchaseOrderLine } from "@/lib/purchasing/model";
import {
  updatePurchaseOrderLine,
  deletePurchaseOrderLine,
} from "@/lib/purchasing/actions";

/**
 * One line on a purchase order, with its PROMISE HISTORY.
 *
 * The history is the point. `purchase_order_line_promises` is append-only —
 * SELECT and INSERT policies, no UPDATE and no DELETE policy at all — and
 * `update_purchase_order_line` writes a row only when the date actually
 * changes. So the rows are the distinct dates that have been promised, and
 * "they moved it three times" is a fact rather than an impression. A surface
 * that showed only the current date would throw away the one thing the table
 * exists to record.
 */
export function PoLineRow({
  orgId,
  poId,
  line,
  itemName,
  itemUnit,
  itemQuantity,
  trade,
  readyBy,
  readyBySource,
  history,
  timesMoved,
  canPurchase,
}: {
  orgId: string;
  poId: string;
  line: PurchaseOrderLine;
  itemName: string;
  itemUnit: string | null;
  itemQuantity: number | null;
  trade: string | null;
  readyBy: string | null;
  readyBySource: string;
  history: { id: string; promised_date: string | null; recorded_at: string }[];
  timesMoved: number;
  canPurchase: boolean;
}) {
  // A MATERIAL ITEM MAY BE SPLIT ACROSS MORE THAN ONE PO — there is no unique
  // index on material_item_id. So the quantity on THIS line is not necessarily
  // the whole item, and the row says "12 of 40 sq" rather than just "12".
  const partial =
    itemQuantity !== null && Number(line.quantity_ordered) < Number(itemQuantity);

  return (
    <li className="border-b border-border px-4 py-3 last:border-0">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          <p className="font-medium text-text">{itemName}</p>
          <p className="text-xs text-muted">
            {trade ? `${trade} · ` : ""}
            <span className="tabular-nums">
              {line.quantity_ordered}
              {itemQuantity !== null ? ` of ${itemQuantity}` : ""}
              {itemUnit ? ` ${itemUnit}` : ""}
            </span>
            {partial && " · part of this item is on another order"}
          </p>

          {/* READY-BY IS DERIVED AND IS NEVER TYPED. It is shown here as a
              consequence of the promises, not as a field. `ready_by_source`
              says WHICH BRANCH FIRED: 'purchase_order' when the promise set is
              non-empty, 'manual' when it is empty — and on the empty branch
              the DATE IS KEPT rather than nulled, so this is not an empty
              state and must not be drawn as one. */}
          {readyBy && (
            <p className="mt-1 text-xs text-muted">
              Material ready by{" "}
              <span className="font-medium tabular-nums text-text">
                {formatDateOnly(readyBy)}
              </span>
              {readyBySource === "purchase_order"
                ? " — from the promised dates on this and any other order"
                : " — set by hand; no live promise is driving it"}
            </p>
          )}
        </div>

      </div>

      {/* THE HISTORY. Oldest first: the first row is what was originally
          promised, the last is what is promised now. */}
      {history.length > 0 && (
        <div className="mt-2 rounded-md bg-surface2 px-3 py-2">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted">
            Promised date
            {timesMoved > 0 &&
              ` · moved ${timesMoved} time${timesMoved === 1 ? "" : "s"}`}
          </p>
          <ol className="mt-1 space-y-0.5">
            {history.map((h, i) => {
              const last = i === history.length - 1;
              return (
                <li
                  key={h.id}
                  className={`flex flex-wrap items-baseline gap-x-2 text-xs ${
                    last ? "text-text" : "text-muted"
                  }`}
                >
                  {/* The strike-through is on the DATE only. `recorded Sep 4`
                      is not superseded — it is when someone was told, and that
                      stays true. Striking the whole line said otherwise. */}
                  <span
                    className={`font-medium tabular-nums ${
                      last ? "" : "line-through decoration-muted/60"
                    }`}
                  >
                    {h.promised_date ? formatDateOnly(h.promised_date) : "no date"}
                  </span>
                  <span className="tabular-nums text-[11px] text-muted">
                    recorded {recordedOn(h.recorded_at)}
                  </span>
                  {last && <span className="text-[11px] text-muted">· current</span>}
                </li>
              );
            })}
          </ol>
        </div>
      )}

      {canPurchase && (
        /* U-W1.9 — COLLAPSED BEHIND A NATIVE <details>. Measured on a
           fifteen-line order at 375x812 before this change: 30 visible inputs
           (a date and a quantity on every line), 30 buttons (a Save and a ✕ on
           every line), and a scroll height of 7,386px — 9.1 screens of form to
           read one purchase order. The catalogue had the same shape before its
           design pass.

           WHAT STAYS OUT, UNTAPPED: everything you READ — item, trade,
           "12 of 40", ready-by and its source, and the full promise history.
           Reading an order never needs a tap.

           WHAT IS ONE TAP AWAY: changing the promised date, which is the field
           that actually moves (it is the reason the history table exists).
           The summary is labelled by that act rather than by "Edit", so the
           common action is named, not hidden inside a generic one. Quantity and
           Remove live inside the same disclosure — quantity rarely changes, and
           Remove is destructive, so fifteen of them in thumb reach was a
           mis-tap waiting to happen.

           <details> rather than client state: no JS, keyboard-accessible, and
           it closes itself on the redirect after a save, which is the right
           behaviour. */
        <details className="group mt-2">
          <summary className="flex min-h-14 cursor-pointer list-none items-center gap-2 rounded-md border border-border px-3 text-sm font-medium text-text sm:h-10 sm:min-h-0 sm:w-fit [&::-webkit-details-marker]:hidden">
            <span aria-hidden="true" className="text-muted transition-transform group-open:rotate-90">
              ›
            </span>
            Record a new promised date
          </summary>

          <div className="mt-2 flex flex-col gap-3 rounded-md border border-border p-3">
            <form
              action={updatePurchaseOrderLine}
              className="flex flex-col gap-2 sm:flex-row sm:items-end"
            >
              <input type="hidden" name="orgId" value={orgId} />
              <input type="hidden" name="poId" value={poId} />
              <input type="hidden" name="lineId" value={line.id} />
              {/* The date comes FIRST and is the default focus of the
                  disclosure — it is what you opened it for. */}
              <label className="flex flex-col gap-1">
                <span className="text-[11px] font-medium uppercase tracking-wide text-muted">
                  New promised date
                </span>
                <input
                  name="promised_date"
                  type="date"
                  className="min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent sm:h-10 sm:w-auto sm:min-h-0 sm:text-sm"
                />
              </label>
              <label className="flex flex-col gap-1">
                <span className="text-[11px] font-medium uppercase tracking-wide text-muted">
                  Quantity
                </span>
                <input
                  name="quantity_ordered"
                  type="number"
                  step="0.001"
                  inputMode="decimal"
                  defaultValue={line.quantity_ordered}
                  className="min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base tabular-nums text-text outline-none focus:border-accent sm:h-10 sm:w-28 sm:min-h-0 sm:text-sm"
                />
              </label>
              <button
                type="submit"
                className="min-h-14 rounded-md bg-accent-strong px-4 text-sm font-medium text-white sm:h-10 sm:min-h-0"
              >
                Save
              </button>
            </form>

            {/* Remove, not cancel: cancellation lives on the PO header and a
                line has no status column to cancel into. Inside the
                disclosure so it is deliberate — two taps, not one. */}
            <form action={deletePurchaseOrderLine} className="border-t border-border pt-3">
              <input type="hidden" name="orgId" value={orgId} />
              <input type="hidden" name="poId" value={poId} />
              <input type="hidden" name="lineId" value={line.id} />
              <button
                type="submit"
                aria-label={`Remove ${itemName} from this order`}
                className="min-h-14 rounded-md px-3 text-sm text-muted hover:text-warn sm:h-9 sm:min-h-0"
              >
                Remove from this order
              </button>
            </form>
          </div>
        </details>
      )}
    </li>
  );
}

/**
 * `recorded_at` is a timestamptz and arrives as UTC (`…T22:19:10+00:00`). The
 * first version of this file took `.slice(0, 10)` of it — a UTC CALENDAR DATE —
 * which is correct until 8 PM Eastern and then silently shows TOMORROW, the
 * exact rollover CLAUDE.md records as having mis-stamped the A1 acceptance.
 * Every fixture used `T10:00:00Z`, which never crosses midnight, so the defect
 * could not appear in one. It surfaced only against the first LIVE promise row
 * on 2026-09-10, recorded at 22:19 UTC.
 *
 * America/New_York because the project runs on it (CLAUDE.md) and BMR is on
 * Eastern time. A per-tenant timezone would be the general answer; there is no
 * such column today, and inventing one is not a surface task.
 */
function recordedOn(iso: string): string {
  return new Date(iso).toLocaleDateString("en-US", {
    timeZone: "America/New_York",
    month: "short",
    day: "numeric",
  });
}
