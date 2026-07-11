import { requireModuleAccess } from "@/lib/workspace/context";
import { moduleLabel } from "@/lib/workspace/modules";

// One dynamic route for all 7 modules rather than 7 near-identical folders.
// Weeks 2-3 add real per-module route trees (e.g. crm/[dealId]/page.tsx) —
// Next resolves those more-specific static segments ahead of this dynamic
// one, so this placeholder needs no migration when that lands.
export default async function ModulePlaceholderPage({
  params,
}: {
  params: { orgId: string; moduleKey: string };
}) {
  const ctx = await requireModuleAccess(params.orgId, params.moduleKey);

  return (
    <div className="flex flex-col gap-2">
      <span className="w-fit rounded-full bg-accent-soft px-3 py-1 font-mono text-xs uppercase tracking-wide text-accent-strong">
        Coming in Weeks 2–3
      </span>
      <h1 className="text-2xl font-semibold text-text">
        {moduleLabel(ctx.moduleKey, ctx.active.tenant_type)}
      </h1>
      <p className="text-sm text-muted">
        {ctx.active.org_name} · role: {ctx.active.role}
      </p>
    </div>
  );
}
