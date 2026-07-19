import { formatActivityLine, formatDate } from "@/lib/crm/stages";
import { AddNoteForm } from "./AddNoteForm";
import type { Database } from "@/lib/supabase/database.types";

type DealNote = Database["public"]["Tables"]["deal_notes"]["Row"];
type DealActivity = Database["public"]["Tables"]["deal_activity"]["Row"];

type FeedEntry =
  | { kind: "note"; id: string; created_at: string; content: string; authorName: string }
  | { kind: "activity"; id: string; created_at: string; label: string };

// Mobile only — spec: "Log Activity = notes + activity combined." Same
// #lead-notes anchor id as LeadNotesPanel (desktop); sm:hidden here keeps
// only one in the DOM at a given breakpoint.
export function MobileLogActivity({
  orgId,
  dealId,
  notes,
  activity,
  authorName,
}: {
  orgId: string;
  dealId: string;
  notes: DealNote[];
  activity: DealActivity[];
  authorName: (userId: string | null) => string;
}) {
  const feed: FeedEntry[] = [
    ...notes.map((n): FeedEntry => ({ kind: "note", id: n.id, created_at: n.created_at, content: n.content, authorName: authorName(n.created_by) })),
    ...activity.map((a): FeedEntry => ({
      kind: "activity",
      id: a.id,
      created_at: a.created_at,
      label: formatActivityLine(a, a.actor_id ? authorName(a.actor_id) : null),
    })),
  ].sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());

  return (
    <section id="lead-notes" className="flex flex-col gap-3 rounded-lg border border-border bg-surface p-4 sm:hidden">
      <h3 className="text-xs font-semibold uppercase tracking-wide text-muted">Log Activity</h3>
      <AddNoteForm orgId={orgId} dealId={dealId} />
      <div className="flex flex-col gap-2">
        {feed.length === 0 && <p className="text-xs text-muted">Nothing logged yet.</p>}
        {feed.map((entry) =>
          entry.kind === "note" ? (
            <div key={`note-${entry.id}`} className="rounded-md bg-surface2 px-3 py-2 text-sm text-text">
              <p>{entry.content}</p>
              <p className="mt-1 text-xs text-muted">
                {entry.authorName} · {formatDate(entry.created_at)}
              </p>
            </div>
          ) : (
            <div key={`activity-${entry.id}`} className="text-xs">
              <span className="text-text">{entry.label}</span>
              <span className="text-muted"> · {formatDate(entry.created_at)}</span>
            </div>
          )
        )}
      </div>
    </section>
  );
}
