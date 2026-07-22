"use client";

import { useEffect, useState, useTransition } from "react";
import { formatMoney } from "@/lib/crm/stages";
import { formatQty } from "@/lib/estimating/format";
import { EditableField } from "@/components/estimating/EditableField";
import {
  addEstimateDocumentLineItem,
  updateEstimateDocumentLineItem,
  deleteEstimateDocumentLineItem,
  reorderEstimateDocumentLineItems,
} from "@/lib/estimating/actions";
import type { Database } from "@/lib/supabase/database.types";

type LineItem = Database["public"]["Tables"]["estimate_line_items"]["Row"];

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
export function LineItemsEditor({
  orgId,
  estimateId,
  lineItems,
  locked,
}: {
  orgId: string;
  estimateId: string;
  lineItems: LineItem[];
  locked: boolean;
}) {
  const [order, setOrder] = useState<string[]>(lineItems.map((li) => li.id));
  const [dragId, setDragId] = useState<string | null>(null);
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
    const formData = new FormData();
    formData.set("orgId", orgId);
    formData.set("estimateId", estimateId);
    formData.set("description", "");
    formData.set("quantity", "1");
    formData.set("unit_price", "0");
    formData.set("sort_order", String(order.length));
    startTransition(() => {
      addEstimateDocumentLineItem(formData);
    });
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
        <button
          type="button"
          disabled={isPending}
          onClick={handleAdd}
          className="self-start text-sm text-accent-strong hover:underline disabled:opacity-60"
        >
          + Add line item
        </button>
      )}
    </div>
  );
}
