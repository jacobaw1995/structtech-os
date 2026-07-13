import Link from "next/link";
import { requireModuleAccess } from "@/lib/workspace/context";
import { createWorkOrderFromEstimate } from "@/lib/coordination/actions";
import { formatDate } from "@/lib/crm/stages";
import type { Database } from "@/lib/supabase/database.types";

// More specific than the [moduleKey] placeholder route — see crm/page.tsx's
// comment for why Next resolves this static segment first.

type WorkOrder = Database["public"]["Tables"]["work_orders"]["Row"] & {
  estimate: Database["public"]["Tables"]["estimates"]["Row"] | null;
};
type Estimate = Database["public"]["Tables"]["estimates"]["Row"];

export default async function CoordinationPage({
  params,
}: {
  params: { orgId: string };
}) {
  const ctx = await requireModuleAccess(params.orgId, "coordination");
  const supabase = ctx.supabase;

  // List queries — fine direct per CLAUDE.md rule 5. The embedded
  // estimate:estimates(*) resolves off the estimate_id FK so the card can
  // show company/site_address without a second round trip per row.
  const [{ data: workOrders }, { data: signedEstimates }] = await Promise.all([
    supabase
      .from("work_orders")
      .select("*, estimate:estimates(*)")
      .eq("org_id", params.orgId)
      .order("created_at", { ascending: false }),
    supabase
      .from("estimates")
      .select("*")
      .eq("org_id", params.orgId)
      .eq("status", "signed")
      .order("signed_at", { ascending: false }),
  ]);

  const workOrderList = (workOrders ?? []) as WorkOrder[];
  const convertedEstimateIds = new Set(workOrderList.map((w) => w.estimate_id));
  const unconvertedSigned = ((signedEstimates ?? []) as Estimate[]).filter(
    (e) => !convertedEstimateIds.has(e.id)
  );

  return (
    <div className="flex h-full flex-col gap-6">
      <div>
        <h1 className="text-2xl font-semibold text-text">Coordination</h1>
        <p className="text-sm text-muted">{ctx.active.org_name}</p>
      </div>

      {unconvertedSigned.length > 0 && (
        <div className="flex flex-col gap-2">
          <h2 className="text-xs font-semibold uppercase tracking-wide text-muted">
            Signed — ready for a work order
          </h2>
          {unconvertedSigned.map((estimate) => (
            <form
              key={estimate.id}
              action={createWorkOrderFromEstimate}
              className="flex items-center justify-between gap-4 rounded-lg border border-border bg-surface px-4 py-3"
            >
              <input type="hidden" name="orgId" value={params.orgId} />
              <input type="hidden" name="estimateId" value={estimate.id} />
              <div>
                <p className="text-sm font-semibold text-text">
                  {estimate.company || estimate.contact_name || "Untitled"}
                </p>
                {estimate.site_address && (
                  <p className="text-xs text-muted">{estimate.site_address}</p>
                )}
              </div>
              <button
                type="submit"
                className="flex min-h-11 items-center justify-center rounded-lg bg-accent-strong px-4 text-sm font-medium text-white"
              >
                Create work order →
              </button>
            </form>
          ))}
        </div>
      )}

      <div className="flex flex-col gap-2">
        <h2 className="text-xs font-semibold uppercase tracking-wide text-muted">
          Work orders
        </h2>
        {workOrderList.length === 0 ? (
          <div className="flex h-40 flex-col items-center justify-center gap-1 rounded-lg border border-border bg-surface text-center">
            <p className="text-sm font-semibold text-text">No work orders yet</p>
            <p className="text-xs text-muted">
              Work orders appear once a deal is signed.
            </p>
          </div>
        ) : (
          <div className="flex flex-col gap-2">
            {workOrderList.map((wo) => (
              <Link
                key={wo.id}
                href={`/w/${params.orgId}/coordination/${wo.id}`}
                className="flex items-center justify-between gap-4 rounded-lg border border-border bg-surface px-4 py-3 hover:border-accent"
              >
                <div>
                  <div className="flex items-center gap-2">
                    <p className="text-sm font-semibold text-text">
                      {wo.estimate?.company || wo.estimate?.contact_name || "Untitled"}
                    </p>
                    {wo.voided_at && (
                      <span className="rounded-full bg-surface2 px-2 py-0.5 text-xs font-medium text-muted line-through">
                        Voided
                      </span>
                    )}
                  </div>
                  {wo.estimate?.site_address && (
                    <p className="text-xs text-muted">{wo.estimate.site_address}</p>
                  )}
                </div>
                <span className="w-16 text-right text-xs text-muted">
                  {formatDate(wo.created_at)}
                </span>
              </Link>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
