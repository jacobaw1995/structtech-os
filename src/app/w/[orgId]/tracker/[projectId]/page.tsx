import Link from "next/link";
import { requireModuleAccess } from "@/lib/workspace/context";
import { parseTrackerStatuses, parseTrackerTypes } from "@/lib/tracker/config";
import { QuickAddItemForm } from "@/components/tracker/QuickAddItemForm";
import { ItemCard } from "@/components/tracker/ItemCard";
import { MobileTrackerBoard } from "@/components/tracker/MobileTrackerBoard";
import { ItemDetailPanel } from "@/components/tracker/ItemDetailPanel";
import { updateTrackerProject, deleteTrackerProject } from "@/lib/tracker/actions";
import type { Database } from "@/lib/supabase/database.types";

type TrackerItem = Database["public"]["Tables"]["tracker_items"]["Row"];

export default async function TrackerProjectPage({
  params,
  searchParams,
}: {
  params: { orgId: string; projectId: string };
  searchParams: { item?: string; error?: string; edit?: string };
}) {
  const ctx = await requireModuleAccess(params.orgId, "tracker");
  const supabase = ctx.supabase;

  const [{ data: moduleRow }, { data: projectRows }, { data: items }, { data: memberRows }] =
    await Promise.all([
      supabase
        .from("tenant_modules")
        .select("config")
        .eq("org_id", params.orgId)
        .eq("module_key", "tracker"),
      // Single-record fetch RPC (rule 4), not a direct .select().single().
      supabase.rpc("fetch_tracker_project", { p_project_id: params.projectId }),
      supabase
        .from("tracker_items")
        .select("*")
        .eq("org_id", params.orgId)
        .eq("project_id", params.projectId)
        .is("archived_at", null)
        .order("created_at", { ascending: true }),
      supabase.rpc("list_org_members", { p_org_id: params.orgId }),
    ]);

  const project = projectRows?.[0];
  if (!project || project.org_id !== params.orgId) {
    return (
      <div className="flex flex-col gap-2">
        <Link href={`/w/${params.orgId}/tracker`} className="text-sm text-accent-strong hover:underline">
          ← Back to Tracker
        </Link>
        <p className="text-sm text-muted">Project not found.</p>
      </div>
    );
  }

  const rawConfig = moduleRow?.[0]?.config ?? null;
  const statuses = parseTrackerStatuses(rawConfig);
  const types = parseTrackerTypes(rawConfig);
  const members = memberRows ?? [];
  const memberNames = new Map(members.map((m) => [m.user_id, m.full_name ?? m.user_id]));
  const typeLabels = new Map(types.map((t) => [t.key, t.label]));

  const itemList = (items ?? []) as TrackerItem[];
  const byStatus = new Map<string, TrackerItem[]>();
  for (const s of statuses) byStatus.set(s.key, []);
  const unrecognized: TrackerItem[] = [];
  for (const item of itemList) {
    const bucket = byStatus.get(item.status);
    if (bucket) bucket.push(item);
    else unrecognized.push(item);
  }

  const mobileStatuses =
    unrecognized.length > 0
      ? [...statuses, { key: "__unrecognized__", label: "Unrecognized", terminal: false }]
      : statuses;
  const mobileItemsByStatus =
    unrecognized.length > 0 ? new Map(byStatus).set("__unrecognized__", unrecognized) : byStatus;
  const mobileStatusesWithCounts = mobileStatuses.map((s) => ({
    ...s,
    count: (mobileItemsByStatus.get(s.key) ?? []).length,
  }));

  const boardHref = `/w/${params.orgId}/tracker/${params.projectId}`;

  // Selected item can be archived (restore lives in the panel) — fetched
  // via a dedicated RPC that doesn't filter archived_at, unlike the board
  // query above which only shows active items as columns.
  let selectedItem: TrackerItem | null = null;
  if (searchParams.item) {
    const { data: fetched } = await supabase.rpc("fetch_tracker_item", {
      p_item_id: searchParams.item,
    });
    const candidate = fetched?.[0] as TrackerItem | undefined;
    if (candidate && candidate.org_id === params.orgId && candidate.project_id === params.projectId) {
      selectedItem = candidate;
    }
  }

  const isEditing = searchParams.edit === "1";

  return (
    <div className="flex h-full flex-col gap-4">
      <div className="flex items-start justify-between gap-2">
        <div className="flex flex-col gap-1">
          <Link href={`/w/${params.orgId}/tracker`} className="text-xs text-muted hover:text-text">
            ← Tracker
          </Link>
          {isEditing ? (
            <form action={updateTrackerProject} className="flex flex-col gap-2">
              <input type="hidden" name="orgId" value={params.orgId} />
              <input type="hidden" name="projectId" value={project.id} />
              <input
                name="name"
                defaultValue={project.name}
                required
                className="rounded-md border border-border bg-bg px-2 py-1 text-lg font-semibold text-text outline-none focus:border-accent"
              />
              <input
                name="description"
                defaultValue={project.description ?? ""}
                placeholder="Description"
                className="rounded-md border border-border bg-bg px-2 py-1 text-sm text-text outline-none focus:border-accent"
              />
              <div className="flex gap-2">
                <button type="submit" className="rounded-md bg-accent-strong px-3 py-1 text-xs font-medium text-white">
                  Save
                </button>
                <Link href={boardHref} className="rounded-md border border-border px-3 py-1 text-xs text-text">
                  Cancel
                </Link>
              </div>
            </form>
          ) : (
            <>
              <h1 className="text-2xl font-semibold text-text">{project.name}</h1>
              {project.description && <p className="text-sm text-muted">{project.description}</p>}
            </>
          )}
        </div>
        {!isEditing && (
          <div className="flex shrink-0 items-center gap-2">
            <Link
              href={`${boardHref}?edit=1`}
              className="rounded-md border border-border px-3 py-1.5 text-xs text-text hover:bg-surface2"
            >
              Edit
            </Link>
            <form action={deleteTrackerProject}>
              <input type="hidden" name="orgId" value={params.orgId} />
              <input type="hidden" name="projectId" value={project.id} />
              <button type="submit" className="rounded-md border border-border px-3 py-1.5 text-xs text-warn hover:bg-warn-soft">
                Delete
              </button>
            </form>
          </div>
        )}
      </div>

      {searchParams.error && !selectedItem && (
        <p className="rounded-md bg-warn-soft px-3 py-2 text-xs text-text">{searchParams.error}</p>
      )}

      <QuickAddItemForm orgId={params.orgId} projectId={project.id} types={types} />

      {statuses.length === 0 ? (
        <p className="text-sm text-muted">
          {ctx.active.org_name} has no tracker status configuration yet — nothing to show.
        </p>
      ) : (
        <div className="flex flex-1 gap-4 overflow-hidden">
          <div className="flex flex-1 overflow-hidden sm:hidden">
            <MobileTrackerBoard
              statuses={mobileStatusesWithCounts}
              itemsByStatus={mobileItemsByStatus}
              boardHref={boardHref}
              selectedItem={selectedItem}
              typeLabels={typeLabels}
              assigneeNames={memberNames}
            />
          </div>

          <div className="hidden flex-1 gap-4 overflow-hidden sm:flex">
            <div className="flex flex-1 min-w-0 gap-4 overflow-x-auto pb-2">
              {statuses.map((status) => {
                const statusItems = byStatus.get(status.key) ?? [];
                return (
                  <div key={status.key} className="flex w-64 shrink-0 flex-col gap-2">
                    <div className="flex items-center justify-between px-1">
                      <h2 className="text-sm font-semibold text-text">{status.label}</h2>
                      <span className="font-mono text-xs text-muted">{statusItems.length}</span>
                    </div>
                    <div className="flex flex-col gap-2">
                      {statusItems.map((item) => (
                        <ItemCard
                          key={item.id}
                          item={item}
                          href={`${boardHref}?item=${item.id}`}
                          selected={selectedItem?.id === item.id}
                          typeLabel={typeLabels.get(item.type) ?? item.type}
                          assigneeName={item.assignee_id ? memberNames.get(item.assignee_id) ?? null : null}
                        />
                      ))}
                      {statusItems.length === 0 && (
                        <div className="rounded-md border border-dashed border-border px-3 py-4 text-center text-xs text-muted">
                          Empty
                        </div>
                      )}
                    </div>
                  </div>
                );
              })}

              {unrecognized.length > 0 && (
                <div className="flex w-64 shrink-0 flex-col gap-2">
                  <h2 className="text-sm font-semibold text-warn">Unrecognized status</h2>
                  <div className="flex flex-col gap-2">
                    {unrecognized.map((item) => (
                      <ItemCard
                        key={item.id}
                        item={item}
                        href={`${boardHref}?item=${item.id}`}
                        selected={selectedItem?.id === item.id}
                        typeLabel={typeLabels.get(item.type) ?? item.type}
                        assigneeName={item.assignee_id ? memberNames.get(item.assignee_id) ?? null : null}
                      />
                    ))}
                  </div>
                </div>
              )}
            </div>
          </div>

          {selectedItem && (
            <ItemDetailPanel
              orgId={params.orgId}
              item={selectedItem}
              statuses={statuses}
              types={types}
              members={members}
              closeHref={boardHref}
              returnTo={boardHref}
              errorMessage={searchParams.error}
            />
          )}
        </div>
      )}
    </div>
  );
}
