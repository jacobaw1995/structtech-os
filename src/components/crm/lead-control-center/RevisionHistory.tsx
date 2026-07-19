import { formatActivityLine, formatDate } from "@/lib/crm/stages";
import type { Database } from "@/lib/supabase/database.types";

type DealActivity = Database["public"]["Tables"]["deal_activity"]["Row"];

// Desktop/iPad only (spec) — merges into MobileLogActivity on mobile
// instead of rendering twice.
export function RevisionHistory({
  activity,
  authorName,
}: {
  activity: DealActivity[];
  authorName: (userId: string | null) => string;
}) {
  return (
    <div className="hidden flex-col gap-2 sm:flex">
      <h3 className="text-xs font-semibold uppercase tracking-wide text-muted">Revision History</h3>
      <div className="flex flex-col gap-1.5">
        {activity.length === 0 && <p className="text-xs text-muted">No activity yet.</p>}
        {activity.map((entry) => (
          <div key={entry.id} className="text-xs">
            {/* actor_id null (legacy rows predating Track C2, or a system
                write) falls back to just the event — no "Unknown" noise. */}
            <span className="text-text">
              {formatActivityLine(entry, entry.actor_id ? authorName(entry.actor_id) : null)}
            </span>
            <span className="text-muted"> · {formatDate(entry.created_at)}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
