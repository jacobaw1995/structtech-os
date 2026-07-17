"use client";

import { useRef, useState, useTransition } from "react";
import { updateDealTags } from "@/lib/crm/actions";

// Chips are read-only display; tapping "Edit" swaps to a comma-separated
// text input (same idle/edit toggle idea as ChecklistFieldRow, kept
// separate since tags aren't part of any command-stage checklist).
export function TagsEditor({ orgId, dealId, stage, tags }: { orgId: string; dealId: string; stage: string; tags: string[] }) {
  const [isEditing, setIsEditing] = useState(false);
  const formRef = useRef<HTMLFormElement>(null);
  const [isPending, startTransition] = useTransition();

  if (!isEditing) {
    return (
      <button type="button" onClick={() => setIsEditing(true)} className="flex min-h-14 w-full flex-wrap items-center gap-1.5 text-left sm:min-h-0">
        {tags.length === 0 ? (
          <span className="text-sm text-muted">Tap to add tags</span>
        ) : (
          tags.map((tag) => (
            <span key={tag} className="rounded-full bg-surface2 px-2 py-0.5 text-xs font-medium text-muted">
              {tag}
            </span>
          ))
        )}
      </button>
    );
  }

  return (
    <form
      ref={formRef}
      action={updateDealTags}
      onSubmit={() => setIsEditing(false)}
      className="flex flex-col gap-1"
    >
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="dealId" value={dealId} />
      <input type="hidden" name="stage" value={stage} />
      <input
        name="tags"
        autoFocus
        disabled={isPending}
        defaultValue={tags.join(", ")}
        placeholder="Comma-separated, e.g. Homeowner, Remodel"
        onBlur={() =>
          startTransition(() => {
            formRef.current?.requestSubmit();
          })
        }
        className="min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent disabled:opacity-60 sm:min-h-0 sm:py-1.5 sm:text-sm"
      />
    </form>
  );
}
