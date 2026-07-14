"use client";

import { useRef, useTransition } from "react";
import { updateScheduleBlock, deleteScheduleBlock } from "@/lib/coordination/actions";
import { formatDateOnly } from "@/lib/coordination/stage";
import type { Database } from "@/lib/supabase/database.types";

type ScheduleBlock = Database["public"]["Tables"]["schedule_blocks"]["Row"];

// List view, not the wireframe's day-position grid — a materials-gated
// schedule a crew can actually read on a phone mattered more than
// replicating the desktop week-grid this week. blocked/blocked_reason (the
// grid's hatch + caption) carry over as a plain warning row instead. Same
// auto-submit-on-blur editing pattern as MaterialItemRow.
export function ScheduleBlockRow({
  orgId,
  workOrderId,
  block,
}: {
  orgId: string;
  workOrderId: string;
  block: ScheduleBlock;
}) {
  const formRef = useRef<HTMLFormElement>(null);
  const [isPending, startTransition] = useTransition();

  function submit() {
    startTransition(() => {
      formRef.current?.requestSubmit();
    });
  }

  return (
    // Same mobile stacking as MaterialItemRow: crew name gets its own
    // full-width row, start/end dates share a second row, delete on its
    // own row — three roughly-equal-width fields plus delete were
    // overflowing a phone-width line. sm:contents collapses the date
    // wrapper back into the form's direct flex children at desktop size,
    // reproducing the original single-line layout exactly.
    <div className="flex flex-col gap-1 border-b border-border py-2 last:border-b-0">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
        <form
          ref={formRef}
          action={updateScheduleBlock}
          className="flex flex-1 flex-col gap-2 sm:flex-row sm:flex-wrap sm:items-center"
        >
          <input type="hidden" name="orgId" value={orgId} />
          <input type="hidden" name="workOrderId" value={workOrderId} />
          <input type="hidden" name="scheduleBlockId" value={block.id} />
          <input
            name="crew_name"
            defaultValue={block.crew_name}
            disabled={isPending}
            onBlur={submit}
            className="min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent disabled:opacity-60 sm:min-h-0 sm:w-28 sm:py-2 sm:text-sm"
          />
          <div className="flex items-center gap-2 sm:contents">
            <input
              name="start_date"
              type="date"
              defaultValue={block.start_date}
              disabled={isPending}
              onBlur={submit}
              className="min-h-14 flex-1 rounded-md border border-border bg-bg px-1 text-base text-text outline-none focus:border-accent disabled:opacity-60 sm:min-h-0 sm:w-auto sm:flex-none sm:py-2 sm:text-sm"
            />
            <span className="text-muted">–</span>
            <input
              name="end_date"
              type="date"
              defaultValue={block.end_date}
              disabled={isPending}
              onBlur={submit}
              className="min-h-14 flex-1 rounded-md border border-border bg-bg px-1 text-base text-text outline-none focus:border-accent disabled:opacity-60 sm:min-h-0 sm:w-auto sm:flex-none sm:py-2 sm:text-sm"
            />
          </div>
        </form>
        <form action={deleteScheduleBlock} className="self-end sm:self-auto">
          <input type="hidden" name="orgId" value={orgId} />
          <input type="hidden" name="workOrderId" value={workOrderId} />
          <input type="hidden" name="scheduleBlockId" value={block.id} />
          <button
            type="submit"
            aria-label="Remove schedule block"
            className="flex h-14 w-14 shrink-0 items-center justify-center text-muted hover:text-warn sm:h-9 sm:w-9"
          >
            ✕
          </button>
        </form>
      </div>
      {block.blocked && (
        <p className="rounded-md bg-warn-soft px-2 py-1 text-xs text-text">
          {block.blocked_reason ?? `blocked — start date before materials are ready`}
        </p>
      )}
      {!block.blocked && (
        <p className="text-xs text-muted">
          {formatDateOnly(block.start_date)} – {formatDateOnly(block.end_date)}
        </p>
      )}
    </div>
  );
}
