"use client";

import { useRef, useTransition } from "react";
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
  // U-W1.52 (2026-10-04) — THE BUTTON STOPS TAKING TAPS WHILE ONE IS IN FLIGHT.
  //
  // Jacob submitted the first check-ins in this product's history at 16:51 EDT
  // and got FOUR identical rows, 340ms apart. He reports the submit gave him no
  // sign it had worked.
  //
  // THE MECHANISM IS NOT "TWO SUBMITS AT ONCE", AND THE DIFFERENCE MATTERS.
  // Measured on this component with every server-action POST held for 1.5s:
  // four taps 340ms apart produced THREE posts spaced 1503ms and 1598ms — React
  // SERIALISES form submissions, so nothing ever overlapped. What it does is
  // QUEUE the extra taps and replay them as each one completes. Jacob's 340ms
  // gaps were his ROUND-TRIP TIME, not his tapping speed.
  //
  // So the fix works for a reason worth writing down: disabling the button does
  // not prevent concurrency — React already did — it stops the taps being taken
  // at all, so there is nothing left to replay.
  //
  // This is `disabled={busy}`, which Thursday's §2.8 sweep put explicitly
  // outside that rule: it gates on its OWN submission, never on other data.
  const [isPending, startTransition] = useTransition();
  const formRef = useRef<HTMLFormElement>(null);

  return (
    // Tightened rhythm (phone-test feedback): thinner card chrome
    // (border-2→border, rounded-2xl→rounded-xl, p-4→p-3), gap-3→gap-2.5
    // between fields, and small-caps labels (text-xs) instead of text-sm —
    // inputs stay min-h-14 (≥56dp), only the surrounding whitespace and
    // label weight shrink. inputMode="decimal" on Hours brings up a number
    // pad instead of the full keyboard, same as estimating's squares field.
    <form
      ref={formRef}
      action={(formData) => startTransition(() => createCheckIn(formData))}
      className="flex flex-col gap-2.5 rounded-xl border border-dashed border-border p-3 group-data-[outdoor=true]/field:border-white/40"
    >
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="workOrderId" value={workOrderId} />

      <p className="text-sm font-semibold text-text group-data-[outdoor=true]/field:text-white">
        New check-in
      </p>

      <label className="flex flex-col gap-1">
        <span className="text-sm font-medium text-muted group-data-[outdoor=true]/field:text-white/80">Crew</span>
        <input
          name="crew_name"
          required
          defaultValue={defaultCrewName}
          placeholder="Crew A"
          className="min-h-14 rounded-lg border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
        />
      </label>

      <label className="flex flex-col gap-1">
        <span className="text-sm font-medium text-muted group-data-[outdoor=true]/field:text-white/80">Hours today</span>
        <input
          name="hours"
          type="number"
          inputMode="decimal"
          step="any"
          // U-W1.16 — no prefilled 0. Replacing a prefilled number takes a
          // precise select-and-delete before typing, which is two-handed with
          // gloves. Blank saves "hours not recorded" (NULL), not 0 — Track S,
          // 20260916214356_check_ins_delete_date_hours.
          placeholder="e.g. 8"
          className="min-h-14 rounded-lg border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
        />
      </label>

      <label className="flex flex-col gap-1">
        <span className="text-sm font-medium text-muted group-data-[outdoor=true]/field:text-white/80">Materials used</span>
        <input
          name="materials_used"
          placeholder="e.g. 18 panels, 2 boxes screws"
          className="min-h-14 rounded-lg border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
        />
      </label>

      <label className="flex flex-col gap-1">
        <span className="text-sm font-medium text-muted group-data-[outdoor=true]/field:text-white/80">Blockers?</span>
        <input
          name="blockers"
          placeholder="None"
          className="min-h-14 rounded-lg border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
        />
      </label>

      {/* THE DISABLED STATE SAYS SOMETHING. A greyed button carrying the same
          label reads as broken to a man on a roof; "Saving…" reads as working.
          56dp and the same type size, unchanged — only the words and the
          opacity move. */}
      <button
        type="submit"
        disabled={isPending}
        aria-busy={isPending}
        className="flex min-h-14 items-center justify-center rounded-lg bg-accent-strong text-base font-medium text-white disabled:opacity-70"
      >
        {isPending ? "Saving…" : "Submit check-in"}
      </button>
    </form>
  );
}
