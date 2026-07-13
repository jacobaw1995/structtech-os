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
    <div className="flex flex-col gap-1 border-b border-border py-2 last:border-b-0">
      <div className="flex items-center gap-2">
        <form
          ref={formRef}
          action={updateScheduleBlock}
          className="flex flex-1 flex-wrap items-center gap-2"
        >
          <input type="hidden" name="orgId" value={orgId} />
          <input type="hidden" name="workOrderId" value={workOrderId} />
          <input type="hidden" name="scheduleBlockId" value={block.id} />
          <input
            name="crew_name"
            defaultValue={block.crew_name}
            disabled={isPending}
            onBlur={submit}
            className="w-28 rounded-md border border-border bg-bg px-2 py-2 text-sm text-text outline-none focus:border-accent disabled:opacity-60"
          />
          <input
            name="start_date"
            type="date"
            defaultValue={block.start_date}
            disabled={isPending}
            onBlur={submit}
            className="rounded-md border border-border bg-bg px-1 py-2 text-sm text-text outline-none focus:border-accent disabled:opacity-60"
          />
          <span className="text-muted">–</span>
          <input
            name="end_date"
            type="date"
            defaultValue={block.end_date}
            disabled={isPending}
            onBlur={submit}
            className="rounded-md border border-border bg-bg px-1 py-2 text-sm text-text outline-none focus:border-accent disabled:opacity-60"
          />
        </form>
        <form action={deleteScheduleBlock}>
          <input type="hidden" name="orgId" value={orgId} />
          <input type="hidden" name="workOrderId" value={workOrderId} />
          <input type="hidden" name="scheduleBlockId" value={block.id} />
          <button
            type="submit"
            aria-label="Remove schedule block"
            className="h-9 w-9 shrink-0 text-muted hover:text-warn"
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
