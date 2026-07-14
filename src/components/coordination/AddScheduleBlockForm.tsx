import { addScheduleBlock } from "@/lib/coordination/actions";

export function AddScheduleBlockForm({
  orgId,
  workOrderId,
}: {
  orgId: string;
  workOrderId: string;
}) {
  return (
    // Same mobile stacking as ScheduleBlockRow: crew name on its own row,
    // dates share a second row, the add button on its own row (three
    // fields plus button don't fit a phone-width line together).
    <form
      action={addScheduleBlock}
      className="flex flex-col gap-2 border-t border-border pt-2 sm:flex-row sm:flex-wrap sm:items-center"
    >
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="workOrderId" value={workOrderId} />
      <input
        name="crew_name"
        required
        placeholder="Crew…"
        className="min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent sm:min-h-0 sm:w-28 sm:py-2 sm:text-sm"
      />
      <div className="flex items-center gap-2 sm:contents">
        <input
          name="start_date"
          type="date"
          required
          className="min-h-14 flex-1 rounded-md border border-border bg-bg px-1 text-base text-text outline-none focus:border-accent sm:min-h-0 sm:w-auto sm:flex-none sm:py-2 sm:text-sm"
        />
        <span className="text-muted">–</span>
        <input
          name="end_date"
          type="date"
          required
          className="min-h-14 flex-1 rounded-md border border-border bg-bg px-1 text-base text-text outline-none focus:border-accent sm:min-h-0 sm:w-auto sm:flex-none sm:py-2 sm:text-sm"
        />
      </div>
      <button
        type="submit"
        aria-label="Add schedule block"
        className="flex h-14 w-14 shrink-0 items-center justify-center self-end rounded-md bg-accent-strong text-base font-medium text-white sm:h-9 sm:w-9 sm:self-auto sm:text-sm"
      >
        +
      </button>
    </form>
  );
}
