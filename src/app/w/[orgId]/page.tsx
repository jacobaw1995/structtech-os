import Link from "next/link";
import { redirect } from "next/navigation";
import { getWorkspaceContext } from "@/lib/workspace/context";
import { moduleLabel } from "@/lib/workspace/modules";
import { loadHome } from "@/lib/home/load";
import { HomeSectionCard, HomeSummary } from "@/components/home/HomeSections";

export default async function WorkspaceHomePage({
  params,
}: {
  params: { orgId: string };
}) {
  const ctx = await getWorkspaceContext(params.orgId);

  // U-W1.24 (2026-09-20) — A PERSON WITH ONE MODULE LANDS IN IT.
  //
  // MEASURED BY A HUMAN, not by me: signed in to production as the crew
  // member, this screen rendered a WORKSPACE OVERVIEW — cards headed Schedule,
  // Jobs and "Materials and purchasing" — with the field module behind an
  // "Open Field" button underneath. A roofer opening the app got an office
  // dashboard and one more tap.
  //
  // The comment that used to sit here said a redirect "is what I would
  // recommend, but it removes a route every such user currently lands on, and
  // that is a navigation decision rather than a measurement. Reported, not
  // taken." It has now been taken, by the person whose decision it was, after
  // looking at the screen. Leaving it as a recommendation for another week is
  // what put an office dashboard in front of a crew.
  if (ctx.visibleModules.length === 1) {
    redirect(`/w/${params.orgId}/${ctx.visibleModules[0]}`);
  }

  const home = await loadHome(ctx);

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-2xl font-semibold text-text">
          {ctx.active.org_name}
        </h1>
        <p className="text-sm text-muted">
          {ctx.active.tenant_type} workspace · role: {ctx.active.role} ·{" "}
          <span className="font-mono tabular-nums">{home.today}</span>
        </p>
      </div>

      {/* U-W1.13 — THE HOME SCREEN. What needs this person today, on the page
          they land on. Every gate and every count is in lib/home/load.ts; this
          page only arranges it. The module links stay, below, as navigation. */}
      <HomeSummary data={home} />
      <div className="grid gap-3 lg:grid-cols-2">
        {home.sections.map((s) => (
          <HomeSectionCard key={s.id} section={s} />
        ))}
      </div>

      {/* Navigation for a role that has a CHOICE. The single-module case
          redirected above and never reaches here; the no-module case is a
          membership with nothing granted, which is a state, not an error. */}
      {ctx.visibleModules.length > 1 ? (
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
