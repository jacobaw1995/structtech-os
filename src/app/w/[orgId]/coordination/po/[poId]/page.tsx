import Link from "next/link";
import { redirect } from "next/navigation";
import { requireModuleAccess } from "@/lib/workspace/context";
import {
  PO_STATUSES,
  PO_STATUS_LABEL,
  PO_STATUS_MEANING,
  isPoStatus,
  isStuckInDraft,
  promiseHistory,
  timesMoved,
  type PurchaseOrder,
  type PurchaseOrderLine,
  type PurchaseOrderLinePromise,
} from "@/lib/purchasing/model";
import { PoLineRow } from "@/components/purchasing/PoLineRow";
import { AddPoLineForm } from "@/components/purchasing/AddPoLineForm";
import { updatePurchaseOrder } from "@/lib/purchasing/actions";

// A2.3 — one purchase order.
//
// READ IS NOT GATED, AND THAT IS A RULING (controller, 2026-09-08): a crew
// member CAN read purchase orders, because the production packet exists so a
// crew knows what materials are coming. Checked against what landed rather
// than taken on trust — all three read policies are
// `org_id in (select my_org_ids())` for `authenticated`, with no capability
// term and no RESTRICTIVE companion, and neither read RPC tests the key.
//
// So this page is reachable by anyone with `coordination`, and every WRITE
// control is gated on has_capability(org, 'manage_purchasing') — not rendered
// when absent, with the reason stated. That is U-W1.6's shape: the scheduling
// surface used to offer eight controls the RPC refuses, and the refusal
// arrived after the user had typed.

