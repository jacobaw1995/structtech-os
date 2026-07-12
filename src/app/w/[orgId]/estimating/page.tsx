import Link from "next/link";
import { requireModuleAccess } from "@/lib/workspace/context";
import { formatMoney, formatDate } from "@/lib/crm/stages";
import { estimateStatusLabel, estimateStatusClasses } from "@/lib/estimating/status";
import type { Database } from "@/lib/supabase/database.types";

// More specific than the [moduleKey] placeholder route — see crm/page.tsx's
// comment for why Next resolves this static segment first.

type Estimate = Database["public"]["Tables"]["estimates"]["Row"];

export default async function EstimatingPage({
  params,
}: {
  params: { orgId: string };
}) {
  const ctx = await requireModuleAccess(params.orgId, "estimating");
  const supabase = ctx.supabase;

  // List query — fine direct per CLAUDE.md rule 5; the explicit .eq(org_id)
  // pins this to the active org the same way crm/page.tsx does.
  const { data: estimates } = await supabase
    .from("estimates")
    .select("*")
    .eq("org_id", params.orgId)
    .order("created_at", { ascending: false });

  const estimateList = (estimates ?? []) as Estimate[];

  return (
    <div className="flex h-full flex-col gap-4">
      <div>
        <h1 className="text-2xl font-semibold text-text">Estimating</h1>
        <p className="text-sm text-muted">{ctx.active.org_name}</p>
      </div>

      {estimateList.length === 0 ? (
        <p className="text-sm text-muted">
          No estimates yet — create one from a deal in the pipeline to start
          the on-site flow.
        </p>
      ) : (
        <div className="flex flex-col gap-2">
          {estimateList.map((estimate) => {
            const total = estimate.presented_total ?? estimate.subtotal;
            return (
              <Link
                key={estimate.id}
                href={`/w/${params.orgId}/estimating/${estimate.id}`}
                className="flex items-center justify-between gap-4 rounded-lg border border-border bg-surface px-4 py-3 hover:border-accent"
              >
                <div>
                  <p className="text-sm font-semibold text-text">
                    {estimate.company || estimate.contact_name || "Untitled"}
                  </p>
                  {estimate.site_address && (
                    <p className="text-xs text-muted">{estimate.site_address}</p>
                  )}
                </div>
                <div className="flex items-center gap-4">
                  <span className="font-mono text-sm text-text">
                    {formatMoney(total)}
                  </span>
                  <span
                    className={`rounded-full px-2 py-0.5 text-xs font-medium ${estimateStatusClasses(
                      estimate.status
                    )}`}
                  >
                    {estimateStatusLabel(estimate.status)}
                  </span>
                  <span className="w-16 text-right text-xs text-muted">
                    {formatDate(estimate.created_at)}
                  </span>
                </div>
              </Link>
            );
          })}
        </div>
      )}
    </div>
  );
}
