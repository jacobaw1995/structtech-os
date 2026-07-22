import { recordWorkOrderSignOff } from "@/lib/coordination/actions";
import { formatDate } from "@/lib/crm/stages";
import { formatWorkOrderActivityLine } from "@/lib/coordination/stage";
import type { Database } from "@/lib/supabase/database.types";

type WorkOrder = Database["public"]["Tables"]["work_orders"]["Row"];
type WorkOrderActivity = Database["public"]["Tables"]["work_order_activity"]["Row"];

// Soft capture, not a gate (migration header note 1) — this panel is
// informational either way, never blocks the materials/schedule sections
// below it on the same page.
//
// Task B (7/24 walkthrough) — interim post-signature change visibility.
// Scope fields (materials, colors/finishes) stay editable after sign-off
// on purpose (SCOPE §2.6 — no lock without a Change Order path), but any
// edit made after sign_off_at now gets stamped into work_order_activity
// and surfaced here, same "— edited since" pattern as the estimate
// document's presented-total note.
export function SignOffPanel({
  orgId,
  workOrder,
  activity,
  authorName,
}: {
  orgId: string;
  workOrder: WorkOrder;
  activity: WorkOrderActivity[];
  authorName: (userId: string | null) => string;
}) {
  if (workOrder.sign_off_at) {
    return (
      <div className="rounded-lg border border-border bg-surface p-3">
        <p className="text-sm font-medium text-text">
          Homeowner sign-off complete — {formatDate(workOrder.sign_off_at)}
          {activity.length > 0 && " — changed after sign-off"}
        </p>
        {workOrder.sign_off_notes && (
          <p className="mt-1 text-sm text-muted">{workOrder.sign_off_notes}</p>
        )}
        {activity.length > 0 && (
          <div className="mt-2 flex flex-col gap-1 border-t border-border pt-2">
            {activity.map((entry) => (
              <p key={entry.id} className="text-xs text-text">
                {formatWorkOrderActivityLine(
                  { action: entry.action, from_value: entry.from_value, to_value: entry.to_value },
                  entry.actor_id ? authorName(entry.actor_id) : null
                )}
                <span className="text-muted"> · {formatDate(entry.created_at)}</span>
              </p>
            ))}
          </div>
        )}

        {/* Notes are still editable post-signoff (§2.6 — no lock without a
            Change Order path), gated behind an explicit disclosure since
            this is now established/approved data, not something being
            gathered (same distinction as Task A). record_work_order_sign_off
            preserves the original sign_off_at on this second call — only
            the notes change, and it's what gets logged above. */}
        <details className="mt-2 border-t border-border pt-2 text-xs">
          <summary className="cursor-pointer select-none font-medium text-accent-strong">
            Edit notes →
          </summary>
          <form action={recordWorkOrderSignOff} className="mt-2 flex flex-col gap-2">
            <input type="hidden" name="orgId" value={orgId} />
            <input type="hidden" name="workOrderId" value={workOrder.id} />
            <textarea
              name="notes"
              defaultValue={workOrder.sign_off_notes ?? ""}
              placeholder="Notes (colors, finishes, special requests)…"
              rows={2}
              className="rounded-md border border-border bg-bg px-2 py-2 text-sm text-text outline-none focus:border-accent"
            />
            <button
              type="submit"
              className="self-end rounded-md bg-accent-strong px-3 py-1.5 text-xs font-medium text-white"
            >
              Save
            </button>
          </form>
        </details>
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
