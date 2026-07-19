import Link from "next/link";
import { StatusSelect } from "@/components/tracker/StatusSelect";
import { AssigneeSelect } from "@/components/tracker/AssigneeSelect";
import {
  updateTrackerItemDetails,
  archiveTrackerItem,
  restoreTrackerItem,
  deleteTrackerItem,
} from "@/lib/tracker/actions";
import type { TrackerStatus, TrackerType } from "@/lib/tracker/config";
import { formatDate } from "@/lib/tracker/config";
import type { Database } from "@/lib/supabase/database.types";

type TrackerItem = Database["public"]["Tables"]["tracker_items"]["Row"];

// Full-edit side panel — mirrors the mobile-fullscreen/desktop-sidebar
// pattern crm/page.tsx uses for the Lead Control Center, scaled down: no
// stage tabs/checklist, just every field editable + archive/delete (§2.6).
export function ItemDetailPanel({
  orgId,
  item,
  statuses,
  types,
  members,
  closeHref,
  returnTo,
  errorMessage,
}: {
  orgId: string;
  item: TrackerItem;
  statuses: TrackerStatus[];
  types: TrackerType[];
  members: { user_id: string; full_name: string | null }[];
  closeHref: string;
  returnTo: string;
  errorMessage?: string;
}) {
  return (
    <aside className="fixed inset-0 z-40 flex flex-col gap-4 overflow-y-auto bg-surface p-4 sm:static sm:z-auto sm:w-96 sm:shrink-0 sm:rounded-lg sm:border sm:border-border">
      <div className="flex items-start justify-between gap-2">
        <h2 className="text-base font-semibold text-text">{item.title}</h2>
        <Link href={closeHref} aria-label="Close" className="text-lg text-muted hover:text-text">
          ✕
        </Link>
      </div>

      {errorMessage && (
        <p className="rounded-md bg-warn-soft px-3 py-2 text-xs text-text">{errorMessage}</p>
      )}

      {item.archived_at && (
        <div className="flex items-center justify-between rounded-md bg-warn-soft px-3 py-2 text-xs text-text">
          <span>Archived {formatDate(item.archived_at)}</span>
          <form action={restoreTrackerItem}>
            <input type="hidden" name="orgId" value={orgId} />
            <input type="hidden" name="itemId" value={item.id} />
            <input type="hidden" name="returnTo" value={returnTo} />
            <button type="submit" className="font-medium text-accent-strong hover:underline">
              Restore
            </button>
          </form>
        </div>
      )}

      <div className="grid grid-cols-2 gap-3">
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-muted">Status</span>
          <StatusSelect
            orgId={orgId}
            itemId={item.id}
            currentStatus={item.status}
            statuses={statuses}
            returnTo={returnTo}
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-muted">Assignee</span>
          <AssigneeSelect
            orgId={orgId}
            itemId={item.id}
            currentAssigneeId={item.assignee_id}
            members={members}
            returnTo={returnTo}
          />
        </label>
      </div>

      <form action={updateTrackerItemDetails} className="flex flex-col gap-3">
        <input type="hidden" name="orgId" value={orgId} />
        <input type="hidden" name="itemId" value={item.id} />
        <input type="hidden" name="returnTo" value={returnTo} />

        <label className="flex flex-col gap-1 text-sm">
          <span className="text-muted">Title</span>
          <input
            name="title"
            defaultValue={item.title}
            required
            className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          <span className="text-muted">Description</span>
          <textarea
            name="description"
            defaultValue={item.description ?? ""}
            rows={4}
            className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
          />
        </label>

        <div className="grid grid-cols-2 gap-3">
          <label className="flex flex-col gap-1 text-sm">
            <span className="text-muted">Type</span>
            <select
              name="type"
              defaultValue={item.type}
              className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
            >
              {types.map((t) => (
                <option key={t.key} value={t.key}>
                  {t.label}
                </option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-sm">
            <span className="text-muted">Priority</span>
            <select
              name="priority"
              defaultValue={item.priority}
              className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
            >
              <option value="low">Low</option>
              <option value="normal">Normal</option>
              <option value="high">High</option>
              <option value="urgent">Urgent</option>
            </select>
          </label>
        </div>

        <button
          type="submit"
          className="self-start rounded-md bg-accent-strong px-3 py-1.5 text-sm font-medium text-white"
        >
          Save changes
        </button>
      </form>

      <div className="flex flex-col gap-1 border-t border-border pt-3 text-xs text-muted">
        <span>Created {formatDate(item.created_at)}</span>
        {item.resolved_at && <span>Resolved {formatDate(item.resolved_at)}</span>}
      </div>

      <div className="mt-auto flex items-center justify-between border-t border-border pt-3">
        {!item.archived_at && (
          <form action={archiveTrackerItem}>
            <input type="hidden" name="orgId" value={orgId} />
            <input type="hidden" name="itemId" value={item.id} />
            <input type="hidden" name="returnTo" value={returnTo} />
            <button type="submit" className="text-xs text-muted hover:text-warn">
              Archive
            </button>
          </form>
        )}
        <form action={deleteTrackerItem}>
          <input type="hidden" name="orgId" value={orgId} />
          <input type="hidden" name="itemId" value={item.id} />
          <input type="hidden" name="projectId" value={item.project_id} />
          <button type="submit" className="text-xs text-warn hover:underline">
            Delete
          </button>
        </form>
      </div>
    </aside>
  );
}
