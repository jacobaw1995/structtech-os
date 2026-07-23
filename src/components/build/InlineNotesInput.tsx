"use client";

import { useRef, useTransition } from "react";
import { updateRoadmapItemNotes } from "@/lib/build/actions";

// Auto-submits on blur (not per-keystroke) — matches the row-of-inputs
// feel of the Lead Control Center's inline fields. Submitting an emptied
// input round-trips through the jsonb-patch RPC with notes: "" so clearing
// actually clears (CLAUDE.md migration-discipline: present key means write
// it, not "skip because falsy").
export function InlineNotesInput({
  orgId,
  itemId,
  value,
}: {
  orgId: string;
  itemId: string;
  value: string;
}) {
  const formRef = useRef<HTMLFormElement>(null);
  const [isPending, startTransition] = useTransition();

  return (
    <form ref={formRef} action={updateRoadmapItemNotes}>
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="itemId" value={itemId} />
      <input
        name="notes"
        defaultValue={value}
        placeholder="Notes…"
        disabled={isPending}
        onBlur={(e) => {
          if (e.target.value === value) return;
          startTransition(() => {
            formRef.current?.requestSubmit();
          });
        }}
        className="w-full rounded-md border border-transparent bg-transparent px-2 py-1 text-xs text-text outline-none hover:border-border focus:border-accent focus:bg-bg disabled:opacity-60"
      />
    </form>
  );
}
