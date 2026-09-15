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
 * QUANTITY IS REQUIRED AND STARTS EMPTY. Since 20260913012939 the RPC has
 * no quantity default and refuses null with its own named cause. The form
 * used to pre-fill 1, which answered for the user and kept that refusal from
 * ever being seen. A PROMISED DATE IS NOT required — the migration says so
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
          Quantity <span className="text-[var(--warn-strong)]">· required</span>
        </span>
        {/* U-W1.12 — NO defaultValue. It used to be pre-filled with 1, which
            made the field `required` in name only: a user who never touched it
            ordered one of everything, and the RPC's own named refusal ("enter
            a quantity to order — a supplier cannot be sent an order with no
            quantity") could never fire, because the box was never empty.
            Track S removed the RPC's DEFAULT 1 in 20260913012939; the form was
            still supplying it. */}
        <input
          name="quantity_ordered"
          type="number"
          step="0.001"
          min="0.001"
          inputMode="decimal"
          placeholder="How many?"
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
