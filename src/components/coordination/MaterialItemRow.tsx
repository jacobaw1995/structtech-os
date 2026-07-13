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
    <div className="flex items-center gap-2 py-1">
      <form
        ref={formRef}
        action={updateMaterialItem}
        className="flex flex-1 items-center gap-2"
      >
        <input type="hidden" name="orgId" value={orgId} />
        <input type="hidden" name="workOrderId" value={workOrderId} />
        <input type="hidden" name="materialItemId" value={item.id} />
        <input
          name="name"
          defaultValue={item.name}
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
          name="ready_by"
          type="date"
          defaultValue={item.ready_by ?? ""}
          disabled={isPending}
          onBlur={submit}
          className="w-36 rounded-md border border-border bg-bg px-1 py-2 text-sm text-text outline-none focus:border-accent disabled:opacity-60"
        />
      </form>
      <form action={deleteMaterialItem}>
        <input type="hidden" name="orgId" value={orgId} />
        <input type="hidden" name="workOrderId" value={workOrderId} />
        <input type="hidden" name="materialItemId" value={item.id} />
        <button
          type="submit"
          aria-label="Remove material"
          className="h-9 w-9 shrink-0 text-muted hover:text-warn"
        >
          ✕
        </button>
      </form>
    </div>
  );
}
