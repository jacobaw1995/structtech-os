import { addScheduleBlock } from "@/lib/coordination/actions";

export function AddScheduleBlockForm({
  orgId,
  workOrderId,
}: {
  orgId: string;
  workOrderId: string;
}) {
  return (
    <form
      action={addScheduleBlock}
      className="flex flex-wrap items-center gap-2 border-t border-border pt-2"
    >
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="workOrderId" value={workOrderId} />
      <input
        name="crew_name"
        required
        placeholder="Crew…"
        className="w-28 rounded-md border border-border bg-bg px-2 py-2 text-sm text-text outline-none focus:border-accent"
      />
      <input
        name="start_date"
        type="date"
        required
        className="rounded-md border border-border bg-bg px-1 py-2 text-sm text-text outline-none focus:border-accent"
      />
      <span className="text-muted">–</span>
      <input
        name="end_date"
        type="date"
        required
        className="rounded-md border border-border bg-bg px-1 py-2 text-sm text-text outline-none focus:border-accent"
      />
      <button
        type="submit"
        aria-label="Add schedule block"
        className="h-9 w-9 shrink-0 rounded-md bg-accent-strong text-sm font-medium text-white"
      >
        +
      </button>
    </form>
  );
}
