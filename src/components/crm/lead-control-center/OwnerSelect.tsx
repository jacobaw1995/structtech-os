"use client";

import { useRef, useTransition } from "react";
import { updateDealOwner } from "@/lib/crm/actions";

// Same auto-submit-on-change pattern as StageSelect.tsx.
export function OwnerSelect({
  orgId,
  dealId,
  stage,
  currentOwnerId,
  members,
}: {
  orgId: string;
  dealId: string;
  stage: string;
  currentOwnerId: string | null;
  members: { user_id: string; full_name: string | null }[];
}) {
  const formRef = useRef<HTMLFormElement>(null);
  const [isPending, startTransition] = useTransition();

  return (
    <form ref={formRef} action={updateDealOwner}>
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="dealId" value={dealId} />
      <input type="hidden" name="stage" value={stage} />
      <select
        name="owner_id"
        defaultValue={currentOwnerId ?? ""}
        disabled={isPending}
        onChange={() =>
          startTransition(() => {
            formRef.current?.requestSubmit();
          })
        }
        className="min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent disabled:opacity-60 sm:min-h-0 sm:py-1.5 sm:text-sm"
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
