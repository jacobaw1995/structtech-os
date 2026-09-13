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
import { PurchaseOrderList } from "@/components/purchasing/PurchaseOrderList";
import type { PurchaseOrder } from "@/lib/purchasing/model";
import { WorkOrderDangerZone } from "@/components/coordination/WorkOrderDangerZone";
import { AddTradeWorkOrderForm } from "@/components/coordination/AddTradeWorkOrderForm";
import { TakeOffPanel, type TakeOffLine } from "@/components/coordination/TakeOffPanel";
import { MasterTakeOffCard } from "@/components/coordination/MasterTakeOffCard";
import type { Database } from "@/lib/supabase/database.types";

type WorkOrder = Database["public"]["Tables"]["work_orders"]["Row"];
type Estimate = Database["public"]["Tables"]["estimates"]["Row"];
type MaterialItem = Database["public"]["Tables"]["material_items"]["Row"];
type ScheduleBlock = Database["public"]["Tables"]["schedule_blocks"]["Row"];
type WorkOrderActivity = Database["public"]["Tables"]["work_order_activity"]["Row"];

// Shape of fetch_work_order_tree's jsonb. Declared here because a jsonb-
// returning RPC is `Json` to the generated types — the contract lives in the
// migration, and this is the one place that reads it.
type TradeNode = {
  id: string;
  trade: string | null;
  assignee_type: string | null;
  assignee_ref: string | null;
  predecessor_id: string | null;
  voided_at: string | null;
  voided_by_cascade: boolean;
  material_count: number;
  schedule_count: number;
};
type WorkOrderTree = {
  work_order_id: string;
  level: "master" | "trade";
  job_id: string;
  master_id: string | null;
  master_sign_off_at: string | null;
  voided_at: string | null;
  voided_by_cascade: boolean;
  trades: TradeNode[];
  job_material_count: number;
  job_schedule_count: number;
};