export default async function PurchaseOrderPage({
  params,
  searchParams,
}: {
  params: { orgId: string; poId: string };
  searchParams: { error?: string };
}) {
  const ctx = await requireModuleAccess(params.orgId, "coordination");
  const supabase = ctx.supabase;

  // Single-record fetch through the RPC (CLAUDE.md rule 4).
  const { data: poRows } = await supabase.rpc("fetch_purchase_order", {
    p_po_id: params.poId,
  });
  const po = poRows?.[0] as PurchaseOrder | undefined;

  if (!po || po.org_id !== params.orgId) {
    redirect(`/w/${params.orgId}/coordination`);
  }

  const [{ data: lineRows }, { data: canPurchaseData }] = await Promise.all([
    // List query, so direct (rule 5); RLS scopes it by org.
    supabase
      .from("purchase_order_lines")
      .select("*")
      .eq("purchase_order_id", po.id)
      .order("created_at", { ascending: true }),
    supabase.rpc("has_capability", {
      p_org_id: params.orgId,
      p_capability: "manage_purchasing",
    }),
  ]);

  const lines = (lineRows ?? []) as PurchaseOrderLine[];
  // Closed default, matching has_capability(): anything that is not an
  // explicit TRUE is a no. A null (RPC error, network) must not read as
  // permission.
  const canPurchase = canPurchaseData === true;

  const itemIds = Array.from(new Set(lines.map((l) => l.material_item_id)));
  const lineIds = lines.map((l) => l.id);

  const [{ data: itemRows }, { data: promiseRows }] = await Promise.all([
    itemIds.length
      ? supabase
          .from("material_items")
          .select("id, name, unit, quantity, ready_by, ready_by_source, work_order_id")
          .in("id", itemIds)
      : Promise.resolve({ data: [] as never[] }),
    lineIds.length
      ? supabase
          .from("purchase_order_line_promises")
          .select("*")
          .in("purchase_order_line_id", lineIds)
      : Promise.resolve({ data: [] as never[] }),
  ]);

  type ItemRow = {
    id: string;
    name: string;
    unit: string | null;
    quantity: number;
    ready_by: string | null;
    ready_by_source: string;
    work_order_id: string;
  };
  const items = (itemRows ?? []) as ItemRow[];
  const promises = (promiseRows ?? []) as PurchaseOrderLinePromise[];

  // Trade names, so the cross-trade property is VISIBLE rather than implied.
  const woIds = Array.from(new Set(items.map((i) => i.work_order_id)));
  const { data: woRows } = woIds.length
    ? await supabase.from("work_orders").select("id, trade").in("id", woIds)
    : { data: [] as never[] };
  const tradeOf = new Map(
    ((woRows ?? []) as { id: string; trade: string | null }[]).map((w) => [
      w.id,
      w.trade ?? "Untitled trade",
    ])
  );

  const itemById = new Map(items.map((i) => [i.id, i]));

  // Selectable items for the add form: THE WHOLE JOB'S, across every trade,
  // because that is the property the schema encodes. Two list queries rather
  // than an embed (the null-embed sweep of 2026-08-27 left exactly one embed
  // in src/, and this is not going to be the second).
  let jobItems: { id: string; name: string; unit: string | null; trade: string }[] = [];
  if (po.job_id) {
    const { data: jobWos } = await supabase
      .from("work_orders")
      .select("id, trade")
      .eq("job_id", po.job_id)
      .eq("kind", "trade");
    const wos = (jobWos ?? []) as { id: string; trade: string | null }[];
    if (wos.length) {
      const { data: jobItemRows } = await supabase
        .from("material_items")
        .select("id, name, unit, work_order_id")
        .in(
          "work_order_id",
          wos.map((w) => w.id)
        )
        .order("sort_order", { ascending: true });
      const tradeByWo = new Map(wos.map((w) => [w.id, w.trade ?? "Untitled trade"]));
      jobItems = (
        (jobItemRows ?? []) as {
          id: string;
          name: string;
          unit: string | null;
          work_order_id: string;
        }[]
      ).map((i) => ({
        id: i.id,
        name: i.name,
        unit: i.unit,
        trade: tradeByWo.get(i.work_order_id) ?? "Untitled trade",
      }));
    }
  }
  const status = isPoStatus(po.status) ? po.status : "draft";
  const stuck = isStuckInDraft(po);

  // THE PROPERTY, MADE VISIBLE: one PO, one supplier, materials across several
  // trades. Counting the distinct trades is how the page says so without
  // asserting it in prose that could go stale.
  const tradesCovered = Array.from(
    new Set(lines.map((l) => tradeOf.get(itemById.get(l.material_item_id)?.work_order_id ?? "") ?? "—"))
  );

  return (
    <div className="mx-auto flex w-full max-w-4xl flex-col gap-4">
      <Link
        href={`/w/${params.orgId}/coordination`}
        className="inline-flex min-h-11 items-center self-start text-sm text-muted hover:text-accent-strong sm:min-h-0"
      >
        ← Coordination
      </Link>

      <div className="flex flex-wrap items-start justify-between gap-x-4 gap-y-2">
        <div className="min-w-0">
          <h1 className="text-2xl font-semibold text-text">{po.supplier_name}</h1>
          <p className="text-sm text-muted">
            Purchase order · {ctx.active.org_name}
            {po.reference ? ` · ${po.reference}` : ""}
          </p>
        </div>
        <span
          className={`inline-flex items-center rounded-full px-3 py-1 text-sm font-medium ${
            status === "cancelled"
              ? "bg-surface2 text-muted"
              : status === "draft"
                ? "border border-border text-text"
                : "bg-accent-soft text-accent-strong"
          }`}
        >
          {PO_STATUS_LABEL[status]}
        </span>
      </div>

      {searchParams.error && (
        <p className="rounded-lg border border-warn bg-warn-soft px-4 py-3 text-sm text-text">
          {searchParams.error}
        </p>
      )}

      {/* A PO WITH NO JOB. §2.8: warn at draft time, block only at the
          transition — and the block is the RPC's, not this page's. What this
          page adds is that the advice in the refusal ("attach it to a job
          first") is currently impossible: `job_id` is written only at INSERT,
          in create_purchase_order, and no RPC updates it. Saying so is better
          than letting someone hunt for a control that does not exist. */}
      {stuck && (
        <section className="rounded-lg border border-warn bg-warn-soft px-4 py-3">
          <h2 className="text-sm font-semibold text-text">
            This purchase order has no job attached
          </h2>
          <p className="mt-1 text-sm leading-relaxed text-text">
            It can be edited as a draft, and it cannot be sent or confirmed —
            leaving draft needs a job.
          </p>
          <p className="mt-1.5 text-xs leading-relaxed text-muted">
            There is no way to attach one from here yet: a job is set when the
            purchase order is created and nothing changes it afterwards. Create
            a replacement from the job and delete this one.
          </p>
        </section>
      )}

      {/* NO MONEY, AND NOTHING THAT IMPLIES ONE IS COMING. The only numeric on
          either table is quantity_ordered. No currency, no empty cost column,
          no "pricing soon". */}
      <section className="rounded-lg border border-border bg-surface">
        <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 border-b border-border px-4 py-2">
          <h2 className="text-xs font-semibold uppercase tracking-wide text-muted">
            Items on this order
          </h2>
          <span className="text-xs text-muted">
            {lines.length} line{lines.length === 1 ? "" : "s"}
            {tradesCovered.length > 1 &&
              ` · across ${tradesCovered.length} trades`}
          </span>
        </div>

        {lines.length === 0 ? (
          <p className="px-4 py-4 text-sm text-muted">
            No items yet. A purchase order with no lines is a valid draft — add
            them as the supplier confirms what they can supply.
          </p>
        ) : (
          <ul>
            {lines.map((line) => {
              const item = itemById.get(line.material_item_id);
              const history = promiseHistory(promises, line.id);
              return (
                <PoLineRow
                  key={line.id}
                  orgId={params.orgId}
                  poId={po.id}
                  line={line}
                  itemName={item?.name ?? "Unknown item"}
                  itemUnit={item?.unit ?? null}
                  itemQuantity={item?.quantity ?? null}
                  trade={tradeOf.get(item?.work_order_id ?? "") ?? null}
                  readyBy={item?.ready_by ?? null}
                  readyBySource={item?.ready_by_source ?? "manual"}
                  history={history.map((h) => ({
                    id: h.id,
                    promised_date: h.promised_date,
                    recorded_at: h.recorded_at,
                  }))}
                  timesMoved={timesMoved(history.length)}
                  canPurchase={canPurchase}
                />
              );
            })}
          </ul>
        )}

        {canPurchase ? (
          <AddPoLineForm
            orgId={params.orgId}
            poId={po.id}
            items={jobItems}
            cancelled={status === "cancelled"}
          />
        ) : (
          /* Not a disabled button. Same shape as the scheduling gate: the
             control is absent and the reason is stated, in the voice used for
             the roadmap `restricted` copy — says what is true, says what to
             do, and does not explain the mechanism. It names no role, because
             manage_purchasing is granted per member and the role holding it
             differs per tenant. */
          <p className="border-t border-border px-4 py-3 text-sm text-muted">
            Your role can read this purchase order but not change it. Ask
            whoever handles purchasing in {ctx.active.org_name} if something
            here needs to move.
          </p>
        )}
      </section>

      {canPurchase && (
        <section className="rounded-lg border border-border bg-surface p-4">
          <h2 className="mb-1 text-xs font-semibold uppercase tracking-wide text-muted">
            Status
          </h2>
          <p className="mb-3 text-sm text-muted">{PO_STATUS_MEANING[status]}</p>
          <div className="flex flex-wrap gap-2">
            {PO_STATUSES.filter((s) => s !== status).map((s) => (
              <form key={s} action={updatePurchaseOrder}>
                <input type="hidden" name="orgId" value={params.orgId} />
                <input type="hidden" name="poId" value={po.id} />
                <input type="hidden" name="status" value={s} />
                <button
                  type="submit"
                  className={`min-h-14 rounded-md border px-4 text-sm font-medium sm:h-10 sm:min-h-0 ${
                    s === "cancelled"
                      ? "border-border text-warn"
                      : "border-border text-text"
                  }`}
                >
                  {s === "cancelled" ? "Cancel this order" : `Mark ${PO_STATUS_LABEL[s]}`}
                </button>
              </form>
            ))}
          </div>
          {/* CANCELLATION IS ON THE HEADER. There is no per-line cancel,
              because purchase_order_lines has no status column — the ready-by
              derivation drops a line only when its PO is cancelled. Saying
              this next to the button is cheaper than someone looking for a
              line-level control that cannot exist. */}
          <p className="mt-3 text-xs leading-relaxed text-muted">
            Cancelling applies to the whole order — a line cannot be cancelled
            on its own. Cancelled orders stop counting toward material ready-by
            dates.
          </p>
        </section>
      )}
    </div>
  );
}
