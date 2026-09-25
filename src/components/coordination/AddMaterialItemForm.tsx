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
        {/* U-W1.32 (2026-09-23) — NO defaultValue, AND required. U-W1.12 took
            the pre-filled 1 off the PO LINE form ("price and quantity are asked,
            not assumed") and left the identical assumption one form over, on the
            material that the PO line is later raised against. Found by sweeping
            the class instead of fixing the instance.

            WHY `required` AND NOT ONLY AN EMPTY BOX, and this is the whole
            reason the surface fix is shaped this way: add_material_item declares
            `p_quantity numeric DEFAULT 1`, material_items.quantity is NOT NULL
            DEFAULT 1, and no refusal exists for a missing quantity (measured
            2026-09-23). So an empty box alone would move the assumption from
            VISIBLE (a 1 the user can see and change) to INVISIBLE (a 1 written
            by the database with nobody told) — strictly worse. `required` means
            the number is always the user's.

            RESIDUAL, REPORTED TO S: a submit that bypasses the browser check
            still lands on the RPC default. Closing it properly is the PO-line
            treatment — drop the RPC's DEFAULT and add a named refusal — and
            that is S's to do. */}
        <input
          name="quantity"
          type="number"
          step="any"
          required
          placeholder="Qty"
          aria-label="Quantity"
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
