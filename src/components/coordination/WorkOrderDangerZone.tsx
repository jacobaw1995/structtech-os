import Link from "next/link";
import {
  voidWorkOrder,
  restoreWorkOrder,
  deleteWorkOrder,
} from "@/lib/coordination/actions";

// A1.4 — void/restore are hierarchy-aware, so the buttons have to say which
// rows they will move. Three distinct voided states exist and they are not
// interchangeable:
//
//   live                                    → offer Void (naming the trades it takes with it)
//   voided in its own right                 → offer Restore
//   voided by its master's cascade          → NO restore here; restoring the
//                                             master is what brings it back,
//                                             and restore_work_order refuses a
//                                             trade whose master is still voided.
//
// Delete is unchanged in shape but no longer only a UI hint on a master:
// delete_work_order now refuses a master that has trades and names the count.
// canDelete keeps the button off the page in the case the RPC would refuse,
// which is a hint, not the guard.
export function WorkOrderDangerZone({
  orgId,
  workOrderId,
  voidedAt,
  voidedByCascade,
  masterId,
  liveTradeCount,
  cascadeVoidedTradeCount,
  canDelete,
}: {
  orgId: string;
  workOrderId: string;
  voidedAt: string | null;
  voidedByCascade: boolean;
  masterId: string | null;
  liveTradeCount: number;
  cascadeVoidedTradeCount: number;
  canDelete: boolean;
}) {
  const isVoided = voidedAt !== null;

  return (
    <div className="flex flex-col gap-2 rounded-lg border border-warn/40 bg-surface p-3">
      <h2 className="text-xs font-semibold uppercase tracking-wide text-muted">
        Danger zone
      </h2>

      {isVoided && voidedByCascade && (
        <p className="text-xs text-muted">
          Voided together with its master work order. Restoring the master
          brings this trade back with it.
          {masterId && (
            <>
              {" "}
              <Link
                href={`/w/${orgId}/coordination/${masterId}`}
                className="text-accent-strong underline"
              >
                Go to the master work order
              </Link>
            </>
          )}
        </p>
      )}

      {isVoided && !voidedByCascade && cascadeVoidedTradeCount > 0 && (
        <p className="text-xs text-muted">
          {cascadeVoidedTradeCount} trade
          {cascadeVoidedTradeCount === 1 ? " was" : "s were"} voided with this
          work order and will come back when it is restored. Trades voided on
          their own stay voided.
        </p>
      )}

      {!isVoided && liveTradeCount > 0 && (
        <p className="text-xs text-muted">
          Voiding this work order also voids its {liveTradeCount} live trade
          {liveTradeCount === 1 ? "" : "s"}. Trades already voided on their own
          are left alone.
        </p>
      )}

      <div className="flex flex-wrap gap-2">
        {isVoided ? (
          // A cascade-voided trade gets no restore button: the RPC refuses it
          // while the master is voided, so offering it would only produce an
          // error message. The pointer to the master above is the way back.
          !voidedByCascade && (
            <form action={restoreWorkOrder}>
              <input type="hidden" name="orgId" value={orgId} />
              <input type="hidden" name="workOrderId" value={workOrderId} />
              <button
                type="submit"
                className="rounded-md border border-accent-strong px-3 py-1.5 text-xs font-medium text-accent-strong"
              >
                {cascadeVoidedTradeCount > 0
                  ? `Restore work order + ${cascadeVoidedTradeCount} trade${
                      cascadeVoidedTradeCount === 1 ? "" : "s"
                    }`
                  : "Restore work order"}
              </button>
            </form>
          )
        ) : (
          <form action={voidWorkOrder}>
            <input type="hidden" name="orgId" value={orgId} />
            <input type="hidden" name="workOrderId" value={workOrderId} />
            <button
              type="submit"
              className="rounded-md border border-warn px-3 py-1.5 text-xs font-medium text-warn"
            >
              {liveTradeCount > 0
                ? `Void work order + ${liveTradeCount} trade${
                    liveTradeCount === 1 ? "" : "s"
                  }`
                : "Void work order"}
            </button>
          </form>
        )}
        {canDelete && (
          <form action={deleteWorkOrder}>
            <input type="hidden" name="orgId" value={orgId} />
            <input type="hidden" name="workOrderId" value={workOrderId} />
            <button
              type="submit"
              className="rounded-md border border-warn px-3 py-1.5 text-xs font-medium text-warn"
            >
              Delete work order
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
