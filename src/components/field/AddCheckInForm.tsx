"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { createCheckIn } from "@/lib/field/actions";
import { newSubmissionToken } from "@/lib/field/submission-token";

// Stacked, single-thumb-column, ≥56dp inputs — the "sub-60-second submit"
// requirement means this form has to be fast to fill with gloves on, not
// dense. Photos attach after creation (PhotoPicker needs a check_in id to
// exist first), same create-then-attach order as estimating's signature
// flow.
export function AddCheckInForm({
  orgId,
  workOrderId,
  defaultCrewName,
  checkInCount,
}: {
  orgId: string;
  workOrderId: string;
  defaultCrewName?: string;
  /**
   * How many check-ins this job already has, as the SERVER last rendered it.
   * This is the only thing that rotates the idempotency token — see below.
   */
  checkInCount: number;
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

  // U-W1.53 (2026-10-04) — AND THE PART THE BUTTON CANNOT DO.
  //
  // Disabling the button stops a tap being TAKEN. It cannot help the case it
  // was never able to reach: the request that left the phone and whose ANSWER
  // never came back. An offline resend, a reload-and-resubmit, a second tab —
  // each delivers the same payload again, with no second tap involved. S's
  // function deduplicates those by token; this is where the token comes from.
  //
  // THE RULE, and it is the whole judgement: THE TOKEN CHANGES WHEN A CHECK-IN
  // ACTUALLY LANDS, AND FOR NOTHING ELSE.
  //
  // It is keyed on `checkInCount` — the number of rows the SERVER last rendered
  // — because that is the only fact that distinguishes "my attempt was
  // recorded" from "my attempt was not recorded", and a client that lost the
  // response cannot know the difference any other way. Deliberately NOT keyed
  // on the submission completing: a completion is something the client
  // observes, and the case that matters is the one where it observes nothing.
  //
  // What that gives, case by case:
  //   · a row lands        -> the page re-renders with a bigger count -> new
  //                           token, so the next check-in is a new attempt;
  //   · the answer is lost -> the stale client's count is unchanged -> SAME
  //                           token -> a resend returns the original row's id
  //                           and writes nothing;
  //   · REFUSED (no crew)  -> no row, so the count is unchanged and the token
  //                           is reused. Harmless and in fact correct: the
  //                           function only dedups against a row that EXISTS,
  //                           so the corrected resubmit inserts under the same
  //                           token. Nothing is swallowed.
  //
  // WHAT SHOULD STILL PRODUCE TWO ROWS: a second genuine check-in — the
  // afternoon one after a morning one, or a second crew on the same job —
  // which the crew makes after the first appears in the list above. The count
  // has changed by then, so the token has too. Identical content is not
  // treated as a duplicate; only an identical ATTEMPT is.
  const [token, setToken] = useState(newSubmissionToken);
  const landed = useRef(checkInCount);
  useEffect(() => {
    if (checkInCount > landed.current) {
      landed.current = checkInCount;
      setToken(newSubmissionToken());
    }
  }, [checkInCount]);

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
      <input type="hidden" name="client_token" value={token} />

      <p className="text-sm font-semibold text-text group-data-[outdoor=true]/field:text-white">
        New check-in
      </p>

      <label className="flex flex-col gap-1">
        <span className="text-sm font-medium text-muted group-data-[outdoor=true]/field:text-white/80">Crew</span>
        {/* NO `required`, DELIBERATELY — removed 2026-10-04 by controller ruling.
            createCheckIn's own comment already named the server as the single
            authority on what counts as a crew name and rejected an HTML
            `pattern` for putting the refusal "behind a browser-native bubble
            whose wording we do not control". `required` was that same bubble,
            left in place: it blocked an empty box with Chrome's sentence while
            three spaces travelled on to meet OURS. Two refusals for one
            mistake, and the roofer met whichever one their typing happened to
            trigger.
            AND IT WAS THE COMMON PATH, NOT AN EDGE. defaultCrewName falls back
            through the prior check-in and the schedule block (see the job
            page); when neither exists the box is empty, which is EVERY FIRST
            CHECK-IN ON EVERY JOB THAT HAS NO SCHEDULED CREW NAME. The server
            refuses an empty or spaces-only crew by name — hint crew_required,
            rendered as "Choose a crew, or type who is doing the work."
            (SCOPE §2.8: the submit is never blocked; the answer comes back.) */}
        <input
          name="crew_name"
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
