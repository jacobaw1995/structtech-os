import Link from "next/link";
import { requireModuleAccess } from "@/lib/workspace/context";
import { createTrackerProject, archiveTrackerProject, restoreTrackerProject } from "@/lib/tracker/actions";
import type { Database } from "@/lib/supabase/database.types";

type TrackerProject = Database["public"]["Tables"]["tracker_projects"]["Row"];

// Project list — the tracker module's landing page. "Fluid: add a project
// at will" (spec) drives the same isAdding-toggle pattern as crm/page.tsx's
// AddDealForm, kept inline here (no dedicated component) since the form is
// two fields.
export default async function TrackerPage({
  params,
  searchParams,
}: {
  params: { orgId: string };
  searchParams: { new?: string; error?: string; archived?: string };
}) {
  const ctx = await requireModuleAccess(params.orgId, "tracker");
  const supabase = ctx.supabase;

  const showArchived = searchParams.archived === "1";

  const [{ data: projects }, { data: openItems }] = await Promise.all([
    supabase
      .from("tracker_projects")
      .select("*")
      .eq("org_id", params.orgId)
      .order("created_at", { ascending: true }),
    supabase
      .from("tracker_items")
      .select("project_id")
      .eq("org_id", params.orgId)
      .is("archived_at", null)
      .is("resolved_at", null),
  ]);

  const openCounts = new Map<string, number>();
  for (const row of openItems ?? []) {
    openCounts.set(row.project_id, (openCounts.get(row.project_id) ?? 0) + 1);
  }

  const allProjects = (projects ?? []) as TrackerProject[];
  const visibleProjects = allProjects.filter((p) =>
    showArchived ? p.status === "archived" : p.status !== "archived"
  );

  const isAdding = searchParams.new === "1";
  const basePath = `/w/${params.orgId}/tracker`;

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-text">Tracker</h1>
          <p className="text-sm text-muted">{ctx.active.org_name}</p>
        </div>
        <div className="flex items-center gap-2">
          <Link
            href={`${basePath}/all`}
            className="rounded-md border border-border px-3 py-1.5 text-sm font-medium text-text hover:bg-surface2"
          >
            All open
          </Link>
          <Link
            href={isAdding ? basePath : `${basePath}?new=1`}
            className="rounded-md bg-accent-strong px-3 py-1.5 text-sm font-medium text-white"
          >
            {isAdding ? "Cancel" : "+ New project"}
          </Link>
        </div>
      </div>

      {isAdding && (
        <form
          action={createTrackerProject}
          className="flex flex-col gap-3 rounded-lg border border-border bg-surface p-4"
        >
          <input type="hidden" name="orgId" value={params.orgId} />
          {searchParams.error && (
            <p className="rounded-md bg-warn-soft px-3 py-2 text-xs text-text">
              {searchParams.error}
            </p>
          )}
          <label className="flex flex-col gap-1 text-sm">
            <span className="text-muted">Project name</span>
            <input
              name="name"
              required
              autoFocus
              className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
            />
          </label>
          <label className="flex flex-col gap-1 text-sm">
            <span className="text-muted">Description (optional)</span>
            <input
              name="description"
              className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
            />
          </label>
          <button
            type="submit"
            className="self-start rounded-md bg-accent-strong px-3 py-1.5 text-sm font-medium text-white"
          >
            Create project
          </button>
        </form>
      )}

      <div className="flex items-center gap-2 text-xs">
        <Link
          href={basePath}
          className={showArchived ? "text-muted hover:text-text" : "font-medium text-accent-strong"}
        >
          Active
        </Link>
        <span className="text-border">·</span>
        <Link
          href={`${basePath}?archived=1`}
          className={showArchived ? "font-medium text-accent-strong" : "text-muted hover:text-text"}
        >
          Archived
        </Link>
      </div>

      {visibleProjects.length === 0 ? (
        <p className="text-sm text-muted">
          {showArchived ? "No archived projects." : "No projects yet — create the first one."}
        </p>
      ) : (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {visibleProjects.map((project) => (
            <div
              key={project.id}
              className="flex flex-col gap-2 rounded-lg border border-border bg-surface p-4"
            >
              <Link href={`${basePath}/${project.id}`} className="flex flex-col gap-1">
                <span className="text-sm font-semibold text-text">{project.name}</span>
                {project.description && (
                  <span className="text-xs text-muted">{project.description}</span>
                )}
              </Link>
              <div className="flex items-center justify-between">
                <span className="font-mono text-xs text-muted">
                  {openCounts.get(project.id) ?? 0} open
                </span>
                {project.status === "archived" ? (
                  <form action={restoreTrackerProject}>
                    <input type="hidden" name="orgId" value={params.orgId} />
                    <input type="hidden" name="projectId" value={project.id} />
                    <button type="submit" className="text-xs text-accent-strong hover:underline">
                      Restore
                    </button>
                  </form>
                ) : (
                  <form action={archiveTrackerProject}>
                    <input type="hidden" name="orgId" value={params.orgId} />
                    <input type="hidden" name="projectId" value={project.id} />
                    <button type="submit" className="text-xs text-muted hover:text-warn">
                      Archive
                    </button>
                  </form>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
