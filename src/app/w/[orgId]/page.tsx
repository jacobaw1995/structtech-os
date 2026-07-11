import Link from "next/link";
import { getWorkspaceContext } from "@/lib/workspace/context";
import { moduleLabel } from "@/lib/workspace/modules";

export default async function WorkspaceHomePage({
  params,
}: {
  params: { orgId: string };
}) {
  const ctx = await getWorkspaceContext(params.orgId);

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-2xl font-semibold text-text">
          {ctx.active.org_name}
        </h1>
        <p className="text-sm text-muted">
          {ctx.active.tenant_type} workspace · role: {ctx.active.role}
        </p>
      </div>

      {ctx.visibleModules.length > 0 ? (
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
          {ctx.visibleModules.map((moduleKey) => (
            <Link
              key={moduleKey}
              href={`/w/${params.orgId}/${moduleKey}`}
              className="rounded-lg border border-border bg-surface px-4 py-3 text-sm font-medium text-text transition-colors hover:border-accent"
            >
              {moduleLabel(moduleKey, ctx.active.tenant_type)}
            </Link>
          ))}
        </div>
      ) : (
        <p className="text-sm text-muted">
          No modules visible for your role yet.
        </p>
      )}
    </div>
  );
}
