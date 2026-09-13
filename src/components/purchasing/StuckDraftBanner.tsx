import { attachJobToPurchaseOrder } from "@/lib/purchasing/actions";

/**
 * The jobless-draft banner, and the control that follows its advice.
 *
 * Extracted from the PO page (U-W1.9) so it can be RENDERED AND LOOKED AT
 * without a signed-in session, the same reason CatalogList and CatalogToolbar
 * were extracted on 09-03. The page renders this component and nothing else
 * renders the banner.
 *
 * §2.8 — warn at draft time, block only at the transition. The draft stays
 * fully editable. The TRANSITION is offered only together with a job:
 * update_purchase_order checks the draft-exit rule against
 * coalesce(p_job_id, current job), so "attach and mark sent" is ONE write the
 * database accepts — never a bare "Mark sent" it would refuse.
 */
export function StuckDraftBanner({
  orgId,
  poId,
  orgName,
  canPurchase,
  jobChoices,
}: {
  orgId: string;
  poId: string;
  orgName: string;
  canPurchase: boolean;
  jobChoices: { id: string; label: string }[];
}) {
  return (
    <section className="rounded-lg border border-warn bg-warn-soft px-4 py-3">
      <h2 className="text-sm font-semibold text-text">
        No job attached — this order can&rsquo;t be sent yet
      </h2>
      {/* Role-dependent, and found by READING THE RENDERED TEXT for a reader
          without manage_purchasing: the first draft told everyone "edit it
          and add items freely", which is false for a role that can do
          neither. A sentence that is true for one role and false for another
          has to know which reader it has. */}
      <p className="mt-1 text-sm leading-relaxed text-text">
        {canPurchase
          ? "It\u2019s a working draft: edit it and add items freely. To send or confirm it, attach the job it\u2019s for."
          : "It\u2019s still a draft, and it can\u2019t be sent until the job it\u2019s for is attached."}
      </p>

      {!canPurchase ? (
        <p className="mt-2 text-xs leading-relaxed text-muted">
          Attaching a job is done by whoever handles purchasing in{" "}
          {orgName}.
        </p>
      ) : jobChoices.length === 0 ? (
        <p className="mt-2 text-xs leading-relaxed text-muted">
          There are no jobs in {orgName} to attach it to yet. A
          job appears once a signed estimate is converted on the
          Coordination page.
        </p>
      ) : (
        <form action={attachJobToPurchaseOrder} className="mt-3 flex flex-col gap-2">
          <input type="hidden" name="orgId" value={orgId} />
          <input type="hidden" name="poId" value={poId} />
          <label className="flex flex-col gap-1">
            <span className="text-[11px] font-medium uppercase tracking-wide text-muted">
              Job this order is for
            </span>
            <select
              name="jobId"
              required
              defaultValue=""
              className="min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent sm:h-10 sm:min-h-0 sm:text-sm"
            >
              <option value="" disabled>
                Choose a job…
              </option>
              {jobChoices.map((j) => (
                <option key={j.id} value={j.id}>
                  {j.label}
                </option>
              ))}
            </select>
          </label>
          {/* One job picker, three outcomes. Each button submits the SAME
              job with a different status, in one call. */}
          <div className="flex flex-wrap gap-2">
            <button
              type="submit"
              className="min-h-14 rounded-md border border-border bg-surface px-4 text-sm font-medium text-text sm:h-10 sm:min-h-0"
            >
              Attach, keep as draft
            </button>
            <button
              type="submit"
              name="status"
              value="sent"
              className="min-h-14 rounded-md bg-accent-strong px-4 text-sm font-medium text-white sm:h-10 sm:min-h-0"
            >
              Attach and mark Sent
            </button>
            <button
              type="submit"
              name="status"
              value="confirmed"
              className="min-h-14 rounded-md border border-border bg-surface px-4 text-sm font-medium text-text sm:h-10 sm:min-h-0"
            >
              Attach and mark Confirmed
            </button>
          </div>
        </form>
      )}
    </section>
  );
}
