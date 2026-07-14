import { addMaterialItem } from "@/lib/coordination/actions";

export function AddMaterialItemForm({
  orgId,
  workOrderId,
  nextSortOrder,
}: {
  orgId: string;
  workOrderId: string;
  nextSortOrder: number;
}) {
  return (
    // Same mobile stacking as MaterialItemRow: name on its own row, then
    // qty + ready_by + the add button share a second row (sm:contents
    // collapses that wrapper at desktop size back to the original
    // single-line layout).
    <form
      action={addMaterialItem}
      className="flex flex-col gap-2 border-t border-border pt-2 sm:flex-row sm:items-center"
    >
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="workOrderId" value={workOrderId} />
      <input type="hidden" name="sort_order" value={nextSortOrder} />
      <input
        name="name"
        required
        placeholder="Add material…"
        className="min-h-14 w-full min-w-0 rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent sm:min-h-0 sm:flex-1 sm:py-2 sm:text-sm"
      />
      <div className="flex items-center gap-2 sm:contents">
        <input
          name="quantity"
          type="number"
          step="any"
          defaultValue={1}
          className="min-h-14 w-24 rounded-md border border-border bg-bg px-1 text-right font-mono text-base text-text outline-none focus:border-accent sm:min-h-0 sm:w-14 sm:py-2 sm:text-sm"
        />
        <input
          name="ready_by"
          type="date"
          className="min-h-14 flex-1 rounded-md border border-border bg-bg px-1 text-base text-text outline-none focus:border-accent sm:min-h-0 sm:w-36 sm:flex-none sm:py-2 sm:text-sm"
        />
        <button
          type="submit"
          aria-label="Add material"
          className="flex h-14 w-14 shrink-0 items-center justify-center rounded-md bg-accent-strong text-base font-medium text-white sm:h-9 sm:w-9 sm:text-sm"
        >
          +
        </button>
      </div>
    </form>
  );
}
