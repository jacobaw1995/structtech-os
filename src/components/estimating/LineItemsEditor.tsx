"use client";

import { useEffect, useState, useTransition } from "react";
import { formatMoney } from "@/lib/crm/stages";
import { formatQty } from "@/lib/estimating/format";
import { formatUnitPrice } from "@/lib/catalog/format";
import { EditableField } from "@/components/estimating/EditableField";
import {
  addEstimateDocumentLineItem,
  updateEstimateDocumentLineItem,
  deleteEstimateDocumentLineItem,
  reorderEstimateDocumentLineItems,
} from "@/lib/estimating/actions";
import type { Database } from "@/lib/supabase/database.types";

type LineItem = Database["public"]["Tables"]["estimate_line_items"]["Row"];
type Product = Database["public"]["Tables"]["products"]["Row"];

// Chunk 3 of the estimate builder rebuild — line items are the one part of
// the document that's more than scalar-field edits: add/delete/reorder are
// row-level actions fired directly (constructed FormData + startTransition,
// same pattern StepSign.tsx already uses for its own non-blur submits),
// while each cell (description/qty/unit/rate) is its own EditableField
// instance for the tap-to-edit behavior.
//
// `order` is local state, not derived straight from props, because drag
// reorder needs an immediate visual response — the useEffect below
// resyncs it from props whenever the server round-trips fresh data (a
// save, a delete, a reorder commit), so nothing can drift permanently out
// of sync with the DB.
// A2.1c — PLACEMENT DECISION, recorded because the controller asked for it and
// because a picker is exactly where a document-as-editor degrades into a form.
//
// CHOSEN: an inline "From catalog" affordance sitting BESIDE the existing
// "+ Add line item", expanding in place into a compact list and collapsing the
// moment an item is chosen. What it produces is an ORDINARY ROW — same cells,
// same EditableFields, same drag handle. The catalog is a way to fill a row in,
// not a different kind of row.
//
// REJECTED, with reasons rather than taste:
//   1. A MODAL / DRAWER catalog browser. The estimate is a document edited in
//      place and presented on a tablet in someone's driveway; a modal is a form
//      stacked on top of a document, and it is worst precisely where this
//      screen matters most. This is the "do not let the picker degrade the
//      document into a form" failure, in its most literal form.
//   2. REPLACING "+ Add line item" with a catalog-only path. SCOPE §2.8 — an
//      item the tenant has never catalogued must stay addable with zero
//      friction. Both paths stay, side by side, neither privileged.
//   3. A <datalist> autocomplete on the description cell. This was the most
//      document-native option and my first instinct. It is rejected on a
//      concrete fact, not a preference: `products` deliberately carries NO
//      unique constraint on (org_id, name) — two suppliers, one product name —
//      so a typed string cannot resolve back to one product_id, unit and price.
//      Resolving by name would either pick arbitrarily or need a disambiguation
//      step, which is rejection 1 again by another route.
export function LineItemsEditor({
  orgId,
  estimateId,
  lineItems,
  catalog,
  canViewFinancials,
  locked,
}: {
  orgId: string;
  estimateId: string;
  lineItems: LineItem[];
  catalog: Product[];
  canViewFinancials: boolean;
  locked: boolean;
}) {
  const [pickerOpen, setPickerOpen] = useState(false);
  // U-W1.2 — the picker had no filter. At BMR's current catalog size that is
  // survivable; at the 60-200 items a real catalog reaches it is a scroll-hunt
  // inside a 16rem-tall box, on a tablet, in front of a homeowner.
  const [pickerQuery, setPickerQuery] = useState("");
  const [order, setOrder] = useState<string[]>(lineItems.map((li) => li.id));
  const [dragId, setDragId] = useState<string | null>(null);

  // U-W1.12 — THE PRICE IS ASKED, NEVER ANSWERED FOR.
  // Controller ruling (2026-09-13): $0 remains a legal price and stops being
  // an ASSUMED one. Before this, "+ Add line item" sent unit_price="0" from
  // the client and a catalog item with no sell price sent `sell ?? 0` — so a
  // line saved at $0 without anyone typing $0, and nothing reported it.
  // Removing add_estimate_line_item's DEFAULT 0 would NOT have caught either:
  // both paths sent the zero explicitly. The default lived in this file.
  //
  // `draft` is the add form. It is correct against the RPC both before and
  // after Track S's narrowing: a required field in the UI does not depend on
  // the server refusing an empty one.
  type Draft = {
    description: string;
    unit: string;
    productId: string | null;
    unitPrice: string;
    /** Why the form opened instead of the line simply being added. */
    reason: string | null;
  };
  const [draft, setDraft] = useState<Draft | null>(null);
  const [draftError, setDraftError] = useState<string | null>(null);

  const pickerNeedle = pickerQuery.trim().toLowerCase();
  const pickerResults = pickerNeedle
    ? catalog.filter((p) =>
        [p.name, p.category, p.unit]
          .filter((v): v is string => Boolean(v))
          .some((v) => v.toLowerCase().includes(pickerNeedle))
      )
    : catalog;
  const [isPending, startTransition] = useTransition();

  useEffect(() => {
    setOrder(lineItems.map((li) => li.id));
  }, [lineItems]);

  const byId = new Map(lineItems.map((li) => [li.id, li]));
  const ordered = order.map((id) => byId.get(id)).filter((li): li is LineItem => !!li);

  function commitOrder(next: string[]) {
    setOrder(next);
    const formData = new FormData();
    formData.set("orgId", orgId);
    formData.set("estimateId", estimateId);
    formData.set("orderedIds", JSON.stringify(next));
    startTransition(() => {
      reorderEstimateDocumentLineItems(formData);
    });
  }

  function move(id: string, direction: -1 | 1) {
    const i = order.indexOf(id);
    const j = i + direction;
    if (i < 0 || j < 0 || j >= order.length) return;
    const next = [...order];
    [next[i], next[j]] = [next[j], next[i]];
    commitOrder(next);
  }

  function handleDrop(targetId: string) {
    if (!dragId || dragId === targetId) return;
    const next = [...order];
    const from = next.indexOf(dragId);
    const to = next.indexOf(targetId);
    next.splice(from, 1);
    next.splice(to, 0, dragId);
    setDragId(null);
    commitOrder(next);
  }

  function handleAdd() {
    setPickerOpen(false);
    setDraftError(null);
    setDraft({ description: "", unit: "", productId: null, unitPrice: "", reason: null });
  }

  function submitLine(values: {
    description: string;
    unitPrice: number;
    productId: string | null;
    unit: string | null;
  }) {
    const formData = new FormData();
    formData.set("orgId", orgId);
    formData.set("estimateId", estimateId);
    formData.set("description", values.description);
    // Quantity is unchanged by this ruling, which names unit_price only. It is
    // still sent as 1 and still editable on the row — reported as the next
    // same-class default, not changed here.
    formData.set("quantity", "1");
    formData.set("unit_price", String(values.unitPrice));
    if (values.productId) formData.set("product_id", values.productId);
    if (values.unit) formData.set("unit", values.unit);
    formData.set("sort_order", String(order.length));
    startTransition(() => {
      addEstimateDocumentLineItem(formData);
    });
  }

  // A catalog pick sends the product's id ALONGSIDE the values read off it.
  // The values are what the line stores; the id is provenance only. Nothing
  // downstream re-reads a price through it — see addEstimateDocumentLineItem.
  //
  // A sell price someone SET on the catalog is a real value, shown next to the
  // item in the picker, so it is used. A catalog item with NO sell price used
  // to be added at $0 (`sell ?? 0`). It now opens the add form with the name
  // and unit filled in and the price empty, and says why.
  function handleAddFromCatalog(product: Product) {
    setPickerOpen(false);
    const sell = product.sell === null || product.sell === undefined ? null : Number(product.sell);
    if (sell !== null && Number.isFinite(sell)) {
      submitLine({ description: product.name, unitPrice: sell, productId: product.id, unit: product.unit });
      return;
    }
    setDraftError(null);
    setDraft({
      description: product.name,
      unit: product.unit ?? "",
      productId: product.id,
      unitPrice: "",
      reason: canViewFinancials
        ? "This catalog item has no sell price set, so enter the price for this line."
        : "Prices are not visible to your role, so this catalog item cannot fill one in. Enter the price for this line.",
    });
  }

  function submitDraft(e: React.FormEvent) {
    e.preventDefault();
    if (!draft) return;
    const raw = draft.unitPrice.trim();
    // NAMED CAUSES, one per failure. Never "something went wrong", and never a
    // message that guesses: an empty field is reported as empty, not as zero.
    if (raw === "") {
      setDraftError("enter a unit price for this line — 0 is allowed for a free line, but it has to be entered");
      return;
    }
    const n = Number(raw);
    if (!Number.isFinite(n)) {
      setDraftError(`“${raw}” isn’t a price. Enter a number, such as 19.20.`);
      return;
    }
    if (n < 0) {
      setDraftError("A unit price can’t be negative.");
      return;
    }
    submitLine({
      description: draft.description,
      unitPrice: n,
      productId: draft.productId,
      unit: draft.unit.trim() || null,
    });
    setDraft(null);
    setDraftError(null);
  }

  function handleDelete(id: string) {
    const formData = new FormData();
    formData.set("orgId", orgId);
    formData.set("estimateId", estimateId);
    formData.set("lineItemId", id);
    startTransition(() => {
      deleteEstimateDocumentLineItem(formData);
    });
  }

  const hidden = (item: LineItem) => ({
    orgId,
    estimateId,
    lineItemId: item.id,
  });

  return (
    <div className="flex flex-col gap-2">
      <p className="text-[10px] font-semibold uppercase tracking-wide text-muted">Line items</p>

      {ordered.length === 0 && (
        <p className="rounded-lg bg-surface2 p-3 text-sm text-muted">No line items yet.</p>
      )}

      {ordered.length > 0 && (
        <>
          {/* Table on tablet+/desktop */}
          <div className="hidden overflow-x-auto rounded-lg border border-border sm:block">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border bg-surface2 text-left text-xs uppercase tracking-wide text-muted">
                  {!locked && <th className="w-8 px-2 py-2" />}
                  <th className="px-3 py-2 font-medium">Description</th>
                  <th className="px-3 py-2 text-right font-medium">Qty</th>
                  <th className="px-3 py-2 text-right font-medium">Unit</th>
                  <th className="px-3 py-2 text-right font-medium">Rate</th>
                  <th className="px-3 py-2 text-right font-medium">Total</th>
                  {!locked && <th className="w-8 px-2 py-2" />}
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {ordered.map((item) => (
                  <tr
                    key={item.id}
                    className="group"
                    draggable={!locked}
                    onDragStart={() => setDragId(item.id)}
                    onDragOver={(e) => e.preventDefault()}
                    onDrop={() => handleDrop(item.id)}
                  >
                    {!locked && (
                      <td className="px-2 py-2 align-top">
                        <div className="flex flex-col items-center gap-0.5 opacity-0 group-hover:opacity-100">
                          <button
                            type="button"
                            aria-label="Move up"
                            onClick={() => move(item.id, -1)}
                            className="text-muted hover:text-text"
                          >
                            ▲
                          </button>
                          <span className="cursor-grab text-muted" aria-label="Drag to reorder">
                            ⠿
                          </span>
                          <button
                            type="button"
                            aria-label="Move down"
                            onClick={() => move(item.id, 1)}
                            className="text-muted hover:text-text"
                          >
                            ▼
                          </button>
                        </div>
                      </td>
                    )}
                    <td className="px-3 py-2 text-text">
                      <EditableField
                        key={`desc-${item.id}-${item.description}`}
                        value={item.description}
                        placeholder="Description"
                        action={updateEstimateDocumentLineItem}
                        hidden={hidden(item)}
                        name="description"
                        type="textarea"
                        locked={locked}
                        block
                      />
                    </td>
                    <td className="px-3 py-2 text-right font-mono text-text">
                      <EditableField
                        key={`qty-${item.id}-${item.quantity}`}
                        value={String(item.quantity ?? "")}
                        display={formatQty(item.quantity)}
                        action={updateEstimateDocumentLineItem}
                        hidden={hidden(item)}
                        name="quantity"
                        type="number"
                        align="right"
                        locked={locked}
                      />
                    </td>
                    <td className="px-3 py-2 text-right font-mono text-muted">
                      <EditableField
                        key={`unit-${item.id}-${item.unit}`}
                        value={item.unit ?? ""}
                        display={item.unit || "—"}
                        placeholder="unit"
                        action={updateEstimateDocumentLineItem}
                        hidden={hidden(item)}
                        name="unit"
                        align="right"
                        locked={locked}
                      />
                    </td>
                    <td className="px-3 py-2 text-right font-mono text-text">
                      <EditableField
                        key={`price-${item.id}-${item.unit_price}`}
                        value={String(item.unit_price ?? "")}
                        display={formatMoney(item.unit_price)}
                        action={updateEstimateDocumentLineItem}
                        hidden={hidden(item)}
                        name="unit_price"
                        type="number"
                        align="right"
                        locked={locked}
                        // Advisory-only unpriced marker (SCOPE §2.8) — editor
                        // view only, never shown once locked (the row itself
                        // already renders in plain text at that point via
                        // EditableField's own locked branch).
                        className={!locked && item.unit_price === 0 ? "text-warn" : undefined}
                      />
                    </td>
                    <td className="px-3 py-2 text-right font-mono text-text">
                      {formatMoney(item.line_total)}
                    </td>
                    {!locked && (
                      <td className="px-2 py-2 text-center opacity-0 group-hover:opacity-100">
                        <button
                          type="button"
                          aria-label="Delete line item"
                          onClick={() => handleDelete(item.id)}
                          className="text-muted hover:text-warn"
                        >
                          ✕
                        </button>
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Stacked cards on phone */}
          <div className="flex flex-col divide-y divide-border rounded-lg border border-border sm:hidden">
            {ordered.map((item) => (
              <div key={item.id} className="flex flex-col gap-1 p-3">
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0 flex-1">
                    <EditableField
                      key={`desc-m-${item.id}-${item.description}`}
                      value={item.description}
                      placeholder="Description"
                      action={updateEstimateDocumentLineItem}
                      hidden={hidden(item)}
                      name="description"
                      type="textarea"
                      locked={locked}
                      className="text-sm text-text"
                      block
                    />
                  </div>
                  <span className="font-mono text-sm text-text">
                    {formatMoney(item.line_total)}
                  </span>
                </div>
                <div className="flex items-center gap-2 font-mono text-xs text-muted">
                  <EditableField
                    key={`qty-m-${item.id}-${item.quantity}`}
                    value={String(item.quantity ?? "")}
                    display={formatQty(item.quantity)}
                    action={updateEstimateDocumentLineItem}
                    hidden={hidden(item)}
                    name="quantity"
                    type="number"
                    locked={locked}
                    className="w-8"
                  />
                  <EditableField
                    key={`unit-m-${item.id}-${item.unit}`}
                    value={item.unit ?? ""}
                    display={item.unit || "unit"}
                    placeholder="unit"
                    action={updateEstimateDocumentLineItem}
                    hidden={hidden(item)}
                    name="unit"
                    locked={locked}
                    className="w-12"
                  />
                  <span>×</span>
                  <EditableField
                    key={`price-m-${item.id}-${item.unit_price}`}
                    value={String(item.unit_price ?? "")}
                    display={formatMoney(item.unit_price)}
                    action={updateEstimateDocumentLineItem}
                    hidden={hidden(item)}
                    name="unit_price"
                    type="number"
                    locked={locked}
                    className={`w-16 ${!locked && item.unit_price === 0 ? "text-warn" : ""}`}
                  />
                  {!locked && (
                    <div className="ml-auto flex items-center gap-3">
                      <button
                        type="button"
                        aria-label="Move up"
                        onClick={() => move(item.id, -1)}
                        className="flex h-8 w-8 items-center justify-center text-muted"
                      >
                        ▲
                      </button>
                      <button
                        type="button"
                        aria-label="Move down"
                        onClick={() => move(item.id, 1)}
                        className="flex h-8 w-8 items-center justify-center text-muted"
                      >
                        ▼
                      </button>
                      <button
                        type="button"
                        aria-label="Delete line item"
                        onClick={() => handleDelete(item.id)}
                        className="flex h-8 w-8 items-center justify-center text-muted"
                      >
                        ✕
                      </button>
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        </>
      )}

      {!locked && (
        <div className="flex flex-col gap-2">
          {/* U-W1.2 — both of these were bare text links with no height. They
              are the two most-tapped controls in the estimate builder and they
              are tapped on a driveway tablet, so they are 56dp targets below
              sm now (SCOPE §2.4). Neither is ever disabled by the other's
              state (§2.8); `isPending` only guards a request already in
              flight. */}
          <div className="flex flex-wrap items-center gap-2">
            <button
              type="button"
              disabled={isPending}
              onClick={handleAdd}
              className="min-h-14 flex-1 rounded-md border border-accent px-4 text-sm font-medium text-accent-strong disabled:opacity-60 sm:min-h-0 sm:h-10 sm:flex-initial"
            >
              + Add line item
            </button>
            {/* Offered only when there is a catalog to offer. An empty
                catalog gets no dead control — and no nagging either: the
                blank-row path above is untouched and always available. */}
            {catalog.length > 0 && (
              <button
                type="button"
                disabled={isPending}
                onClick={() => setPickerOpen((v) => !v)}
                className="min-h-14 flex-1 rounded-md border border-border px-4 text-sm text-text disabled:opacity-60 sm:min-h-0 sm:h-10 sm:flex-initial"
              >
                {pickerOpen ? "Close catalog" : "From catalog"}
              </button>
            )}
          </div>

          {draft && (
            <form
              onSubmit={submitDraft}
              noValidate
              className="flex flex-col gap-3 rounded-lg border border-accent bg-surface p-3"
            >
              <p className="text-sm font-semibold text-text">New line</p>
              {draft.reason && <p className="text-xs leading-relaxed text-muted">{draft.reason}</p>}
              <div className="flex flex-col gap-2 sm:flex-row sm:items-end">
                <label className="flex min-w-0 flex-1 flex-col gap-1">
                  <span className="text-[11px] font-medium uppercase tracking-wide text-muted">
                    Description
                  </span>
                  <input
                    value={draft.description}
                    onChange={(e) => setDraft({ ...draft, description: e.target.value })}
                    placeholder="What is this line?"
                    className="min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent sm:h-10 sm:min-h-0 sm:text-sm"
                  />
                </label>
                <label className="flex flex-col gap-1">
                  <span className="text-[11px] font-medium uppercase tracking-wide text-muted">
                    Unit price <span className="text-[var(--warn-strong)]">· required</span>
                  </span>
                  {/* No defaultValue, on purpose. An empty box that must be
                      filled is how a user is ASKED; a box pre-filled with 0 is
                      how they are answered for. Money in the sans face with
                      tabular-nums (decision 1.1). */}
                  <input
                    value={draft.unitPrice}
                    onChange={(e) => {
                      setDraft({ ...draft, unitPrice: e.target.value });
                      if (draftError) setDraftError(null);
                    }}
                    type="number"
                    inputMode="decimal"
                    step="0.01"
                    min="0"
                    required
                    autoFocus
                    aria-invalid={draftError ? true : undefined}
                    aria-describedby={draftError ? "draft-price-error" : undefined}
                    placeholder="e.g. 19.20"
                    className="min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base tabular-nums text-text outline-none focus:border-accent sm:h-10 sm:w-32 sm:min-h-0 sm:text-sm"
                  />
                </label>
              </div>
              {draftError && (
                <p id="draft-price-error" role="alert" className="text-sm text-[var(--warn-strong)]">
                  {draftError}
                </p>
              )}
              <div className="flex flex-wrap gap-2">
                <button
                  type="submit"
                  disabled={isPending}
                  className="min-h-14 rounded-md bg-accent-strong px-4 text-sm font-medium text-white disabled:opacity-60 sm:h-10 sm:min-h-0"
                >
                  Add line
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setDraft(null);
                    setDraftError(null);
                  }}
                  className="min-h-14 rounded-md border border-border px-4 text-sm text-text sm:h-10 sm:min-h-0"
                >
                  Cancel
                </button>
              </div>
            </form>
          )}

          {pickerOpen && (
            <div className="rounded-lg border border-border bg-surface">
              <div className="border-b border-border p-2">
                <input
                  type="search"
                  value={pickerQuery}
                  onChange={(e) => setPickerQuery(e.target.value)}
                  placeholder="Filter catalog…"
                  aria-label="Filter catalog items"
                  autoFocus
                  className="min-h-14 w-full rounded-md border border-border bg-bg px-3 text-base text-text outline-none placeholder:text-muted focus:border-accent sm:min-h-0 sm:h-9 sm:text-sm"
                />
              </div>
              <div className="max-h-72 overflow-y-auto">
                {pickerResults.length === 0 ? (
                  <p className="px-3 py-4 text-sm text-muted">
                    No catalog item matches “{pickerQuery}”. You can still add a blank
                    line and type it in.
                  </p>
                ) : (
                  pickerResults.map((product) => (
                    <button
                      key={product.id}
                      type="button"
                      disabled={isPending}
                      onClick={() => handleAddFromCatalog(product)}
                      className="flex min-h-14 w-full items-center justify-between gap-4 border-b border-border px-3 py-2 text-left last:border-0 hover:bg-surface2 disabled:opacity-60"
                    >
                      <span className="flex min-w-0 flex-col">
                        <span className="truncate text-sm text-text">{product.name}</span>
                        <span className="text-xs text-muted">
                          {[product.category, product.unit].filter(Boolean).join(" · ") || "—"}
                        </span>
                      </span>
                      {/* Prices are absent, not blanked, for a caller without
                          financials — list_products() already nulled them, and the
                          picker simply has nothing to show. formatUnitPrice, not
                          formatMoney: this is the SAME number the catalog page
                          shows, and formatMoney rounds a $19.20/lf item to $19.
                          The two surfaces disagreeing about one product's price
                          is worse than either being wrong alone. */}
                      {canViewFinancials && (
                        <span className="shrink-0 tabular-nums text-sm text-text">
                          {formatUnitPrice(product.sell) ?? "—"}
                        </span>
                      )}
                    </button>
                  ))
                )}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
