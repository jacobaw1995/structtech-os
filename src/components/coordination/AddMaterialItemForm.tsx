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
    <form
      action={addMaterialItem}
      className="flex items-center gap-2 border-t border-border pt-2"
    >
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="workOrderId" value={workOrderId} />
      <input type="hidden" name="sort_order" value={nextSortOrder} />
      <input
        name="name"
        required
        placeholder="Add material…"
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
        name="ready_by"
        type="date"
        className="w-36 rounded-md border border-border bg-bg px-1 py-2 text-sm text-text outline-none focus:border-accent"
      />
      <button
        type="submit"
        aria-label="Add material"
        className="h-9 w-9 shrink-0 rounded-md bg-accent-strong text-sm font-medium text-white"
      >
        +
      </button>
    </form>
  );
}
