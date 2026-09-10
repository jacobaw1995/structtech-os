import { addPurchaseOrderLine } from "@/lib/purchasing/actions";

/**
 * Add a material item to this purchase order.
 *
 * THE ITEM LIST IS THE WHOLE JOB'S, NOT ONE TRADE'S. A purchase order goes to
 * one supplier and may cover materials across several trades on one job, so
 * restricting this picker to a single trade would design out the property the
 * schema exists to support. Items are grouped by trade so the crossing is
 * visible while you pick.
 *
 * QUANTITY IS REQUIRED even though the RPC parameter has a default:
 * `add_purchase_order_line` raises "quantity ordered must be greater than
 * zero" when it arrives null, so an optional-looking field would be a control
 * the backend refuses. A PROMISED DATE IS NOT required — the migration says so
 * explicitly ("SCOPE 2.8: a line with no promised_date saves"), because you
 * order first and learn the date later.
 */
export function AddPoLineForm({
  orgId,
  poId,
  items,
  cancelled,
}: {
  orgId: string;
  poId: string;
  items: { id: string; name: string; unit: string | null; trade: string }[];
  cancelled: boolean;
}) {
  if (items.length === 0) {
    return (
      <p className="border-t border-border px-4 py-3 text-sm text-muted">
        This job has no material items yet. Add them on a trade&rsquo;s work
        order first, then they can be put on an order here.
      </p>
    );
  }

  const trades = Array.from(new Set(items.map((i) => i.trade))).sort();

  return (
    <form
      action={addPurchaseOrderLine}
      className="flex flex-col gap-2 border-t border-border px-4 py-3 sm:flex-row sm:items-end"
    >
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="poId" value={poId} />

      <label className="flex min-w-0 flex-1 flex-col gap-1">
        <span className="text-[11px] font-medium uppercase tracking-wide text-muted">
          Material item
        </span>
        <select
          name="material_item_id"
          required
          className="min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent sm:h-10 sm:min-h-0 sm:text-sm"
        >
          {trades.map((t) => (
            <optgroup key={t} label={t}>
              {items
                .filter((i) => i.trade === t)
                .map((i) => (
                  <option key={i.id} value={i.id}>
                    {i.name}
                    {i.unit ? ` (${i.unit})` : ""}
                  </option>
                ))}
            </optgroup>
          ))}
        </select>
      </label>

      <label className="flex flex-col gap-1">
        <span className="text-[11px] font-medium uppercase tracking-wide text-muted">
          Quantity
        </span>
        <input
          name="quantity_ordered"
          type="number"
          step="0.001"
          min="0.001"
          inputMode="decimal"
          defaultValue={1}
          required
          className="min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base tabular-nums text-text outline-none focus:border-accent sm:h-10 sm:w-28 sm:min-h-0 sm:text-sm"
        />
      </label>

      <label className="flex flex-col gap-1">
        <span className="text-[11px] font-medium uppercase tracking-wide text-muted">
          Promised date
        </span>
        <input
          name="promised_date"
          type="date"
          className="min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent sm:h-10 sm:w-auto sm:min-h-0 sm:text-sm"
        />
      </label>

      <button
        type="submit"
        className="min-h-14 rounded-md bg-accent-strong px-4 text-sm font-medium text-white sm:h-10 sm:min-h-0"
      >
        Add item
      </button>

      {cancelled && (
        <p className="basis-full text-xs text-muted">
          This order is cancelled — anything added here will not count toward
          material ready-by dates until it is reopened.
        </p>
      )}
    </form>
  );
}
