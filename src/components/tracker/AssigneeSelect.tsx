"use client";

import { useRef, useTransition } from "react";
import { updateTrackerItemAssignee } from "@/lib/tracker/actions";

// Same auto-submit-on-change pattern as crm/lead-control-center/OwnerSelect.tsx.
export function AssigneeSelect({
  orgId,
  itemId,
  currentAssigneeId,
  members,
  returnTo,
}: {
  orgId: string;
  itemId: string;
  currentAssigneeId: string | null;
  members: { user_id: string; full_name: string | null }[];
  returnTo: string;
}) {
  const formRef = useRef<HTMLFormElement>(null);
  const [isPending, startTransition] = useTransition();

  return (
    <form ref={formRef} action={updateTrackerItemAssignee}>
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="itemId" value={itemId} />
      <input type="hidden" name="returnTo" value={returnTo} />
      <select
        name="assignee_id"
        defaultValue={currentAssigneeId ?? ""}
        disabled={isPending}
        onChange={() =>
          startTransition(() => {
            formRef.current?.requestSubmit();
          })
        }
        className="min-h-11 w-full rounded-md border border-border bg-bg px-2 text-sm text-text outline-none focus:border-accent disabled:opacity-60 sm:min-h-0 sm:py-1.5"
      >
        <option value="">Unassigned</option>
        {members.map((m) => (
          <option key={m.user_id} value={m.user_id}>
            {m.full_name ?? m.user_id}
          </option>
        ))}
      </select>
    </form>
  );
}
