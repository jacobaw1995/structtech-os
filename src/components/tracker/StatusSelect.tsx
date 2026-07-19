"use client";

import { useRef, useTransition } from "react";
import { updateTrackerItemStatus } from "@/lib/tracker/actions";
import type { TrackerStatus } from "@/lib/tracker/config";

// Same auto-submit-on-change pattern as crm/StageSelect.tsx.
export function StatusSelect({
  orgId,
  itemId,
  currentStatus,
  statuses,
  returnTo,
}: {
  orgId: string;
  itemId: string;
  currentStatus: string;
  statuses: TrackerStatus[];
  returnTo: string;
}) {
  const formRef = useRef<HTMLFormElement>(null);
  const [isPending, startTransition] = useTransition();

  return (
    <form ref={formRef} action={updateTrackerItemStatus}>
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="itemId" value={itemId} />
      <input type="hidden" name="returnTo" value={returnTo} />
      <select
        name="status"
        defaultValue={currentStatus}
        disabled={isPending}
        onChange={() =>
          startTransition(() => {
            formRef.current?.requestSubmit();
          })
        }
        className="min-h-11 rounded-md border border-border bg-bg px-2 text-sm text-text outline-none focus:border-accent disabled:opacity-60 sm:min-h-0 sm:py-1"
      >
        {statuses.map((s) => (
          <option key={s.key} value={s.key}>
            {s.label}
          </option>
        ))}
      </select>
    </form>
  );
}
