"use client";

import { useRef, useTransition } from "react";
import { updateMaterialItem, deleteMaterialItem } from "@/lib/coordination/actions";
import type { Database } from "@/lib/supabase/database.types";

type MaterialItem = Database["public"]["Tables"]["material_items"]["Row"];

// Same auto-submit-on-blur pattern as estimating's LineItemRow.
export function MaterialItemRow({
  orgId,
  workOrderId,
  item,
}: {
  orgId: string;
  workOrderId: string;
  item: MaterialItem;
}) {
  const formRef = useRef<HTMLFormElement>(null);
  const [isPending, startTransition] = useTransition();

  function submit() {
    startTransition(() => {
      formRef.current?.requestSubmit();
    });
  }

  return (
    // Mobile: name gets its own full-width row (w-full forces the wrap),
    // qty+ready_by share a second row, delete sits on its own row —
    // fixing the phone-test complaint where all four fields jammed onto
    // one line and squeezed name to unreadable width. sm:contents on the
    // qty/date wrapper removes it from the box tree at desktop size so
    // those two inputs fall back to being direct flex children of the
    // form, reproducing the original single-line desktop layout exactly.
    <div className="flex flex-col gap-2 border-b border-border py-2 last:border-b-0 sm:flex-row sm:items-center sm:gap-2 sm:border-none sm:py-1">
      <form
        ref={formRef}
        action={updateMaterialItem}
        className="flex flex-1 flex-col gap-2 sm:flex-row sm:items-center"
      >
        <input type="hidden" name="orgId" value={orgId} />
        <input type="hidden" name="workOrderId" value={workOrderId} />
        <input type="hidden" name="materialItemId" value={item.id} />
        <input
          name="name"
          defaultValue={item.name}
          disabled={isPending}
          onBlur={submit}
          className="min-h-14 w-full min-w-0 rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent disabled:opacity-60 sm:min-h-0 sm:flex-1 sm:py-2 sm:text-sm"
        />
        <div className="flex items-center gap-2 sm:contents">
          <input
            name="quantity"
            type="number"
            step="any"
            defaultValue={item.quantity}
            disabled={isPending}
            onBlur={submit}
            className="min-h-14 w-24 rounded-md border border-border bg-bg px-1 text-right font-mono text-base text-text outline-none focus:border-accent disabled:opacity-60 sm:min-h-0 sm:w-14 sm:py-2 sm:text-sm"
          />
          <input
            name="ready_by"
            type="date"
            defaultValue={item.ready_by ?? ""}
            disabled={isPending}
            onBlur={submit}
            className="min-h-14 flex-1 rounded-md border border-border bg-bg px-1 text-base text-text outline-none focus:border-accent disabled:opacity-60 sm:min-h-0 sm:w-36 sm:flex-none sm:py-2 sm:text-sm"
          />
        </div>
      </form>
      <form action={deleteMaterialItem} className="self-end sm:self-auto">
        <input type="hidden" name="orgId" value={orgId} />
        <input type="hidden" name="workOrderId" value={workOrderId} />
        <input type="hidden" name="materialItemId" value={item.id} />
        <button
          type="submit"
          aria-label="Remove material"
          className="flex h-14 w-14 shrink-0 items-center justify-center text-muted hover:text-warn sm:h-9 sm:w-9"
        >
          ✕
        </button>
      </form>
    </div>
  );
}
