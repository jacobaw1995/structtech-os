import { recordWorkOrderSignOff } from "@/lib/coordination/actions";
import { formatDate } from "@/lib/crm/stages";
import type { Database } from "@/lib/supabase/database.types";

type WorkOrder = Database["public"]["Tables"]["work_orders"]["Row"];

// Soft capture, not a gate (migration header note 1) — this panel is
// informational either way, never blocks the materials/schedule sections
// below it on the same page.
export function SignOffPanel({
  orgId,
  workOrder,
}: {
  orgId: string;
  workOrder: WorkOrder;
}) {
  if (workOrder.sign_off_at) {
    return (
      <div className="rounded-lg border border-border bg-surface p-3">
        <p className="text-sm font-medium text-text">
          Homeowner sign-off complete — {formatDate(workOrder.sign_off_at)}
        </p>
        {workOrder.sign_off_notes && (
          <p className="mt-1 text-sm text-muted">{workOrder.sign_off_notes}</p>
        )}
      </div>
    );
  }

  return (
    <form
      action={recordWorkOrderSignOff}
      className="flex flex-col gap-2 rounded-lg border border-border bg-surface p-3"
    >
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="workOrderId" value={workOrder.id} />
      <p className="text-sm font-medium text-text">
        Homeowner sign-off — colors &amp; finishes
      </p>
      <textarea
        name="notes"
        placeholder="Notes (colors, finishes, special requests)…"
        rows={2}
        className="rounded-md border border-border bg-bg px-2 py-2 text-sm text-text outline-none focus:border-accent"
      />
      <button
        type="submit"
        className="flex min-h-11 items-center justify-center rounded-lg bg-accent-strong text-sm font-medium text-white"
      >
        Mark sign-off complete
      </button>
    </form>
  );
}
