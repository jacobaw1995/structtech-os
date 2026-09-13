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

      {/* U-W1.10 — measured at 375x812 as a `field` member: this whole screen
          was ONE tile, 46px tall, under §2.4's 56dp floor. A crew member opens
          the app and the only thing on the page is a single small link to the
          only place they are allowed to go.

          Two changes, both from that measurement. Every tile is now a 56dp
          target. And when a role has exactly ONE visible module, it stops
          being a grid — a two-column grid holding one item is a layout
          pretending there is a choice — and becomes one full-width primary
          action that names where it goes.

          NOT a redirect. Skipping this screen entirely for single-module roles
          would be the smaller journey and it is what I would recommend, but it
          removes a route every such user currently lands on, and that is a
          navigation decision rather than a measurement. Reported, not taken. */}
      {ctx.visibleModules.length === 1 ? (
        <Link
          href={`/w/${params.orgId}/${ctx.visibleModules[0]}`}
          className="flex min-h-14 items-center justify-center rounded-lg bg-accent-strong px-4 text-base font-semibold text-white"
        >
          Open {moduleLabel(ctx.visibleModules[0], ctx.active.tenant_type)}
        </Link>
      ) : ctx.visibleModules.length > 1 ? (
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
          {ctx.visibleModules.map((moduleKey) => (
            <Link
              key={moduleKey}
              href={`/w/${params.orgId}/${moduleKey}`}
              className="flex min-h-14 items-center rounded-lg border border-border bg-surface px-4 text-sm font-medium text-text transition-colors hover:border-accent"
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
