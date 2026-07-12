"use client";

import { useRef, useTransition } from "react";
import {
  updateEstimateLineItem,
  deleteEstimateLineItem,
} from "@/lib/estimating/actions";
import type { Database } from "@/lib/supabase/database.types";

type LineItem = Database["public"]["Tables"]["estimate_line_items"]["Row"];

// Same auto-submit-on-interaction pattern as StageSelect
// (src/components/crm/StageSelect.tsx): inline inputs, no separate "edit
// mode" toggle. Submits on blur (not onChange) so it fires once per edit,
// not once per keystroke.
export function LineItemRow({
  orgId,
  estimateId,
  item,
  locked,
}: {
  orgId: string;
  estimateId: string;
  item: LineItem;
  locked: boolean;
}) {
  const formRef = useRef<HTMLFormElement>(null);
  const [isPending, startTransition] = useTransition();

  function submit() {
    startTransition(() => {
      formRef.current?.requestSubmit();
    });
  }

  if (locked) {
    return (
      <div className="flex items-center justify-between gap-2 py-1.5 text-sm text-text group-data-[outdoor=true]/flow:text-white">
        <span className="flex-1 truncate">{item.description}</span>
        <span className="font-mono text-xs text-muted group-data-[outdoor=true]/flow:text-white/60">
          {item.quantity} × {item.unit_price}
        </span>
        <span className="w-16 text-right font-mono">{item.line_total}</span>
      </div>
    );
  }

  return (
    <div className="flex items-center gap-2 py-1">
      <form
        ref={formRef}
        action={updateEstimateLineItem}
        className="flex flex-1 items-center gap-2"
      >
        <input type="hidden" name="orgId" value={orgId} />
        <input type="hidden" name="estimateId" value={estimateId} />
        <input type="hidden" name="lineItemId" value={item.id} />
        <input
          name="description"
          defaultValue={item.description}
          disabled={isPending}
          onBlur={submit}
          className="min-w-0 flex-1 rounded-md border border-border bg-bg px-2 py-2 text-sm text-text outline-none focus:border-accent disabled:opacity-60"
        />
        <input
          name="quantity"
          type="number"
          step="any"
          defaultValue={item.quantity}
          disabled={isPending}
          onBlur={submit}
          className="w-14 rounded-md border border-border bg-bg px-1 py-2 text-right font-mono text-sm text-text outline-none focus:border-accent disabled:opacity-60"
        />
        <input
          name="unit_price"
          type="number"
          step="any"
          defaultValue={item.unit_price}
          disabled={isPending}
          onBlur={submit}
          className="w-20 rounded-md border border-border bg-bg px-1 py-2 text-right font-mono text-sm text-text outline-none focus:border-accent disabled:opacity-60"
        />
      </form>
      <form action={deleteEstimateLineItem}>
        <input type="hidden" name="orgId" value={orgId} />
        <input type="hidden" name="estimateId" value={estimateId} />
        <input type="hidden" name="lineItemId" value={item.id} />
        <button
          type="submit"
          aria-label="Remove line item"
          className="h-9 w-9 shrink-0 text-muted hover:text-warn"
        >
          ✕
        </button>
      </form>
    </div>
  );
}
