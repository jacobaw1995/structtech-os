import Link from "next/link";
import { requireModuleAccess } from "@/lib/workspace/context";
import { parseTrackerStatuses, parseTrackerTypes, priorityLabel } from "@/lib/tracker/config";
import { ItemDetailPanel } from "@/components/tracker/ItemDetailPanel";
import type { Database } from "@/lib/supabase/database.types";

type TrackerItem = Database["public"]["Tables"]["tracker_items"]["Row"];
type TrackerProject = Database["public"]["Tables"]["tracker_projects"]["Row"];

// Cross-project "All open" view (spec): everything open across projects,
// filterable by type/priority. "Open" = not archived and not resolved
// (resolved_at null) — an item can sit in a non-terminal status forever
// without being "open" in the filtered sense once someone resolves it
// without moving the status config's terminal entry, so resolved_at (not a
// status-key check) is the source of truth here, matching how the RPC
// layer itself decides resolved_at.
export default async function TrackerAllOpenPage({
  params,
  searchParams,
}: {
  params: { orgId: string };
  searchParams: { type?: string; priority?: string; item?: string; error?: string };
}) {
  const ctx = await requireModuleAccess(params.orgId, "tracker");
  const supabase = ctx.supabase;

  const [{ data: moduleRow }, { data: projects }, { data: items }, { data: memberRows }] =
    await Promise.all([
      supabase
        .from("tenant_modules")
        .select("config")
        .eq("org_id", params.orgId)
        .eq("module_key", "tracker"),
      supabase.from("tracker_projects").select("*").eq("org_id", params.orgId),
      supabase
        .from("tracker_items")
        .select("*")
        .eq("org_id", params.orgId)
        .is("archived_at", null)
        .is("resolved_at", null)
        .order("created_at", { ascending: false }),
      supabase.rpc("list_org_members", { p_org_id: params.orgId }),
    ]);

  const rawConfig = moduleRow?.[0]?.config ?? null;
  const statuses = parseTrackerStatuses(rawConfig);
  const types = parseTrackerTypes(rawConfig);
  const members = memberRows ?? [];
  const typeLabels = new Map(types.map((t) => [t.key, t.label]));
  const projectNames = new Map((projects ?? []).map((p: TrackerProject) => [p.id, p.name]));
  const statusLabels = new Map(statuses.map((s) => [s.key, s.label]));

  const PRIORITY_RANK: Record<string, number> = { urgent: 3, high: 2, normal: 1, low: 0 };

  let filtered = (items ?? []) as TrackerItem[];
  if (searchParams.type) filtered = filtered.filter((i) => i.type === searchParams.type);
  if (searchParams.priority) filtered = filtered.filter((i) => i.priority === searchParams.priority);
  filtered = [...filtered].sort(
    (a, b) => (PRIORITY_RANK[b.priority] ?? 0) - (PRIORITY_RANK[a.priority] ?? 0)
  );

  const basePath = `/w/${params.orgId}/tracker/all`;
  const returnTo = (() => {
    const p = new URLSearchParams();
    if (searchParams.type) p.set("type", searchParams.type);
    if (searchParams.priority) p.set("priority", searchParams.priority);
    const qs = p.toString();
    return qs ? `${basePath}?${qs}` : basePath;
  })();

  function filterHref(key: "type" | "priority", value: string | undefined) {
    const p = new URLSearchParams();
    if (key === "type" && value) p.set("type", value);
    else if (searchParams.type) p.set("type", searchParams.type);
    if (key === "priority" && value) p.set("priority", value);
    else if (searchParams.priority) p.set("priority", searchParams.priority);
    const qs = p.toString();
    return qs ? `${basePath}?${qs}` : basePath;
  }

  let selectedItem: TrackerItem | null = null;
  if (searchParams.item) {
    const { data: fetched } = await supabase.rpc("fetch_tracker_item", {
      p_item_id: searchParams.item,
    });
    const candidate = fetched?.[0] as TrackerItem | undefined;
    if (candidate && candidate.org_id === params.orgId) selectedItem = candidate;
  }

  return (
    <div className="flex h-full flex-col gap-4">
      <div className="flex items-center justify-between">
        <div>
          <Link href={`/w/${params.orgId}/tracker`} className="text-xs text-muted hover:text-text">
            ← Tracker
          </Link>
          <h1 className="text-2xl font-semibold text-text">All open</h1>
        </div>
        <span className="font-mono text-xs text-muted">{filtered.length} open</span>
      </div>

      <div className="flex flex-wrap items-center gap-3">
        <div className="flex flex-wrap gap-1.5">
          <Link
            href={filterHref("type", undefined)}
            className={`rounded-full px-3 py-1 text-xs font-medium ${
              !searchParams.type ? "bg-accent-soft text-accent-strong" : "bg-surface2 text-muted"
            }`}
          >
            All types
          </Link>
          {types.map((t) => (
            <Link
              key={t.key}
              href={filterHref("type", t.key)}
              className={`rounded-full px-3 py-1 text-xs font-medium ${
                searchParams.type === t.key ? "bg-accent-soft text-accent-strong" : "bg-surface2 text-muted"
              }`}
            >
              {t.label}
            </Link>
          ))}
        </div>
        <div className="flex flex-wrap gap-1.5">
          <Link
            href={filterHref("priority", undefined)}
            className={`rounded-full px-3 py-1 text-xs font-medium ${
              !searchParams.priority ? "bg-warn-soft text-warn" : "bg-surface2 text-muted"
            }`}
          >
            All priorities
          </Link>
          {(["urgent", "high", "normal", "low"] as const).map((p) => (
            <Link
              key={p}
              href={filterHref("priority", p)}
              className={`rounded-full px-3 py-1 text-xs font-medium ${
                searchParams.priority === p ? "bg-warn-soft text-warn" : "bg-surface2 text-muted"
              }`}
            >
              {priorityLabel(p)}
            </Link>
          ))}
        </div>
      </div>

      <div className="flex flex-1 gap-4 overflow-hidden">
        <div className="flex flex-1 flex-col gap-2 overflow-y-auto">
          {filtered.length === 0 ? (
            <p className="text-sm text-muted">Nothing open matches these filters.</p>
          ) : (
            filtered.map((item) => (
              <Link
                key={item.id}
                href={`${basePath}?item=${item.id}${searchParams.type ? `&type=${searchParams.type}` : ""}${
                  searchParams.priority ? `&priority=${searchParams.priority}` : ""
                }`}
                className={`flex flex-col gap-1.5 rounded-md border bg-surface p-3 text-left transition-colors hover:border-accent sm:flex-row sm:items-center sm:justify-between ${
                  selectedItem?.id === item.id ? "border-accent ring-1 ring-accent" : "border-border"
                }`}
              >
                <div className="flex flex-col gap-1">
                  <span className="text-sm font-medium text-text">{item.title}</span>
                  <span className="text-xs text-muted">{projectNames.get(item.project_id) ?? "—"}</span>
                </div>
                <div className="flex flex-wrap items-center gap-1.5">
                  <span className="rounded-full bg-accent-soft px-2 py-0.5 text-[11px] text-accent-strong">
                    {typeLabels.get(item.type) ?? item.type}
                  </span>
                  <span className="rounded-full bg-surface2 px-2 py-0.5 text-[11px] text-muted">
                    {statusLabels.get(item.status) ?? item.status}
                  </span>
                  <span
                    className={`rounded-full px-2 py-0.5 text-[11px] ${
                      item.priority === "urgent" || item.priority === "high"
                        ? "bg-warn-soft text-warn"
                        : "bg-surface2 text-muted"
                    }`}
                  >
                    {priorityLabel(item.priority)}
                  </span>
                </div>
              </Link>
            ))
          )}
        </div>

        {selectedItem && (
          <ItemDetailPanel
            orgId={params.orgId}
            item={selectedItem}
            statuses={statuses}
            types={types}
            members={members}
            closeHref={basePath}
            returnTo={returnTo}
            errorMessage={searchParams.error}
          />
        )}
      </div>
    </div>
  );
}
