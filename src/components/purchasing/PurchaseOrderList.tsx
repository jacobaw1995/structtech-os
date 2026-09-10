import Link from "next/link";
import {
  PO_STATUS_LABEL,
  isPoStatus,
  isStuckInDraft,
  type PurchaseOrder,
} from "@/lib/purchasing/model";
import { createPurchaseOrder } from "@/lib/purchasing/actions";

/**
 * The job's purchase orders, on the master work order.
 *
 * ON THE MASTER, NOT ON A TRADE, and that placement is the property: a PO goes
 * to ONE SUPPLIER and may cover materials across SEVERAL TRADES on one job.
 * Hanging this off a trade would quietly assert one PO per trade, which is the
 * shape the schema deliberately does not have.
 *
 * TWO PLACES, ONE COMPONENT. On a job's master work order the job is fixed.
 * At the org level (the coordination index) the job is a CHOICE, including
 * "no job yet" — a draft off a supplier phone call. That second mode exists
 * only because migration 20260910215139 made it safe: create_purchase_order
 * takes an explicit p_org_id, so a jobless draft names its tenant instead of
 * inheriting an arbitrary one from `limit 1` over a three-org membership set.
 * Until that landed this component deliberately had no jobless path.
 */
export function PurchaseOrderList({
  orgId,
  returnTo,
  jobId,
  jobs,
  orgName,
  orders,
  canPurchase,
  heading,
}: {
  orgId: string;
  /** Where a refused create sends the user back to. */
  returnTo: string;
  /** Job mode: every order created here belongs to this job. */
  jobId?: string | null;
  /** Org mode: the job is chosen, and "no job yet" is a valid choice. */
  jobs?: { id: string; label: string }[];
  orgName: string;
  orders: PurchaseOrder[];
  canPurchase: boolean;
  heading?: string;
}) {
  const orgMode = jobs !== undefined;
  return (
    <div className="rounded-lg border border-border bg-surface p-3">
      <div className="mb-2 flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
        <h2 className="text-xs font-semibold uppercase tracking-wide text-muted">
          {heading ?? "Purchase orders — one supplier each"}
        </h2>
        <span className="text-xs text-muted">
          {orders.length} order{orders.length === 1 ? "" : "s"}
          {orgMode ? ` in ${orgName}` : " on this job"}
        </span>
      </div>

      {orders.length === 0 ? (
        <p className="py-2 text-sm text-muted">
          No purchase orders yet. One order goes to one supplier and can cover
          material from any trade on this job.
        </p>
      ) : (
        <ul className="mb-2">
          {orders.map((po) => {
            const status = isPoStatus(po.status) ? po.status : "draft";
            return (
              <li key={po.id} className="border-b border-border last:border-0">
                <Link
                  href={`/w/${orgId}/coordination/po/${po.id}`}
                  className="flex min-h-14 items-center gap-3 py-2"
                >
                  <span className="min-w-0 flex-1">
                    <span className="block font-medium text-text">
                      {po.supplier_name}
                    </span>
                    <span className="block text-xs text-muted">
                      {PO_STATUS_LABEL[status]}
                      {po.reference ? ` · ${po.reference}` : ""}
                      {isStuckInDraft(po) && " · no job attached"}
                    </span>
                  </span>
                  <span aria-hidden="true" className="shrink-0 text-lg text-muted">
                    ›
                  </span>
                </Link>
              </li>
            );
          })}
        </ul>
      )}

      {canPurchase && (jobId || orgMode) ? (
        <form
          action={createPurchaseOrder}
          className="flex flex-col gap-2 border-t border-border pt-2"
        >
          <input type="hidden" name="orgId" value={orgId} />
          <input type="hidden" name="returnTo" value={returnTo} />
          {!orgMode && jobId && <input type="hidden" name="jobId" value={jobId} />}

          <div className="flex flex-col gap-2 sm:flex-row sm:items-end">
            <label className="flex min-w-0 flex-1 flex-col gap-1">
              <span className="text-[11px] font-medium uppercase tracking-wide text-muted">
                Supplier
              </span>
              <input
                name="supplier_name"
                required
                placeholder="Supplier name…"
                className="min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base text-text outline-none placeholder:text-muted focus:border-accent sm:h-10 sm:min-h-0 sm:text-sm"
              />
            </label>

            {orgMode && (
              <label className="flex min-w-0 flex-1 flex-col gap-1">
                <span className="text-[11px] font-medium uppercase tracking-wide text-muted">
                  Job
                </span>
                {/* "No job yet" is the FIRST option and the default, because the
                    workflow this mode exists for is the supplier phone call,
                    where the job is the thing you do not know yet. §2.8: it is
                    a choice, not a gate — the order saves either way. */}
                <select
                  name="jobId"
                  defaultValue=""
                  className="min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent sm:h-10 sm:min-h-0 sm:text-sm"
                >
                  <option value="">No job yet — attach one later</option>
                  {(jobs ?? []).map((j) => (
                    <option key={j.id} value={j.id}>
                      {j.label}
                    </option>
                  ))}
                </select>
              </label>
            )}

            <button
              type="submit"
              className="min-h-14 shrink-0 rounded-md bg-accent-strong px-4 text-sm font-medium text-white sm:h-10 sm:min-h-0"
            >
              Start an order
            </button>
          </div>

          {/* THE TENANT IS NAMED, NEVER INFERRED. This sentence is the
              on-screen half of p_org_id: it says out loud which workspace the
              write lands in, which is the exact fact the old signature could
              not state and got wrong for multi-org users. */}
          <p className="text-xs text-muted">
            Creates a draft in <span className="font-medium text-text">{orgName}</span>.
            {orgMode &&
              " Without a job it stays a draft — it can be edited and have items added, and it can be sent once a job is attached."}
          </p>
        </form>
      ) : !canPurchase ? (
        /* Same shape as the scheduling gate and the PO detail page: the
           control is absent, the reason is stated, no role is named. Reading
           is deliberately NOT gated — a crew needs to know what is coming. */
        <p className="border-t border-border pt-2 text-sm text-muted">
          Your role can see these orders but not raise or change them. Ask
          whoever handles purchasing in {orgName}.
        </p>
      ) : null}
    </div>
  );
}
