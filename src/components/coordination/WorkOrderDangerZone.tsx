import {
  voidWorkOrder,
  restoreWorkOrder,
  deleteWorkOrder,
} from "@/lib/coordination/actions";

// Delete is only offered when nothing downstream is visible from this page
// (no materials, no schedule) — a fast client-side hint, not the real
// guard. delete_work_order() itself also checks check_ins/production_packets
// (Field module data this page doesn't fetch) and raises a clear error if
// blocked, same "UI hint + RPC is the real guard" split as
// StepPreliminary's canDelete. Void has no such restriction — cancelling a
// job with real history is exactly the case that needs to keep working.
export function WorkOrderDangerZone({
  orgId,
  workOrderId,
  voidedAt,
  canDelete,
}: {
  orgId: string;
  workOrderId: string;
  voidedAt: string | null;
  canDelete: boolean;
}) {
  return (
    <div className="flex flex-col gap-2 rounded-lg border border-warn/40 bg-surface p-3">
      <h2 className="text-xs font-semibold uppercase tracking-wide text-muted">
        Danger zone
      </h2>
      <div className="flex flex-wrap gap-2">
        {voidedAt ? (
          <form action={restoreWorkOrder}>
            <input type="hidden" name="orgId" value={orgId} />
            <input type="hidden" name="workOrderId" value={workOrderId} />
            <button
              type="submit"
              className="rounded-md border border-accent-strong px-3 py-1.5 text-xs font-medium text-accent-strong"
            >
              Restore work order
            </button>
          </form>
        ) : (
          <form action={voidWorkOrder}>
            <input type="hidden" name="orgId" value={orgId} />
            <input type="hidden" name="workOrderId" value={workOrderId} />
            <button
              type="submit"
              className="rounded-md border border-warn px-3 py-1.5 text-xs font-medium text-warn"
            >
              Void work order
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
