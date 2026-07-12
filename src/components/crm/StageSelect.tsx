"use client";

import { useRef, useTransition } from "react";
import { updateDealStage } from "@/lib/crm/actions";
import type { CrmStage } from "@/lib/crm/stages";

// Small client island (same pattern as WorkspaceShell's tenant switcher) —
// everything else on this page is a server component. Auto-submits on
// change so "stage dropdown" behaves like a dropdown, not a
// select-then-hunt-for-a-save-button form.
export function StageSelect({
  orgId,
  dealId,
  currentStage,
  stages,
}: {
  orgId: string;
  dealId: string;
  currentStage: string;
  stages: CrmStage[];
}) {
  const formRef = useRef<HTMLFormElement>(null);
  const [isPending, startTransition] = useTransition();

  return (
    <form ref={formRef} action={updateDealStage}>
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="dealId" value={dealId} />
      <select
        name="stage"
        defaultValue={currentStage}
        disabled={isPending}
        onChange={() =>
          startTransition(() => {
            formRef.current?.requestSubmit();
          })
        }
        className="rounded-md border border-border bg-bg px-2 py-1 text-sm text-text outline-none focus:border-accent disabled:opacity-60"
      >
        {stages.map((s) => (
          <option key={s.key} value={s.key}>
            {s.label}
          </option>
        ))}
      </select>
    </form>
  );
}
