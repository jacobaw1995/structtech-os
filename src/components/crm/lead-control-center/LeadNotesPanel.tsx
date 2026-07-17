import { formatDate } from "@/lib/crm/stages";
import { AddNoteForm } from "./AddNoteForm";
import type { Database } from "@/lib/supabase/database.types";

type DealNote = Database["public"]["Tables"]["deal_notes"]["Row"];

// Desktop/tablet right panel. Same #lead-notes anchor id as
// MobileLogActivity — only one of the two is visible at a given
// breakpoint (hidden sm:flex here, sm:hidden there), so there's still
// exactly one element with that id in the rendered DOM at a time.
export function LeadNotesPanel({
  orgId,
  dealId,
  notes,
  authorName,
}: {
  orgId: string;
  dealId: string;
  notes: DealNote[];
  authorName: (userId: string | null) => string;
}) {
  return (
    <aside
      id="lead-notes"
      className="hidden sm:flex sm:w-72 sm:shrink-0 sm:flex-col sm:gap-3 sm:overflow-y-auto sm:rounded-lg sm:border sm:border-border sm:bg-surface sm:p-4"
    >
      <div>
        <h3 className="text-xs font-semibold uppercase tracking-wide text-muted">Lead Notes</h3>
        <p className="text-xs text-muted">Name and timestamp on every entry.</p>
      </div>
      <AddNoteForm orgId={orgId} dealId={dealId} />
      <div className="flex flex-col gap-2">
        {notes.length === 0 && <p className="text-xs text-muted">No notes yet.</p>}
        {notes.map((note) => (
          <div key={note.id} className="rounded-md bg-surface2 px-3 py-2 text-sm text-text">
            <p>{note.content}</p>
            <p className="mt-1 text-xs text-muted">
              {authorName(note.created_by)} · {formatDate(note.created_at)}
            </p>
          </div>
        ))}
      </div>
    </aside>
  );
}
