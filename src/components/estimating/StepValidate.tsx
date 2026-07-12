import Link from "next/link";
import { updateEstimateDetails } from "@/lib/estimating/actions";
import { formatMoney } from "@/lib/crm/stages";
import { LineItemRow } from "@/components/estimating/LineItemRow";
import { AddLineItemForm } from "@/components/estimating/AddLineItemForm";
import type { Database } from "@/lib/supabase/database.types";

type Estimate = Database["public"]["Tables"]["estimates"]["Row"];
type LineItem = Database["public"]["Tables"]["estimate_line_items"]["Row"];

// update_estimate_details() advances 'preliminary' -> 'validated' the first
// time it runs (Stage 3 migration, section 5c) — providing on-roof numbers
// IS the validation, so there's no separate "mark validated" action here.
const inputClasses =
  "rounded-md border border-border bg-bg px-2 py-2 text-sm text-text outline-none focus:border-accent group-data-[outdoor=true]/flow:border-white/40 group-data-[outdoor=true]/flow:bg-black group-data-[outdoor=true]/flow:text-white";

export function StepValidate({
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
  const locked = !["preliminary", "validated"].includes(estimate.status);
  const canContinue = estimate.status !== "preliminary";

  return (
    <div className="flex flex-col gap-4">
      {errorMessage && (
        <p className="rounded-md bg-warn-soft px-3 py-2 text-xs text-text">
          {errorMessage}
        </p>
      )}

      <div className="flex flex-col gap-3 rounded-2xl border-2 border-border bg-surface p-4 group-data-[outdoor=true]/flow:border-white group-data-[outdoor=true]/flow:bg-black">
        <p className="text-xs uppercase tracking-wide text-muted group-data-[outdoor=true]/flow:text-white/60">
          Validate measurements
        </p>

        <form
          action={updateEstimateDetails}
          className="grid grid-cols-2 gap-3"
        >
          <input type="hidden" name="orgId" value={orgId} />
          <input type="hidden" name="estimateId" value={estimate.id} />

          <label className="col-span-1 flex flex-col gap-1 text-sm">
            <span className="text-muted group-data-[outdoor=true]/flow:text-white/70">
              Roof squares
            </span>
            <input
              name="squares"
              type="number"
              inputMode="decimal"
              step="any"
              defaultValue={estimate.squares ?? ""}
              disabled={locked}
              className={inputClasses}
            />
          </label>
          <label className="col-span-1 flex flex-col gap-1 text-sm">
            <span className="text-muted group-data-[outdoor=true]/flow:text-white/70">
              Pitch
            </span>
            <input
              name="pitch"
              placeholder="6/12"
              defaultValue={estimate.pitch ?? ""}
              disabled={locked}
              className={inputClasses}
            />
          </label>
          <label className="col-span-2 flex flex-col gap-1 text-sm">
            <span className="text-muted group-data-[outdoor=true]/flow:text-white/70">
              Site address
            </span>
            <input
              name="site_address"
              defaultValue={estimate.site_address ?? ""}
              disabled={locked}
              className={inputClasses}
            />
          </label>

          {!locked && (
            <button
              type="submit"
              className="col-span-2 mt-1 min-h-14 rounded-lg bg-accent-strong text-base font-medium text-white"
            >
              Recalculate
            </button>
          )}
        </form>
      </div>

      <div className="flex flex-col gap-2 rounded-2xl border-2 border-border bg-surface p-4 group-data-[outdoor=true]/flow:border-white group-data-[outdoor=true]/flow:bg-black">
        <p className="text-xs uppercase tracking-wide text-muted group-data-[outdoor=true]/flow:text-white/60">
          Line items
        </p>

        {lineItems.length === 0 && (
          <p className="text-xs text-muted group-data-[outdoor=true]/flow:text-white/60">
            No line items yet.
          </p>
        )}

        <div className="flex flex-col divide-y divide-border group-data-[outdoor=true]/flow:divide-white/20">
          {lineItems.map((item) => (
            <LineItemRow
              key={item.id}
              orgId={orgId}
              estimateId={estimate.id}
              item={item}
              locked={locked}
            />
          ))}
        </div>

        {!locked && (
          <AddLineItemForm
            orgId={orgId}
            estimateId={estimate.id}
            nextSortOrder={lineItems.length}
          />
        )}

        <div className="mt-2 flex items-center justify-between border-t border-border pt-2 text-sm font-semibold text-text group-data-[outdoor=true]/flow:border-white/30 group-data-[outdoor=true]/flow:text-white">
          <span>Subtotal</span>
          <span className="font-mono">{formatMoney(estimate.subtotal)}</span>
        </div>
      </div>

      {canContinue && (
        <Link
          href={`/w/${orgId}/estimating/${estimate.id}?step=3`}
          className="flex min-h-14 items-center justify-center rounded-lg bg-accent-strong text-base font-medium text-white"
        >
          Continue to present
        </Link>
      )}
    </div>
  );
}
