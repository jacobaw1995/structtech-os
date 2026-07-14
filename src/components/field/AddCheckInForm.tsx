import { createCheckIn } from "@/lib/field/actions";

// Stacked, single-thumb-column, ≥56dp inputs — the "sub-60-second submit"
// requirement means this form has to be fast to fill with gloves on, not
// dense. Photos attach after creation (PhotoPicker needs a check_in id to
// exist first), same create-then-attach order as estimating's signature
// flow.
export function AddCheckInForm({
  orgId,
  workOrderId,
  defaultCrewName,
}: {
  orgId: string;
  workOrderId: string;
  defaultCrewName?: string;
}) {
  return (
    // Tightened rhythm (phone-test feedback): thinner card chrome
    // (border-2→border, rounded-2xl→rounded-xl, p-4→p-3), gap-3→gap-2.5
    // between fields, and small-caps labels (text-xs) instead of text-sm —
    // inputs stay min-h-14 (≥56dp), only the surrounding whitespace and
    // label weight shrink. inputMode="decimal" on Hours brings up a number
    // pad instead of the full keyboard, same as estimating's squares field.
    <form
      action={createCheckIn}
      className="flex flex-col gap-2.5 rounded-xl border border-dashed border-border p-3 group-data-[outdoor=true]/field:border-white/40"
    >
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="workOrderId" value={workOrderId} />

      <p className="text-sm font-semibold text-text group-data-[outdoor=true]/field:text-white">
        New check-in
      </p>

      <label className="flex flex-col gap-1">
        <span className="text-xs font-medium text-muted group-data-[outdoor=true]/field:text-white/70">Crew</span>
        <input
          name="crew_name"
          required
          defaultValue={defaultCrewName}
          placeholder="Crew A"
          className="min-h-14 rounded-lg border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
        />
      </label>

      <label className="flex flex-col gap-1">
        <span className="text-xs font-medium text-muted group-data-[outdoor=true]/field:text-white/70">Hours today</span>
        <input
          name="hours"
          type="number"
          inputMode="decimal"
          step="any"
          defaultValue={0}
          className="min-h-14 rounded-lg border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
        />
      </label>

      <label className="flex flex-col gap-1">
        <span className="text-xs font-medium text-muted group-data-[outdoor=true]/field:text-white/70">Materials used</span>
        <input
          name="materials_used"
          placeholder="e.g. 18 panels, 2 boxes screws"
          className="min-h-14 rounded-lg border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
        />
      </label>

      <label className="flex flex-col gap-1">
        <span className="text-xs font-medium text-muted group-data-[outdoor=true]/field:text-white/70">Blockers?</span>
        <input
          name="blockers"
          placeholder="None"
          className="min-h-14 rounded-lg border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
        />
      </label>

      <button
        type="submit"
        className="flex min-h-14 items-center justify-center rounded-lg bg-accent-strong text-base font-medium text-white"
      >
        Submit check-in
      </button>
    </form>
  );
}
