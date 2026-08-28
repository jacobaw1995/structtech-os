import { generateTakeOff } from "@/lib/coordination/actions";

// A2.2 clause (b), as a real user path rather than a synthetic one.
//
// A take-off lands materials on a TRADE (controller decision 2026-08-28), so
// the master can never be a valid destination. The control still lives here,
// and still submits, because the master is where a PM forms the intention
// "turn this estimate into materials" — and because SCOPE §2.8 forbids a
// button that is disabled or hidden on account of other data being absent.
// generate_take_off answers it by naming the job's live trade count and the
// next action. On a job with zero trades that is exactly clause (b)'s refusal;
// on a job with trades it is a routing message. Neither silently does nothing.
export function MasterTakeOffCard({
  orgId,
  masterWorkOrderId,
  liveTradeCount,
}: {
  orgId: string;
  masterWorkOrderId: string;
  liveTradeCount: number;
}) {
  return (
    <div className="rounded-lg border border-border bg-surface p-3">
      <h2 className="mb-1 text-xs font-semibold uppercase tracking-wide text-muted">
        Take-off
      </h2>
      <p className="mb-2 text-sm text-muted">
        {liveTradeCount === 0
          ? "Materials attach to a trade, and this job has no trades yet. Add a trade above, then open it to run the take-off."
          : `Open a trade and run the take-off there — this job has ${liveTradeCount} live trade${liveTradeCount === 1 ? "" : "s"}.`}
      </p>
      <form action={generateTakeOff}>
        <input type="hidden" name="orgId" value={orgId} />
        <input type="hidden" name="workOrderId" value={masterWorkOrderId} />
        <button
          type="submit"
          className="flex min-h-11 items-center justify-center rounded-lg border border-border bg-bg px-4 text-sm font-medium text-text"
        >
          Generate take-off
        </button>
      </form>
    </div>
  );
}
