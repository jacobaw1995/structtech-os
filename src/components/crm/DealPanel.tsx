import Link from "next/link";
import { StageSelect } from "@/components/crm/StageSelect";
import { addDealNote } from "@/lib/crm/actions";
import { createEstimateFromDeal } from "@/lib/estimating/actions";
import { estimateStatusLabel, estimateStatusClasses } from "@/lib/estimating/status";
import { formatMoney, formatDate, daysBetween, type CrmStage } from "@/lib/crm/stages";
import type { Database } from "@/lib/supabase/database.types";

type Deal = Database["public"]["Tables"]["deals"]["Row"];
type DealNote = Database["public"]["Tables"]["deal_notes"]["Row"];
type DealActivity = Database["public"]["Tables"]["deal_activity"]["Row"];
type FollowUp = Database["public"]["Tables"]["follow_ups"]["Row"];
type Estimate = Database["public"]["Tables"]["estimates"]["Row"];

function activityLabel(entry: DealActivity): string {
  switch (entry.action) {
    case "stage_changed":
      return `Stage: ${entry.from_value ?? "—"} → ${entry.to_value ?? "—"}`;
    case "created":
      return `Created (${entry.to_value ?? "—"})`;
    case "note_added":
      return `Note added`;
    case "followup_scheduled":
      return `Follow-up scheduled (${entry.to_value ?? "—"})`;
    case "engagement_materialize_failed":
      return `Engagement creation failed`;
    default:
      return entry.action;
  }
}

export function DealPanel({
  orgId,
  deal,
  stages,
  notes,
  activity,
  nextFollowUp,
  closeHref,
  errorMessage,
  estimates,
  canCreateEstimate,
}: {
  orgId: string;
  deal: Deal;
  stages: CrmStage[];
  notes: DealNote[];
  activity: DealActivity[];
  nextFollowUp: FollowUp | null;
  closeHref: string;
  errorMessage?: string;
  estimates: Estimate[];
  canCreateEstimate: boolean;
}) {
  const nextActionText =
    stages.find((s) => s.key === deal.stage)?.next_action ?? null;

  return (
    // Wireframe §7: "tap a deal for the detail view" — a distinct screen on
    // mobile, not a docked side panel squeezed next to a now-single-column
    // board. fixed inset-0 makes it a full-screen takeover there; the sm:
    // overrides restore the original in-flow side panel unchanged.
    <aside className="fixed inset-0 z-40 flex flex-col gap-4 overflow-y-auto bg-surface p-4 sm:static sm:z-auto sm:w-80 sm:shrink-0 sm:rounded-lg sm:border sm:border-border">
      <div className="flex items-start justify-between gap-2">
        <div>
          <h2 className="text-base font-semibold text-text">
            {deal.company || deal.contact_name}
          </h2>
          {deal.company && (
            <p className="text-xs text-muted">{deal.contact_name}</p>
          )}
        </div>
        <Link
          href={closeHref}
          aria-label="Close"
          className="-mr-2 -mt-2 flex h-11 w-11 shrink-0 items-center justify-center text-lg text-muted hover:text-text sm:m-0 sm:h-auto sm:w-auto sm:text-sm"
        >
          ✕
        </Link>
      </div>

      {errorMessage && (
        <p className="rounded-md bg-warn-soft px-3 py-2 text-xs text-text">
          {errorMessage}
        </p>
      )}

      <div className="flex flex-col gap-2 text-sm">
        <div className="flex items-center justify-between">
          <span className="text-muted">Stage</span>
          <StageSelect
            orgId={orgId}
            dealId={deal.id}
            currentStage={deal.stage}
            stages={stages}
          />
        </div>
        <div className="flex items-center justify-between">
          <span className="text-muted">Value</span>
          <span className="font-mono text-text">{formatMoney(deal.value)}</span>
        </div>
        {nextActionText && (
          <div className="flex items-center justify-between">
            <span className="text-muted">Next action</span>
            <span className="w-fit rounded-full bg-accent-soft px-2 py-0.5 text-xs text-accent-strong">
              {nextActionText}
            </span>
          </div>
        )}
        <div className="flex items-center justify-between">
          <span className="text-muted">Auto follow-up</span>
          <span className="text-text">
            {nextFollowUp
              ? `${formatDate(nextFollowUp.send_at)} (day ${daysBetween(
                  deal.created_at,
                  nextFollowUp.send_at
                )})`
              : "none pending"}
          </span>
        </div>
      </div>

      {canCreateEstimate && (
        <div className="flex flex-col gap-2">
          <h3 className="text-xs font-semibold uppercase tracking-wide text-muted">
            Estimates
          </h3>
          <div className="flex flex-col gap-1.5">
            {estimates.length === 0 && (
              <p className="text-xs text-muted">No estimates yet.</p>
            )}
            {estimates.map((estimate) => (
              <Link
                key={estimate.id}
                href={`/w/${orgId}/estimating/${estimate.id}`}
                className="flex items-center justify-between rounded-md bg-surface2 px-3 py-2 text-sm text-text hover:bg-accent-soft"
              >
                <span className="font-mono">
                  {formatMoney(estimate.presented_total ?? estimate.subtotal)}
                </span>
                <span
                  className={`rounded-full px-2 py-0.5 text-xs font-medium ${estimateStatusClasses(
                    estimate.status
                  )}`}
                >
                  {estimateStatusLabel(estimate.status)}
                </span>
              </Link>
            ))}
          </div>
          <form action={createEstimateFromDeal}>
            <input type="hidden" name="orgId" value={orgId} />
            <input type="hidden" name="dealId" value={deal.id} />
            <button
              type="submit"
              className="w-full rounded-md border border-accent-strong px-3 py-1.5 text-xs font-medium text-accent-strong hover:bg-accent-soft"
            >
              + Create estimate
            </button>
          </form>
        </div>
      )}

      <div className="flex flex-col gap-2">
        <h3 className="text-xs font-semibold uppercase tracking-wide text-muted">
          Notes
        </h3>
        <form action={addDealNote} className="flex flex-col gap-2">
          <input type="hidden" name="orgId" value={orgId} />
          <input type="hidden" name="dealId" value={deal.id} />
          <textarea
            name="content"
            required
            rows={2}
            placeholder="Add a note…"
            className="rounded-md border border-border bg-bg px-2 py-1.5 text-sm text-text outline-none focus:border-accent"
          />
          <button
            type="submit"
            className="self-end rounded-md bg-accent-strong px-3 py-1 text-xs font-medium text-white"
          >
            Add note
          </button>
        </form>
        <div className="flex flex-col gap-2">
          {notes.length === 0 && (
            <p className="text-xs text-muted">No notes yet.</p>
          )}
          {notes.map((note) => (
            <div
              key={note.id}
              className="rounded-md bg-surface2 px-3 py-2 text-sm text-text"
            >
              <p>{note.content}</p>
              <p className="mt-1 text-xs text-muted">
                {formatDate(note.created_at)}
              </p>
            </div>
          ))}
        </div>
      </div>

      <div className="flex flex-col gap-2">
        <h3 className="text-xs font-semibold uppercase tracking-wide text-muted">
          Activity
        </h3>
        <div className="flex flex-col gap-1.5">
          {activity.length === 0 && (
            <p className="text-xs text-muted">No activity yet.</p>
          )}
          {activity.map((entry) => (
            <div key={entry.id} className="text-xs">
              <span className="text-text">{activityLabel(entry)}</span>
              <span className="text-muted"> · {formatDate(entry.created_at)}</span>
            </div>
          ))}
        </div>
      </div>
    </aside>
  );
}
