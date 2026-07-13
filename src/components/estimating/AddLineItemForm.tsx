import { addEstimateLineItem } from "@/lib/estimating/actions";

export function AddLineItemForm({
  orgId,
  estimateId,
  nextSortOrder,
}: {
  orgId: string;
  estimateId: string;
  nextSortOrder: number;
}) {
  return (
    <form
      action={addEstimateLineItem}
      className="flex items-center gap-2 border-t border-border pt-2 group-data-[outdoor=true]/flow:border-white/30"
    >
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="estimateId" value={estimateId} />
      <input type="hidden" name="sort_order" value={nextSortOrder} />
      <input
        name="description"
        required
        placeholder="Add line item…"
        className="min-w-0 flex-1 rounded-md border border-border bg-bg px-2 py-2 text-sm text-text outline-none focus:border-accent"
      />
      <input
        name="quantity"
        type="number"
        step="any"
        defaultValue={1}
        className="w-14 rounded-md border border-border bg-bg px-1 py-2 text-right font-mono text-sm text-text outline-none focus:border-accent"
      />
      <input
        name="unit_price"
        type="number"
        step="any"
        placeholder="0"
        className="w-20 rounded-md border border-border bg-bg px-1 py-2 text-right font-mono text-sm text-text outline-none focus:border-accent"
      />
      <button
        type="submit"
        aria-label="Add line item"
        className="h-9 w-9 shrink-0 rounded-md bg-accent-strong text-sm font-medium text-white"
      >
        +
      </button>
    </form>
  );
}
