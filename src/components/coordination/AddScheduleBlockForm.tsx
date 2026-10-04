import { addScheduleBlock } from "@/lib/coordination/actions";

// U-W1.50 (2026-10-04) — THE BLOCK CAN NOW CARRY THE CREW RECORD, NOT JUST A
// TYPED NAME.
//
// MEASURED BEFORE BUILDING: addScheduleBlock passed four arguments and never
// p_crew_id, and ALL THREE schedule_blocks rows in the database have a NULL
// crew_id — 3 of 3. The cause was the action, not careless entry.
//
// THE PICKER IS NOT A GATE (SCOPE §2.8). The typed name stays, because a crew
// that has no record yet is a real Monday: the office books "Osman Rivera" at
// 7am and makes the crew record later. add_schedule_block refuses ONLY when
// both are empty (hint crew_required), which is the database agreeing.
//
// AND THE NAME IS NOT TYPED TWICE. When a crew is chosen, the trigger
// crew_name_from_crew overwrites crew_name from the crew record, so there is
// one source for that fact and the typed box is ignored. Two sources for one
// fact is how they diverge.
export function AddScheduleBlockForm({
  orgId,
  workOrderId,
  crews,
  crewsReadable,
}: {
  orgId: string;
  workOrderId: string;
  crews: { id: string; name: string }[];
  crewsReadable: boolean;
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
      {crewsReadable && crews.length > 0 && (
        <select
          name="crew_id"
          defaultValue=""
          aria-label="Crew"
          className="min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent sm:min-h-0 sm:w-36 sm:py-2 sm:text-sm"
        >
          <option value="">Crew… or type a name</option>
          {crews.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </select>
      )}
      {/* NOT `required` any more: either control satisfies the database, and
          marking this one required would make the picker useless — the browser
          would refuse the submit before the server ever saw the crew. */}
      <input
        name="crew_name"
        placeholder={crewsReadable && crews.length > 0 ? "or type who…" : "Who is doing the work…"}
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
        aria-label="Add a crew and dates"
        className="flex h-14 w-14 shrink-0 items-center justify-center self-end rounded-md bg-accent-strong text-base font-medium text-white sm:h-9 sm:w-9 sm:self-auto sm:text-sm"
      >
        +
      </button>
    </form>
  );
}
