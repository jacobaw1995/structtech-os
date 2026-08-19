import { redirect } from "next/navigation";
import Link from "next/link";
import { requireModuleAccess } from "@/lib/workspace/context";
import { coordinationStages } from "@/lib/coordination/stage";
import { ProgressChips } from "@/components/coordination/ProgressChips";
import { SignOffPanel } from "@/components/coordination/SignOffPanel";
import { MaterialItemRow } from "@/components/coordination/MaterialItemRow";
import { AddMaterialItemForm } from "@/components/coordination/AddMaterialItemForm";
import { ScheduleBlockRow } from "@/components/coordination/ScheduleBlockRow";
import { AddScheduleBlockForm } from "@/components/coordination/AddScheduleBlockForm";
import { WorkOrderDangerZone } from "@/components/coordination/WorkOrderDangerZone";
import { AddTradeWorkOrderForm } from "@/components/coordination/AddTradeWorkOrderForm";
import type { Database } from "@/lib/supabase/database.types";

type WorkOrder = Database["public"]["Tables"]["work_orders"]["Row"];
type Estimate = Database["public"]["Tables"]["estimates"]["Row"];
type MaterialItem = Database["public"]["Tables"]["material_items"]["Row"];
type ScheduleBlock = Database["public"]["Tables"]["schedule_blocks"]["Row"];
type WorkOrderActivity = Database["public"]["Tables"]["work_order_activity"]["Row"];

