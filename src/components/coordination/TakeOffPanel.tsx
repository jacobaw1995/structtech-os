"use client";

import { useState } from "react";
import { generateTakeOff } from "@/lib/coordination/actions";

export type TakeOffLine = {
  id: string;
  description: string;
  quantity: number;
  unit: string | null;
  // Whether this line already produced a material on THIS trade. Comes from
  // material_items.estimate_line_item_id, the provenance column A2.2 added —
  // without it the page cannot tell a re-run from a first run, which is the
  // same "a guard needs an identity to key on" problem the unique index solves
  // one layer down.
  alreadyTakenOff: boolean;
};

// A2.2 — the trade-side take-off. Deliberately NO money on this panel: a
// take-off carries description, quantity, unit and product across, and
// material_items has no cost, sell or unit-price column to carry one into.
export function TakeOffPanel({
  orgId,
  workOrderId,
  lines,
}: {
  orgId: string;
  workOrderId: string;
  lines: TakeOffLine[];
}) {
  // Pre-ticked to everything not already taken off — the common action is
  // "bring the rest of this estimate onto this trade", and a re-run therefore
  // starts with nothing ticked rather than looking like it wants to duplicate.
  const [selected, setSelected] = useState<Set<string>>(
    () => new Set(lines.filter((l) => !l.alreadyTakenOff).map((l) => l.id))
  );
  const [open, setOpen] = useState(false);

  function toggle(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  const remaining = lines.filter((l) => !l.alreadyTakenOff).length;

  return (
    <div className="border-t border-border pt-2">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="flex min-h-11 w-full items-center justify-between gap-2 text-left text-sm font-medium text-accent-strong"
      >
        <span>Take-off from estimate</span>
        <span className="text-xs font-normal text-muted">
          {remaining === 0
            ? `all ${lines.length} lines taken off`
            : `${remaining} of ${lines.length} lines not yet taken off`}
          {" · "}
          {open ? "hide" : "show"}
        </span>
      </button>

      {open && (
        <form action={generateTakeOff} className="mt-2 flex flex-col gap-1">
          <input type="hidden" name="orgId" value={orgId} />
          <input type="hidden" name="workOrderId" value={workOrderId} />

          {lines.map((line) => (
            <label
              key={line.id}
              className="flex min-h-11 items-center gap-3 rounded-md px-1 py-1 hover:bg-surface2"
            >
              <input
                type="checkbox"
                name="lineItemId"
                value={line.id}
                checked={selected.has(line.id)}
                onChange={() => toggle(line.id)}
                className="h-5 w-5 shrink-0 accent-[oklch(0.42_0.16_250)]"
              />
              <span className="min-w-0 flex-1 truncate text-sm text-text">
                {line.description}
              </span>
              <span className="shrink-0 font-mono text-xs text-muted">
                {line.quantity}
                {line.unit ? ` ${line.unit}` : ""}
              </span>
              {line.alreadyTakenOff && (
                <span className="shrink-0 rounded-full bg-surface2 px-2 py-0.5 text-xs text-muted">
                  on this trade
                </span>
              )}
            </label>
          ))}

          {/* Never disabled (SCOPE §2.8). Submitting an empty selection is a
              case the RPC answers by name — "no estimate line items were
              selected" — rather than a control that silently does nothing. */}
          <button
            type="submit"
            className="mt-1 flex min-h-11 items-center justify-center rounded-lg bg-accent-strong px-4 text-sm font-medium text-white"
          >
            Generate take-off ({selected.size} selected)
          </button>
        </form>
      )}
    </div>
  );
}
