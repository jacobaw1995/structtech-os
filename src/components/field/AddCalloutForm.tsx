import { addProductionPacketCallout } from "@/lib/field/actions";

export function AddCalloutForm({
  orgId,
  workOrderId,
  productionPacketId,
}: {
  orgId: string;
  workOrderId: string;
  productionPacketId: string;
}) {
  return (
    <form
      action={addProductionPacketCallout}
      className="flex flex-col gap-2 border-t border-border pt-2 group-data-[outdoor=true]/field:border-white/30"
    >
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="workOrderId" value={workOrderId} />
      <input type="hidden" name="productionPacketId" value={productionPacketId} />
      <input
        name="label"
        required
        placeholder="Add detail callout…"
        className="min-h-12 rounded-lg border border-border bg-bg px-3 text-sm text-text outline-none focus:border-accent group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
      />
      <input
        name="detail"
        placeholder="Detail (optional)"
        className="min-h-12 rounded-lg border border-border bg-bg px-3 text-sm text-text outline-none focus:border-accent group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
      />
      <button
        type="submit"
        className="flex min-h-12 items-center justify-center rounded-lg bg-accent-strong text-sm font-medium text-white"
      >
        + Add callout
      </button>
    </form>
  );
}
