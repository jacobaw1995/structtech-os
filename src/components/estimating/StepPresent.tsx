import Link from "next/link";
import { presentEstimate } from "@/lib/estimating/actions";
import { formatMoney } from "@/lib/crm/stages";
import type { Database } from "@/lib/supabase/database.types";

type Estimate = Database["public"]["Tables"]["estimates"]["Row"];
type LineItem = Database["public"]["Tables"]["estimate_line_items"]["Row"];

// present_estimate() freezes presented_total from the current subtotal
// (SCOPE.md §12C price-lock habit) and, via the status check every
// line-item RPC does, locks further edits — this view goes read-only the
// moment status flips to 'presented', no separate lock step needed here.
export function StepPresent({
  orgId,
  estimate,
  lineItems,
  errorMessage,
}: {
  orgId: string;
  estimate: Estimate;
  lineItems: LineItem[];
  errorMessage?: string;
}) {
  const isPresented = estimate.status !== "validated";
  const total = estimate.presented_total ?? estimate.subtotal;

  return (
    <div className="flex flex-col gap-4">
      {errorMessage && (
        <p className="rounded-md bg-warn-soft px-3 py-2 text-xs text-text">
          {errorMessage}
        </p>
      )}

      <div className="flex flex-col gap-3 rounded-2xl border-2 border-border bg-surface p-4 group-data-[outdoor=true]/flow:border-white group-data-[outdoor=true]/flow:bg-black">
        <p className="text-xs uppercase tracking-wide text-muted group-data-[outdoor=true]/flow:text-white/60">
          Line items
        </p>

        <div className="flex flex-col divide-y divide-border text-sm group-data-[outdoor=true]/flow:divide-white/20">
          {lineItems.map((item) => (
            <div
              key={item.id}
              className="flex items-center justify-between py-1.5 text-text group-data-[outdoor=true]/flow:text-white"
            >
              <span>{item.description}</span>
              <span className="font-mono">{formatMoney(item.line_total)}</span>
            </div>
          ))}
          {lineItems.length === 0 && (
            <p className="py-1.5 text-xs text-muted group-data-[outdoor=true]/flow:text-white/60">
              No line items.
            </p>
          )}
        </div>

        <div className="flex flex-col items-center gap-1 border-t border-border pt-3 group-data-[outdoor=true]/flow:border-white/30">
          <span className="text-xs text-muted group-data-[outdoor=true]/flow:text-white/60">
            {isPresented ? "Presented total" : "Final estimate"}
          </span>
          <span className="text-3xl font-bold text-text group-data-[outdoor=true]/flow:text-white group-data-[outdoor=true]/flow:text-4xl">
            {formatMoney(total)}
          </span>
        </div>
      </div>

      {isPresented ? (
        <Link
          href={`/w/${orgId}/estimating/${estimate.id}?step=4`}
          className="flex min-h-14 items-center justify-center rounded-lg bg-accent-strong text-base font-medium text-white"
        >
          Continue to sign
        </Link>
      ) : (
        <form action={presentEstimate}>
          <input type="hidden" name="orgId" value={orgId} />
          <input type="hidden" name="estimateId" value={estimate.id} />
          <button
            type="submit"
            className="flex min-h-14 w-full items-center justify-center rounded-lg bg-accent-strong text-base font-medium text-white"
          >
            Present to client
          </button>
        </form>
      )}
    </div>
  );
}