export default async function WorkOrderPage({
  params,
  searchParams,
}: {
  params: { orgId: string; workOrderId: string };
  searchParams: { error?: string };
}) {
  const ctx = await requireModuleAccess(params.orgId, "coordination");
  const supabase = ctx.supabase;

  // Single-record fetch RPC (CLAUDE.md rule 4), same pattern as
  // fetch_estimate in estimating/[estimateId]/page.tsx.
  const { data: fetchedWorkOrder } = await supabase.rpc("fetch_work_order", {
    p_work_order_id: params.workOrderId,
  });
  const workOrder = fetchedWorkOrder?.[0] as WorkOrder | undefined;

  // Guards the agency_admin multi-org case the same way estimating's page
  // does — fetch_work_order only guarantees org membership, not THIS org.
  if (!workOrder || workOrder.org_id !== params.orgId) {
    redirect(`/w/${params.orgId}/coordination`);
  }

  const [{ data: fetchedEstimate }, { data: materialsData }, { data: scheduleData }, { data: activityData }, { data: memberRows }, { data: jobWorkOrderData }, { data: tradeNameData }] =
    await Promise.all([
      supabase.rpc("fetch_estimate", { p_estimate_id: workOrder.estimate_id }),
      supabase
        .from("material_items")
        .select("*")
        .eq("work_order_id", workOrder.id)
        .order("sort_order", { ascending: true }),
      supabase
        .from("schedule_blocks")
        .select("*")
        .eq("work_order_id", workOrder.id)
        .order("start_date", { ascending: true }),
      supabase
        .from("work_order_activity")
        .select("*")
        .eq("work_order_id", workOrder.id)
        .order("created_at", { ascending: true }),
      supabase.rpc("list_org_members", { p_org_id: params.orgId }),
      // Every work order on this job — one query serves both pages: a master
      // renders the trades under it, a trade renders a link back up to its
      // master. List query, so direct table access is fine (CLAUDE.md rule 5).
      supabase
        .from("work_orders")
        .select("*")
        .eq("job_id", workOrder.job_id)
        .order("created_at", { ascending: true }),
      // Trade names this org has already used — the datalist's only source.
      // Not a fixed vocabulary: it is empty on a tenant's first job and never
      // limits what can be typed.
      supabase
        .from("work_orders")
        .select("trade")
        .eq("org_id", params.orgId)
        .eq("kind", "trade"),
    ]);

  const estimate = fetchedEstimate?.[0] as Estimate | undefined;
  const materials = (materialsData ?? []) as MaterialItem[];
  const scheduleBlocks = (scheduleData ?? []) as ScheduleBlock[];
  const activity = (activityData ?? []) as WorkOrderActivity[];
  const members = memberRows ?? [];

  const isMaster = workOrder.kind === "master";
  const jobWorkOrders = (jobWorkOrderData ?? []) as WorkOrder[];
  const trades = jobWorkOrders.filter((w) => w.kind === "trade");
  const master = jobWorkOrders.find((w) => w.kind === "master");
  const tradeSuggestions = Array.from(
    new Set(
      ((tradeNameData ?? []) as { trade: string | null }[])
        .map((r) => r.trade)
        .filter((t): t is string => t !== null && t.length > 0)
    )
  ).sort();

  // A1.3b: materials and schedule now live on trades, so a master's own
  // material_items/schedule_blocks queries return nothing by definition. The
  // master still needs to SUMMARISE them, so count them across the job. Second
  // round trip rather than one: the ids come from the query above.
  const jobWorkOrderIds = jobWorkOrders.map((w) => w.id);
  const [{ data: jobMaterialData }, { data: jobScheduleData }] = await Promise.all([
    supabase.from("material_items").select("id").in("work_order_id", jobWorkOrderIds),
    supabase.from("schedule_blocks").select("id").in("work_order_id", jobWorkOrderIds),
  ]);
  const jobMaterialCount = (jobMaterialData ?? []).length;
  const jobScheduleCount = (jobScheduleData ?? []).length;

  function tradeById(id: string | null): WorkOrder | undefined {
    return id ? jobWorkOrders.find((w) => w.id === id) : undefined;
  }

  // "crew · Ramirez crew". Both halves are always present or both absent —
  // create_trade_work_order refuses a half-specified assignee.
  function assigneeLabel(w: WorkOrder): string {
    if (!w.assignee_type || !w.assignee_ref) return "Unassigned";
    return `${w.assignee_type} · ${w.assignee_ref}`;
  }

  function authorName(userId: string | null): string {
    if (!userId) return "Unknown";
    return members.find((m: { user_id: string; full_name: string | null }) => m.user_id === userId)?.full_name ?? "Unknown";
  }

  // Sign-off always reads off the MASTER — after A1.3b a trade's own
  // sign_off_at is null by construction, so a trade reading its own column
  // would permanently show "not signed off" on a job that is signed.
  // Material/schedule counts are job-wide on a master and own-trade on a trade,
  // which is exactly what each level is responsible for.
  const stages = coordinationStages({
    signOffAt: master?.sign_off_at ?? null,
    materialCount: isMaster ? jobMaterialCount : materials.length,
    scheduleCount: isMaster ? jobScheduleCount : scheduleBlocks.length,
  });

  // The trades.length gate is a UI-level stopgap only: delete_work_order does
  // not yet know about children, so offering delete on a master with trades
  // would orphan them. A1.4 makes the RPC itself refuse or cascade explicitly,
  // and that is the real enforcement — this only keeps A1.3a from shipping a
  // new way to break the tree.
  const canDelete = isMaster
    ? trades.length === 0 && jobMaterialCount === 0 && jobScheduleCount === 0
    : materials.length === 0 && scheduleBlocks.length === 0;

  const nextMaterialSortOrder =
    materials.length === 0 ? 0 : Math.max(...materials.map((m) => m.sort_order)) + 1;

  return (
    <div className="flex h-full flex-col gap-4">
      <div>
        <Link
          href={`/w/${params.orgId}/coordination`}
          className="text-sm text-muted"
        >
          ← Coordination
        </Link>
        {!isMaster && master && (
          <Link
            href={`/w/${params.orgId}/coordination/${master.id}`}
            className="ml-3 text-sm text-muted"
          >
            ↑ Master work order
          </Link>
        )}
        <div className="mt-1 flex flex-wrap items-center gap-2">
          <h1 className="text-2xl font-semibold text-text">
            {estimate?.company || estimate?.contact_name || "Work order"}
          </h1>
          {!isMaster && workOrder.trade && (
            <span className="rounded-full bg-accent-soft px-2 py-0.5 text-xs font-medium text-accent-strong">
              {workOrder.trade}
            </span>
          )}
          {workOrder.voided_at && (
            <span className="rounded-full bg-surface2 px-2 py-0.5 text-xs font-medium text-muted line-through">
              Voided
            </span>
          )}
        </div>
        {estimate?.site_address && (
          <p className="text-sm text-muted">{estimate.site_address}</p>
        )}
        {!isMaster && (
          <p className="text-xs text-muted">
            {assigneeLabel(workOrder)}
            {workOrder.predecessor_id &&
              ` · after ${tradeById(workOrder.predecessor_id)?.trade ?? "another trade"}`}
          </p>
        )}
        {estimate?.squares != null && (
          <p className="font-mono text-xs text-muted">
            {estimate.squares} sq{estimate.pitch ? ` · ${estimate.pitch} pitch` : ""}
          </p>
        )}
      </div>

      <ProgressChips stages={stages} />

      {searchParams.error && (
        <p className="rounded-md bg-warn-soft px-3 py-2 text-sm text-text">
          {searchParams.error}
        </p>
      )}

      {/* Master only — trades do not nest, so a trade page offers no way to
          create another trade and shows no trade list. */}
      {isMaster && (
        <div className="rounded-lg border border-border bg-surface p-3">
          <h2 className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted">
            Trade work orders
          </h2>
          {trades.length === 0 && (
            <p className="py-2 text-sm text-muted">
              No trade work orders yet. Add the first one below — the trade is
              whatever this job actually needs, typed in full.
            </p>
          )}
          {trades.map((t) => (
            <Link
              key={t.id}
              href={`/w/${params.orgId}/coordination/${t.id}`}
              className="flex items-center justify-between gap-3 border-b border-border py-2 last:border-b-0"
            >
              <div className="min-w-0">
                <p className="flex items-center gap-2 text-sm font-semibold text-text">
                  <span className="truncate">{t.trade}</span>
                  {t.voided_at && (
                    <span className="shrink-0 rounded-full bg-surface2 px-2 py-0.5 text-xs font-medium text-muted line-through">
                      Voided
                    </span>
                  )}
                </p>
                <p className="truncate text-xs text-muted">
                  {assigneeLabel(t)}
                  {t.predecessor_id &&
                    ` · after ${tradeById(t.predecessor_id)?.trade ?? "another trade"}`}
                </p>
              </div>
              <span className="shrink-0 text-muted">→</span>
            </Link>
          ))}
          <AddTradeWorkOrderForm
            orgId={params.orgId}
            masterWorkOrderId={workOrder.id}
            siblingTrades={trades}
            tradeSuggestions={tradeSuggestions}
          />
          {/* Guidance, not a gate: says where the child objects went rather
              than leaving the master looking like it lost them. */}
          {trades.length > 0 && (
            <p className="pt-2 text-xs text-muted">
              Materials and schedule live on each trade — {jobMaterialCount}{" "}
              material{jobMaterialCount === 1 ? "" : "s"} and {jobScheduleCount}{" "}
              schedule block{jobScheduleCount === 1 ? "" : "s"} across this job.
            </p>
          )}
        </div>
      )}

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <div className="flex flex-col gap-4">
          {/* Sign-off is recorded once on the master (A1.3b) — a trade page does
              not offer it, because record_work_order_sign_off would refuse it. */}
          {isMaster && (
            <SignOffPanel orgId={params.orgId} workOrder={workOrder} activity={activity} authorName={authorName} />
          )}

          {/* Materials attach to a trade. Rendering this form on a master would
              offer a control the RPC now always refuses — the third clause of
              A1.3b's Done when. Hiding what cannot exist at this level is not
              SCOPE §2.8 blocking: nothing here is disabled pending other data. */}
          {!isMaster && (
          <div className="rounded-lg border border-border bg-surface p-3">
            <h2 className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted">
              Material list
            </h2>
            {materials.length === 0 && (
              <p className="py-2 text-sm text-muted">No materials added yet.</p>
            )}
            {materials.map((item) => (
              <MaterialItemRow
                key={item.id}
                orgId={params.orgId}
                workOrderId={workOrder.id}
                item={item}
              />
            ))}
            <AddMaterialItemForm
              orgId={params.orgId}
              workOrderId={workOrder.id}
              nextSortOrder={nextMaterialSortOrder}
            />
          </div>
          )}
        </div>

        {!isMaster && (
        <div className="rounded-lg border border-border bg-surface p-3">
          <h2 className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted">
            Schedule — crew + dates
          </h2>
          {materials.some((m) => m.ready_by) && (
            <p className="mb-2 text-xs text-muted">
              Earliest start is gated on the latest material ready-by date.
            </p>
          )}
          {scheduleBlocks.length === 0 && (
            <p className="py-2 text-sm text-muted">No schedule blocks yet.</p>
          )}
          {scheduleBlocks.map((block) => (
            <ScheduleBlockRow
              key={block.id}
              orgId={params.orgId}
              workOrderId={workOrder.id}
              block={block}
            />
          ))}
          <AddScheduleBlockForm orgId={params.orgId} workOrderId={workOrder.id} />
        </div>
        )}
      </div>

      <WorkOrderDangerZone
        orgId={params.orgId}
        workOrderId={workOrder.id}
        voidedAt={workOrder.voided_at}
        canDelete={canDelete}
      />
    </div>
  );
}
