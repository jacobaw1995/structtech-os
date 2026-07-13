"use client";

import { useRef, useTransition } from "react";
import {
  updateProductionPacketCallout,
  deleteProductionPacketCallout,
} from "@/lib/field/actions";
import type { Callout } from "@/lib/field/callouts";

// Same auto-submit-on-blur pattern as coordination's MaterialItemRow.
// Wireframe 3a shows callouts as a numbered read display ("① Skylight
// flash — copper") — this is the editable form of that same list.
export function CalloutRow({
  orgId,
  workOrderId,
  productionPacketId,
  callout,
  index,
}: {
  orgId: string;
  workOrderId: string;
  productionPacketId: string;
  callout: Callout;
  index: number;
}) {
  const formRef = useRef<HTMLFormElement>(null);
  const [isPending, startTransition] = useTransition();

  function submit() {
    startTransition(() => {
      formRef.current?.requestSubmit();
    });
  }

  return (
    <div className="flex items-start gap-2 py-1">
      <span className="mt-3 text-sm text-muted group-data-[outdoor=true]/field:text-white/60">
        {index + 1}.
      </span>
      <form
        ref={formRef}
        action={updateProductionPacketCallout}
        className="flex flex-1 flex-col gap-2"
      >
        <input type="hidden" name="orgId" value={orgId} />
        <input type="hidden" name="workOrderId" value={workOrderId} />
        <input type="hidden" name="productionPacketId" value={productionPacketId} />
        <input type="hidden" name="calloutId" value={callout.id} />
        <input
          name="label"
          defaultValue={callout.label}
          disabled={isPending}
          onBlur={submit}
          placeholder="Skylight flash — copper"
          className="min-h-12 rounded-lg border border-border bg-bg px-3 text-sm text-text outline-none focus:border-accent disabled:opacity-60 group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
        />
        <input
          name="detail"
          defaultValue={callout.detail ?? ""}
          disabled={isPending}
          onBlur={submit}
          placeholder="Detail (optional)"
          className="min-h-12 rounded-lg border border-border bg-bg px-3 text-sm text-text outline-none focus:border-accent disabled:opacity-60 group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
        />
      </form>
      <form action={deleteProductionPacketCallout}>
        <input type="hidden" name="orgId" value={orgId} />
        <input type="hidden" name="workOrderId" value={workOrderId} />
        <input type="hidden" name="productionPacketId" value={productionPacketId} />
        <input type="hidden" name="calloutId" value={callout.id} />
        <button
          type="submit"
          aria-label="Remove callout"
          className="flex min-h-11 min-w-11 items-center justify-center text-muted hover:text-warn"
        >
          ✕
        </button>
      </form>
    </div>
  );
}
