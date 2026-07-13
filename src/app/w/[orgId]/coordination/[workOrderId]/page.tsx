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
import type { Database } from "@/lib/supabase/database.types";

type WorkOrder = Database["public"]["Tables"]["work_orders"]["Row"];
type Estimate = Database["public"]["Tables"]["estimates"]["Row"];
type MaterialItem = Database["public"]["Tables"]["material_items"]["Row"];
type ScheduleBlock = Database["public"]["Tables"]["schedule_blocks"]["Row"];

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

  const [{ data: fetchedEstimate }, { data: materialsData }, { data: scheduleData }] =
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
    ]);

  const estimate = fetchedEstimate?.[0] as Estimate | undefined;
  const materials = (materialsData ?? []) as MaterialItem[];
  const scheduleBlocks = (scheduleData ?? []) as ScheduleBlock[];

  const stages = coordinationStages({
    signOffAt: workOrder.sign_off_at,
    materialCount: materials.length,
    scheduleCount: scheduleBlocks.length,
  });

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
        <div className="mt-1 flex items-center gap-2">
          <h1 className="text-2xl font-semibold text-text">
            {estimate?.company || estimate?.contact_name || "Work order"}
          </h1>
          {workOrder.voided_at && (
            <span className="rounded-full bg-surface2 px-2 py-0.5 text-xs font-medium text-muted line-through">
              Voided
            </span>
          )}
        </div>
        {estimate?.site_address && (
          <p className="text-sm text-muted">{estimate.site_address}</p>
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

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <div className="flex flex-col gap-4">
          <SignOffPanel orgId={params.orgId} workOrder={workOrder} />

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
        </div>

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
      </div>

      <WorkOrderDangerZone
        orgId={params.orgId}
        workOrderId={workOrder.id}
        voidedAt={workOrder.voided_at}
        canDelete={materials.length === 0 && scheduleBlocks.length === 0}
      />
    </div>
  );
}
