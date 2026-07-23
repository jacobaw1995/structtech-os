import { requireModuleAccess } from "@/lib/workspace/context";
import {
  createRoadmapItem,
  updateRoadmapItemStatus,
  updateRoadmapItemPhase,
  updateRoadmapItemDetails,
  deleteRoadmapItem,
} from "@/lib/build/actions";
import { ROADMAP_PHASES, ROADMAP_STATUSES } from "@/lib/build/config";
import { formatDate } from "@/lib/tracker/config";
import { InlineFieldSelect } from "@/components/build/InlineFieldSelect";
import { InlineNotesInput } from "@/components/build/InlineNotesInput";
import type { Database } from "@/lib/supabase/database.types";

type RoadmapItem = Database["public"]["Tables"]["roadmap_items"]["Row"];

// StructTech-internal Build Tracker — the in-app source of truth that
// supersedes docs/ROADMAP_MATRIX.html + docs/ROLLOUT_CHECKLIST.md (CLAUDE.md
// "NEW — build FIRST", 7/24). Grouped table by section, form == the matrix:
// every row is phase/status/notes editable inline, full CRUD (§2.6).
export default async function BuildTrackerPage({
  params,
  searchParams,
}: {
  params: { orgId: string };
  searchParams: { new?: string; edit?: string; error?: string };
}) {
  const ctx = await requireModuleAccess(params.orgId, "build");
  const supabase = ctx.supabase;

  const [{ data: items }, { data: memberRows }] = await Promise.all([
    supabase
      .from("roadmap_items")
      .select("*")
      .eq("org_id", params.orgId)
      .order("sort_order", { ascending: true }),
    supabase.rpc("list_org_members", { p_org_id: params.orgId }),
  ]);

  const memberNames = new Map(
    (memberRows ?? []).map((m) => [m.user_id, m.full_name ?? "—"])
  );

  const itemList = (items ?? []) as RoadmapItem[];

  // Grouped by section text (not by sort_order contiguity) — a newly added
  // item lands at the bottom of the org's global sort_order, but should
  // still join its existing section's group wherever that group first
  // appears, not start a duplicate group at the end.
  const bySection = new Map<string, RoadmapItem[]>();
  for (const item of itemList) {
    const bucket = bySection.get(item.section) ?? [];
    bucket.push(item);
    bySection.set(item.section, bucket);
  }

  const isAdding = searchParams.new === "1";
  const editingId = searchParams.edit;
  const existingSections = Array.from(bySection.keys());
  const basePath = `/w/${params.orgId}/build`;

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-text">Build Tracker</h1>
          <p className="text-sm text-muted">
            {ctx.active.org_name} · {itemList.length} items
          </p>
        </div>
        <a
          href={isAdding ? basePath : `${basePath}?new=1`}
          className="rounded-md bg-accent-strong px-3 py-1.5 text-sm font-medium text-white"
        >
          {isAdding ? "Cancel" : "+ New item"}
        </a>
      </div>

      {searchParams.error && (
        <p className="rounded-md bg-warn-soft px-3 py-2 text-xs text-text">
          {searchParams.error}
        </p>
      )}

      {isAdding && (
        <form
          action={createRoadmapItem}
          className="flex flex-col gap-3 rounded-lg border border-border bg-surface p-4"
        >
          <input type="hidden" name="orgId" value={params.orgId} />
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <label className="flex flex-col gap-1 text-sm">
              <span className="text-muted">Section</span>
              <input
                name="section"
                required
                autoFocus
                list="build-sections"
                className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
              />
              <datalist id="build-sections">
                {existingSections.map((s) => (
                  <option key={s} value={s} />
                ))}
              </datalist>
            </label>
            <label className="flex flex-col gap-1 text-sm">
              <span className="text-muted">Feature</span>
              <input
                name="feature"
                required
                className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
              />
            </label>
            <label className="flex flex-col gap-1 text-sm">
              <span className="text-muted">Phase</span>
              <select
                name="phase"
                defaultValue="later"
                className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
              >
                {ROADMAP_PHASES.map((p) => (
                  <option key={p.key} value={p.key}>
                    {p.label}
                  </option>
                ))}
              </select>
            </label>
            <label className="flex flex-col gap-1 text-sm">
              <span className="text-muted">Status</span>
              <select
                name="status"
                defaultValue="planned"
                className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
              >
                {ROADMAP_STATUSES.map((s) => (
                  <option key={s.key} value={s.key}>
                    {s.label}
                  </option>
                ))}
              </select>
            </label>
          </div>
          <label className="flex flex-col gap-1 text-sm">
            <span className="text-muted">Notes (optional)</span>
            <input
              name="notes"
              className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
            />
          </label>
          <button
            type="submit"
            className="self-start rounded-md bg-accent-strong px-3 py-1.5 text-sm font-medium text-white"
          >
            Add item
          </button>
        </form>
      )}

      {itemList.length === 0 ? (
        <p className="text-sm text-muted">No roadmap items yet — add the first one.</p>
      ) : (
        <div className="flex flex-col gap-6">
          {Array.from(bySection.entries()).map(([section, rows]) => (
            <div key={section} className="flex flex-col gap-1">
              <h2 className="px-1 text-xs font-semibold uppercase tracking-wide text-muted">
                {section}
              </h2>
              <div className="overflow-x-auto rounded-lg border border-border bg-surface">
                <table className="w-full min-w-[720px] text-left text-sm">
                  <thead>
                    <tr className="border-b border-border text-xs text-muted">
                      <th className="px-3 py-2 font-medium">Feature</th>
                      <th className="px-3 py-2 font-medium">Phase</th>
                      <th className="px-3 py-2 font-medium">Status</th>
                      <th className="px-3 py-2 font-medium">Notes</th>
                      <th className="px-3 py-2 font-medium">Last changed</th>
                      <th className="px-3 py-2 font-medium" />
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((item) => {
                      const isEditing = editingId === item.id;
                      const changedBy = item.updated_by
                        ? memberNames.get(item.updated_by) ?? "—"
                        : "—";
                      return (
                        <tr key={item.id} className="border-b border-border last:border-0">
                          <td className="px-3 py-2 align-top">
                            {isEditing ? (
                              <form
                                action={updateRoadmapItemDetails}
                                className="flex flex-col gap-1"
                              >
                                <input type="hidden" name="orgId" value={params.orgId} />
                                <input type="hidden" name="itemId" value={item.id} />
                                <input
                                  name="section"
                                  defaultValue={item.section}
                                  required
                                  className="rounded-md border border-border bg-bg px-2 py-1 text-xs text-text outline-none focus:border-accent"
                                />
                                <input
                                  name="feature"
                                  defaultValue={item.feature}
                                  required
                                  autoFocus
                                  className="rounded-md border border-border bg-bg px-2 py-1 text-text outline-none focus:border-accent"
                                />
                                <div className="flex gap-2">
                                  <button
                                    type="submit"
                                    className="rounded-md bg-accent-strong px-2 py-1 text-xs font-medium text-white"
                                  >
                                    Save
                                  </button>
                                  <a
                                    href={basePath}
                                    className="rounded-md border border-border px-2 py-1 text-xs text-text"
                                  >
                                    Cancel
                                  </a>
                                </div>
                              </form>
                            ) : (
                              <div className="flex flex-col gap-0.5">
                                <span className="text-text">{item.feature}</span>
                                <a
                                  href={`${basePath}?edit=${item.id}`}
                                  className="w-fit text-xs text-accent-strong hover:underline"
                                >
                                  Edit
                                </a>
                              </div>
                            )}
                          </td>
                          <td className="px-3 py-2 align-top">
                            <InlineFieldSelect
                              action={updateRoadmapItemPhase}
                              orgId={params.orgId}
                              itemId={item.id}
                              fieldName="phase"
                              value={item.phase}
                              options={ROADMAP_PHASES}
                            />
                          </td>
                          <td className="px-3 py-2 align-top">
                            <InlineFieldSelect
                              action={updateRoadmapItemStatus}
                              orgId={params.orgId}
                              itemId={item.id}
                              fieldName="status"
                              value={item.status}
                              options={ROADMAP_STATUSES}
                            />
                          </td>
                          <td className="px-3 py-2 align-top">
                            <InlineNotesInput
                              orgId={params.orgId}
                              itemId={item.id}
                              value={item.notes ?? ""}
                            />
                          </td>
                          <td className="px-3 py-2 align-top font-mono text-xs text-muted">
                            {changedBy} · {formatDate(item.updated_at)}
                          </td>
                          <td className="px-3 py-2 align-top">
                            <form action={deleteRoadmapItem}>
                              <input type="hidden" name="orgId" value={params.orgId} />
                              <input type="hidden" name="itemId" value={item.id} />
                              <button
                                type="submit"
                                className="text-xs text-muted hover:text-warn"
                              >
                                Delete
                              </button>
                            </form>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
