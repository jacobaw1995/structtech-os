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
 * CREATION ALWAYS CARRIES THE JOB. `job_id` is nullable and drafting off a
 * supplier phone call is a real workflow — but `create_purchase_order`'s
 * no-job branch resolves the org with `select org_id from org_members where
 * user_id = auth.uid() limit 1`, no ORDER BY and no org argument, so for a
 * multi-org user it picks arbitrarily. The one person who would draft that way
 * is in three orgs. And nothing writes job_id after the insert, so such a PO
 * could never leave draft. Offering the control would be handing someone a
 * one-way door into possibly the wrong tenant. Reported, not worked around.
 */
export function PurchaseOrderList({
  orgId,
  workOrderId,
  jobId,
  orgName,
  orders,
  canPurchase,
}: {
  orgId: string;
  workOrderId: string;
  jobId: string | null;
  orgName: string;
  orders: PurchaseOrder[];
  canPurchase: boolean;
}) {
  return (
    <div className="rounded-lg border border-border bg-surface p-3">
      <div className="mb-2 flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
        <h2 className="text-xs font-semibold uppercase tracking-wide text-muted">
          Purchase orders — one supplier each
        </h2>
        <span className="text-xs text-muted">
          {orders.length} order{orders.length === 1 ? "" : "s"} on this job
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

      {canPurchase && jobId ? (
        <form
          action={createPurchaseOrder}
          className="flex flex-col gap-2 border-t border-border pt-2 sm:flex-row sm:items-center"
        >
          <input type="hidden" name="orgId" value={orgId} />
          <input type="hidden" name="workOrderId" value={workOrderId} />
          <input type="hidden" name="jobId" value={jobId} />
          <input
            name="supplier_name"
            required
            placeholder="Supplier name…"
            aria-label="Supplier name"
            className="min-h-14 w-full flex-1 rounded-md border border-border bg-bg px-2 text-base text-text outline-none placeholder:text-muted focus:border-accent sm:h-10 sm:min-h-0 sm:text-sm"
          />
          <button
            type="submit"
            className="min-h-14 shrink-0 rounded-md bg-accent-strong px-4 text-sm font-medium text-white sm:h-10 sm:min-h-0"
          >
            Start an order
          </button>
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
