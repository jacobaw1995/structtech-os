import Link from "next/link";
import { redirect } from "next/navigation";
import { requireModuleAccess } from "@/lib/workspace/context";
import {
  PO_STATUSES,
  PO_STATUS_LABEL,
  PO_STATUS_MEANING,
  isPoStatus,
  isStuckInDraft,
  jobLabel,
  promiseHistory,
  timesMoved,
  type PurchaseOrder,
  type PurchaseOrderLine,
  type PurchaseOrderLinePromise,
} from "@/lib/purchasing/model";
import { PoLineRow } from "@/components/purchasing/PoLineRow";
import { AddPoLineForm } from "@/components/purchasing/AddPoLineForm";
import { StuckDraftBanner } from "@/components/purchasing/StuckDraftBanner";
import {
  updatePurchaseOrder,
  deletePurchaseOrder,
} from "@/lib/purchasing/actions";

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
  searchParams: { error?: string; confirmDelete?: string };
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

  // The org's jobs, labelled by the shared jobLabel(). Two list queries, not
  // an embed. Used for the attach picker on a jobless draft and for the
  // "delivering to" line on every other order.
  const { data: jobRowsRaw } = await supabase
    .from("jobs")
    .select("id, estimate_id, created_at, service_address_street, service_address_city, service_address_state, service_address_zip")
    .eq("org_id", params.orgId)
    .order("created_at", { ascending: false });
  type JobLite = {
    id: string;
    estimate_id: string;
    created_at: string;
    service_address_street: string | null;
    service_address_city: string | null;
    service_address_state: string | null;
    service_address_zip: string | null;
  };
  const jobRows = (jobRowsRaw ?? []) as JobLite[];
  const estIds = Array.from(new Set(jobRows.map((j) => j.estimate_id)));
  const { data: estRowsRaw } = estIds.length
    ? await supabase.from("estimates").select("id, company, contact_name").in("id", estIds)
    : { data: [] as never[] };
  const estById = new Map(
    ((estRowsRaw ?? []) as { id: string; company: string | null; contact_name: string | null }[]).map(
      (e) => [e.id, e]
    )
  );
  const jobChoices = jobRows.map((j) => ({
    id: j.id,
    label: jobLabel(j, estById.get(j.estimate_id) ?? null),
  }));
  const attachedJobLabel = po.job_id
    ? jobChoices.find((j) => j.id === po.job_id)?.label ?? "a job in this workspace"
    : null;

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
        name: i.name.trim(),
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
          {attachedJobLabel && (
            <p className="text-sm text-text">
              <span className="text-muted">For </span>
              {attachedJobLabel}
            </p>
          )}
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

      {/* A PO WITH NO JOB — U-W1.9, rewritten now that the advice can be
          followed. Until 2026-09-10 this banner had to say "there is no way to
          attach one from here yet": job_id was written only at INSERT.
          Migration 20260910215139 added p_job_id to update_purchase_order, so
          the control that follows the advice lives directly under it.

          §2.8 — warn at draft time, block only at the transition. The draft is
          fully editable and nothing here is disabled. The TRANSITION is offered
          only together with a job: update_purchase_order checks the draft-exit
          rule against coalesce(p_job_id, current job), so "attach and mark
          sent" is ONE write that the database accepts, rather than a "Mark
          sent" button it would refuse. That keeps U-W1.6's property — no
          control the backend will refuse — without turning the requirement
          into a gate. */}
      {stuck && (
        <StuckDraftBanner
          orgId={params.orgId}
          poId={po.id}
          orgName={ctx.active.org_name}
          canPurchase={canPurchase}
          jobChoices={jobChoices}
        />
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
                  // TRIMMED — found against LIVE data on 2026-09-10, not in a
                  // fixture. The first real material item on BMR is named
                  // "Ag panel: 26 ga black replacement. " with a trailing
                  // space: the take-off copies an estimate LINE DESCRIPTION
                  // verbatim, so real item names are sentences, not SKUs, and
                  // arrive untrimmed. HTML hides it in body text; it does not
                  // hide it in aria-labels or <option>s.
                  itemName={item?.name?.trim() || "Unknown item"}
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

      {canPurchase && !stuck && (
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

      {/* DELETE — SCOPE §2.6, and for a jobless draft it is the ONLY way out:
          cancelling is itself a transition out of draft, so
          update_purchase_order refuses it without a job. A phone-call draft
          that fell through would otherwise be permanent. Two taps via
          ?confirmDelete=1, and the second names what it removes — the
          catalogue's pattern. This also retires the promise the old banner
          made ("…and delete this one") on a page that had no delete control. */}
      {canPurchase && (
        <section className="rounded-lg border border-border bg-surface p-4">
          {searchParams.confirmDelete === "1" ? (
            <div className="flex flex-col gap-2">
              <p className="text-sm text-text">
                Delete the order to <span className="font-medium">{po.supplier_name}</span>
                {lines.length > 0 &&
                  ` and its ${lines.length} line${lines.length === 1 ? "" : "s"}`}
                ? Material ready-by dates are recalculated without it.
              </p>
              <div className="flex flex-wrap gap-2">
                <form action={deletePurchaseOrder}>
                  <input type="hidden" name="orgId" value={params.orgId} />
                  <input type="hidden" name="poId" value={po.id} />
                  <button
                    type="submit"
                    className="min-h-14 rounded-md bg-warn px-4 text-sm font-medium text-white sm:h-10 sm:min-h-0"
                  >
                    Delete this order for good
                  </button>
                </form>
                <Link
                  href={`/w/${params.orgId}/coordination/po/${po.id}`}
                  className="inline-flex min-h-14 items-center rounded-md border border-border px-4 text-sm font-medium text-text sm:h-10 sm:min-h-0"
                >
                  Keep it
                </Link>
              </div>
            </div>
          ) : (
            <Link
              href={`/w/${params.orgId}/coordination/po/${po.id}?confirmDelete=1`}
              className="inline-flex min-h-14 items-center text-sm text-muted hover:text-warn sm:min-h-0"
            >
              {stuck ? "Delete this draft" : "Delete this order"}
            </Link>
          )}
        </section>
      )}
    </div>
  );
}
