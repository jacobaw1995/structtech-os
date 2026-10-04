import { SPECIAL_TRIP_REASONS } from "@/lib/field/special-trip";
import { ActionForm } from "@/components/field/ActionForm";

// LOGGING A SPECIAL TRIP, IN TWO TAPS. Track U, U-W1.31, 2026-09-23.
//
// MOUNTED on the crew job page (field/[workOrderId]/page.tsx) — this header
// said "NOT MOUNTED ON ANY SCREEN YET" until 2026-10-04, which stopped being
// true when the action and the table landed. Corrected rather than deleted:
// the reason it was written is still the rule. A control that appears to record
// something it cannot is worse than no control.
//
// Tap 1 opens the list. Tap 2 IS the record: each reason is its own submit
// button carrying its own code, so choosing and confirming are the same motion.
// No free-text box anywhere, by construction — there is nothing to type, so
// there is nothing to type instead of choosing.
//
// <details> rather than useState: this stays a SERVER component, and the open
// state survives nothing, which is right — a crew opens it, taps, and it is done.
// The pending state that a server component cannot hold lives one level down, in
// ActionForm — see that file for the measurement that made it necessary.
//
// EACH REASON KEEPS ITS OWN PENDING STATE, and that is deliberate. Tapping the
// SAME reason twice is the duplicate we are stopping; tapping a DIFFERENT one is
// a different record, and disabling the other six while one is in flight would
// gate a control on a submission that is not its own (SCOPE §2.8).
export function SpecialTripPanel({
  orgId,
  workOrderId,
  action,
}: {
  orgId: string;
  workOrderId: string;
  /** The server action that records the trip. Required: no action, no panel. */
  action: (formData: FormData) => void | Promise<void>;
}) {
  return (
    <details className="group/trip rounded-lg border border-border p-3 group-data-[outdoor=true]/field:border-white/30">
      <summary className="flex min-h-14 cursor-pointer list-none items-center gap-2 text-base font-semibold text-text group-data-[outdoor=true]/field:text-white [&::-webkit-details-marker]:hidden">
        <span aria-hidden="true" className="text-muted transition-transform group-open/trip:rotate-90 group-data-[outdoor=true]/field:text-white/80">
          ›
        </span>
        Log a special trip
      </summary>

      <p className="mt-2 text-sm text-muted group-data-[outdoor=true]/field:text-white/80">
        Tap the reason you came back. That is the whole thing — nothing to type.
      </p>

      <ul className="mt-2 flex flex-col gap-2">
        {SPECIAL_TRIP_REASONS.map((reason) => (
          <li key={reason.code}>
            <ActionForm
              action={action}
              buttonClassName="flex min-h-14 w-full flex-col items-start justify-center rounded-lg border border-border px-3 py-2 text-left text-base font-medium text-text group-data-[outdoor=true]/field:border-white/60 group-data-[outdoor=true]/field:text-white"
              label={
                <>
                  {reason.label}
                  <span className="text-xs font-normal text-muted group-data-[outdoor=true]/field:text-white/70">
                    {reason.help}
                  </span>
                </>
              }
              /* It names the reason it is recording — on a roof, "Saving…" alone
                 does not say WHICH of seven buttons was the one that took. */
              pendingLabel={
                <>
                  Saving…
                  <span className="text-xs font-normal text-muted group-data-[outdoor=true]/field:text-white/70">
                    {reason.label}
                  </span>
                </>
              }
            >
              <input type="hidden" name="orgId" value={orgId} />
              <input type="hidden" name="workOrderId" value={workOrderId} />
              <input type="hidden" name="reason" value={reason.code} />
            </ActionForm>
          </li>
        ))}
      </ul>
    </details>
  );
}
