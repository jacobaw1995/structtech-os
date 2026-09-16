"use client";

import { useRef, useTransition } from "react";
import {
  updateProductionPacketCallout,
  deleteProductionPacketCallout,
} from "@/lib/field/actions";
import type { Callout } from "@/lib/field/callouts";
import { TwoTapDelete } from "@/components/field/TwoTapDelete";

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
    // U-W1.16 — stacked, not side by side: at 375px the ✕ was 44x44 beside the
    // inputs and deleted on one tap. Now the inputs are 56dp and full width,
    // and deleting asks first.
    <div className="flex flex-col gap-2 border-b border-border py-2 last:border-0 group-data-[outdoor=true]/field:border-white/30">
      <span className="text-sm font-medium text-muted group-data-[outdoor=true]/field:text-white/80">
        {index + 1}.
      </span>
      <form
        ref={formRef}
        action={updateProductionPacketCallout}
        className="flex flex-col gap-2"
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
          className="min-h-14 rounded-lg border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent disabled:opacity-60 group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
        />
        <input
          name="detail"
          defaultValue={callout.detail ?? ""}
          disabled={isPending}
          onBlur={submit}
          placeholder="Detail (optional)"
          className="min-h-14 rounded-lg border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent disabled:opacity-60 group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
        />
      </form>
      <TwoTapDelete
        action={deleteProductionPacketCallout}
        fields={{ orgId, workOrderId, productionPacketId, calloutId: callout.id }}
        label="Remove"
        ariaLabel={`Remove callout ${index + 1}`}
        question={`Remove callout ${index + 1}${callout.label ? `, "${callout.label}"` : ""}?`}
        confirmLabel="Remove"
      />
    </div>
  );
}