export default async function WorkOrderPage({
  params,
  searchParams,
}: {
  params: { orgId: string; workOrderId: string };
  searchParams: { error?: string; notice?: string };
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

  // A1.4 — the hierarchy comes from one RPC instead of two ad-hoc job-scoped
  // table queries. fetch_work_order_tree returns this work order's level, the
  // job's master id, and every trade on the job with its own voided state and
  // whether that void was its own or its master's cascade. fetch_work_order
  // above is unchanged and still returns the row itself: its `setof
  // work_orders` shape is what the deployed page reads, and narrowing it would
  // have broken production between the migration and the deploy (rule 5b).
  const [{ data: fetchedEstimate }, { data: materialsData }, { data: scheduleData }, { data: activityData }, { data: memberRows }, { data: treeData }, { data: tradeNameData }, { data: lineItemData }, { data: canViewFinancials }, { data: canScheduleData }, { data: canPurchaseData }] =
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
      supabase.rpc("fetch_work_order_tree", { p_work_order_id: workOrder.id }),
      // Trade names this org has already used — the datalist's only source.
      // Not a fixed vocabulary: it is empty on a tenant's first job and never
      // limits what can be typed.
      supabase
        .from("work_orders")
        .select("trade")
        .eq("org_id", params.orgId)
        .eq("kind", "trade"),
      // A2.2 — the take-off's source rows. List query, so direct (rule 5), and
      // the crew gate is the table's own RESTRICTIVE can_view_financials()
      // policy: a field member gets zero rows here without this page doing
      // anything. What this page must NOT do is read that zero as "the
      // estimate has no lines" — see the canViewFinancials branch below.
      supabase
        .from("estimate_line_items")
        .select("id, description, quantity, unit")
        .eq("estimate_id", workOrder.estimate_id)
        .order("sort_order", { ascending: true }),
      supabase.rpc("can_view_financials", { p_org_id: params.orgId }),
      // U-W1.6 — Track S wired `schedule` to refuse at RPC and RLS on
      // 2026-09-05 (3 RPCs + 3 policies on schedule_blocks). Until today this
      // page never asked, so it offered eight controls — crew/start/end/delete
      // on every existing block, plus crew/start/end/add — that all three
      // schedule RPCs raise `your role cannot schedule work in this workspace`
      // for. Measured, not assumed: a grep of src/ for the capability returned
      // a stage key and a model constant, and nothing else.
      supabase.rpc("has_capability", { p_org_id: params.orgId, p_capability: "schedule" }),
      // A2.3 — purchase orders. Gates the WRITE path only: reading a purchase
      // order is org-scoped and needs no capability (controller ruling
      // 2026-09-08, and the three read policies agree).
      supabase.rpc("has_capability", { p_org_id: params.orgId, p_capability: "manage_purchasing" }),
    ]);

  const estimate = fetchedEstimate?.[0] as Estimate | undefined;
  const materials = (materialsData ?? []) as MaterialItem[];
  const scheduleBlocks = (scheduleData ?? []) as ScheduleBlock[];
  const activity = (activityData ?? []) as WorkOrderActivity[];
  const members = memberRows ?? [];

  // Closed default, matching has_capability(): anything that is not an explicit
  // TRUE is a no. A null here (RPC error, network) must not read as permission.
  const canSchedule = canScheduleData === true;
  const canPurchase = canPurchaseData === true;

  // A2.3 — the job's purchase orders. Fetched only on the MASTER, because a PO
  // covers one JOB across any number of trades; hanging it off a trade would
  // assert one PO per trade, which the schema deliberately does not say.
  const isMasterKind = workOrder.kind === "master";
  const jobIdForPos = (treeData as WorkOrderTree | null)?.job_id ?? null;
  const { data: poRows } =
    isMasterKind && jobIdForPos
      ? await supabase.rpc("list_purchase_orders", {
          p_org_id: params.orgId,
          p_job_id: jobIdForPos,
        })
      : { data: null };
  const purchaseOrders = (poRows ?? []) as PurchaseOrder[];

  const tree = (treeData ?? null) as WorkOrderTree | null;
  const isMaster = workOrder.kind === "master";
  const trades = tree?.trades ?? [];
  const masterId = tree?.master_id ?? null;
  const jobMaterialCount = tree?.job_material_count ?? 0;
  const jobScheduleCount = tree?.job_schedule_count ?? 0;
  const liveTrades = trades.filter((t) => t.voided_at === null);
  const cascadeVoidedTrades = trades.filter((t) => t.voided_by_cascade);
  const tradeSuggestions = Array.from(
    new Set(
      ((tradeNameData ?? []) as { trade: string | null }[])
        .map((r) => r.trade)
        .filter((t): t is string => t !== null && t.length > 0)
    )
  ).sort();

  function tradeById(id: string | null): TradeNode | undefined {
    return id ? trades.find((w) => w.id === id) : undefined;
  }

  // "crew · Ramirez crew". Both halves are always present or both absent —
  // create_trade_work_order refuses a half-specified assignee.
  function assigneeLabel(w: {
    assignee_type: string | null;
    assignee_ref: string | null;
  }): string {
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
    signOffAt: tree?.master_sign_off_at ?? null,
    materialCount: isMaster ? jobMaterialCount : materials.length,
    scheduleCount: isMaster ? jobScheduleCount : scheduleBlocks.length,
  });

  // A1.4 moved the real guard into the RPC: delete_work_order now refuses a
  // master that still has trades and names the count in the message. This
  // stays as a UI hint so the button is not offered in a case that will only
  // produce an error — the same "UI hint + RPC is the real guard" split used
  // everywhere else, no longer the stopgap it was in A1.3a.
  const canDelete = isMaster
    ? trades.length === 0 && jobMaterialCount === 0 && jobScheduleCount === 0
    : materials.length === 0 && scheduleBlocks.length === 0;

  const nextMaterialSortOrder =
    materials.length === 0 ? 0 : Math.max(...materials.map((m) => m.sort_order)) + 1;

  // A2.2 — provenance drives the panel. material_items.estimate_line_item_id is
  // the column added with this task, and it is what lets the page distinguish
  // "not taken off yet" from "already on this trade" without guessing by name.
  const takenOffLineIds = new Set(
    materials
      .map((m) => m.estimate_line_item_id)
      .filter((id): id is string => id !== null)
  );
  const takeOffLines: TakeOffLine[] = (
    (lineItemData ?? []) as {
      id: string;
      description: string;
      quantity: number;
      unit: string | null;
    }[]
  ).map((l) => ({
    id: l.id,
    description: l.description,
    quantity: l.quantity,
    unit: l.unit,
    alreadyTakenOff: takenOffLineIds.has(l.id),
  }));

  // §7.1 — NEVER INFER "DOES NOT EXIST" FROM "CANNOT SEE". estimate_line_items
  // carries a RESTRICTIVE can_view_financials() policy, so a crew member's read
  // above returns zero rows on an estimate that has twenty. Branching on the
  // capability (which is knowable) rather than on the empty array (which is
  // ambiguous) is what keeps the empty state from lying.
  const canSeeEstimateLines = canViewFinancials === true;

  return (
    <div className="flex h-full flex-col gap-4">
      <div>
        <Link
          href={`/w/${params.orgId}/coordination`}
          className="text-sm text-muted"
        >
          ← Coordination
        </Link>
        {!isMaster && masterId && (
          <Link
            href={`/w/${params.orgId}/coordination/${masterId}`}
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
              {tree?.voided_by_cascade ? "Voided with master" : "Voided"}
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

      {searchParams.notice && (
        <p className="rounded-md bg-accent-soft px-3 py-2 text-sm text-text">
          {searchParams.notice}
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
                      {/* Restoring the master brings back only the trades the
                          cascade took. A trade voided on its own stays voided,
                          and the user has to be able to see which is which. */}
                      {t.voided_by_cascade ? "Voided with master" : "Voided"}
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

      {isMaster && (
        <PurchaseOrderList
          orgId={params.orgId}
          returnTo={`/w/${params.orgId}/coordination/${workOrder.id}`}
          jobId={jobIdForPos}
          orgName={ctx.active.org_name}
          orders={purchaseOrders}
          canPurchase={canPurchase}
        />
      )}

      {/* A2.2 clause (b) lives here — see MasterTakeOffCard for why the button
          is offered on a level that can never be a valid destination. */}
      {isMaster && (
        <MasterTakeOffCard
          orgId={params.orgId}
          masterWorkOrderId={workOrder.id}
          liveTradeCount={liveTrades.length}
        />
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

            {/* A2.2. Three distinct states, and the third is the point: an
                empty list because the estimate has none, versus an empty list
                because this viewer is not allowed to see them, are different
                facts (§7.1). The crew case says "restricted", never "none". */}
            {canSeeEstimateLines ? (
              takeOffLines.length > 0 ? (
                <TakeOffPanel
                  orgId={params.orgId}
                  workOrderId={workOrder.id}
                  lines={takeOffLines}
                />
              ) : (
                <p className="border-t border-border pt-2 text-xs text-muted">
                  The estimate has no line items to take off.
                </p>
              )
            ) : (
              <p className="border-t border-border pt-2 text-xs text-muted">
                Estimate line items are restricted for your role, so the
                take-off is not available here.
              </p>
            )}
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
              canSchedule={canSchedule}
            />
          ))}
          {canSchedule ? (
            <AddScheduleBlockForm orgId={params.orgId} workOrderId={workOrder.id} />
          ) : (
            /* NOT a disabled button. SCOPE §2.8 forbids blocking an action the
               user is PERMITTED to take because other data is incomplete —
               the catalog's manage_catalog gate and the permissions page's
               manager gate draw the same line. This user is not permitted, and
               the database will say so; offering the control anyway would make
               the refusal arrive AFTER they had typed a crew name and two
               dates, which is the worst version of a block.

               Same voice as the roadmap `restricted` copy: says what is true,
               says what to do, and does not explain the mechanism. It names no
               role, because `schedule` is granted per member and the role that
               holds it differs per tenant — naming "an owner" would be a guess
               rendered as a fact. */
            <p className="border-t border-border pt-2 text-sm text-muted">
              Your role can see the schedule here but not change it. Ask whoever
              manages scheduling in {ctx.active.org_name} if a date needs to move.
            </p>
          )}
        </div>
        )}
      </div>

      <WorkOrderDangerZone
        orgId={params.orgId}
        workOrderId={workOrder.id}
        voidedAt={workOrder.voided_at}
        voidedByCascade={tree?.voided_by_cascade ?? false}
        masterId={masterId}
        liveTradeCount={liveTrades.length}
        cascadeVoidedTradeCount={cascadeVoidedTrades.length}
        canDelete={canDelete}
      />
    </div>
  );
}
