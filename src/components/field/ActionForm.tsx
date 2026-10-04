"use client";

import { useTransition, type ReactNode } from "react";

// A FORM WHOSE BUTTON STOPS ACCEPTING TAPS ONCE IT HAS ONE. Track U, U-W1.52,
// 2026-10-04.
//
// WHY THIS EXISTS, measured rather than assumed. Jacob submitted the first
// check-ins in this product's history at 16:51 EDT on 2026-10-04 and submitted
// four. React does NOT run concurrent submissions of a `<form action={…}>`: it
// serialises them and QUEUES the extra taps, replaying each one as the previous
// completes. So the defect is not a race — it is that a tap taken during flight
// is honoured a second later, and the roofer has no way to know the first one
// landed. Four taps became four rows.
//
// WHAT THE FIX ACTUALLY DOES, said precisely because the mechanism matters: the
// disabled button does not prevent concurrency (there was none). It stops the
// second tap being TAKEN. And it says so — `disabled` alone is a control that
// has gone quiet, which on a roof reads as a control that is broken.
//
// WHY IT IS A COMPONENT AND NOT THREE LINES IN EACH FILE. React 18 is what
// this build is on, so there is no `useFormStatus`; a pending flag has to come
// from a hook, and a hook needs a client component. Every form this wraps is
// rendered by a SERVER component (the QC checklist, the special-trip panel, the
// callout form, the packet notes), which cannot call hooks at all. Pushing those
// whole components across the client boundary to get one boolean would move a
// lot of markup for no reason, so the boundary is drawn around the form instead.
// The children stay server-rendered; only the button needs to know.
//
// AddCheckInForm keeps the same mechanism written inline, because it was already
// a client component for its own reasons (it holds a ref). One mechanism, two
// spellings, and the difference is which side of the boundary the caller is on —
// not a preference.
//
// NOT A §2.8 QUESTION. §2.8 forbids disabling a control because OTHER data is
// incomplete. This gates a control on its own submission, which is the one thing
// it does know about.
export function ActionForm({
  action,
  label,
  pendingLabel = "Saving…",
  className,
  buttonClassName,
  children,
}: {
  action: (formData: FormData) => void | Promise<void>;
  /** What the button says when it is ready. Not a string: some labels have two lines. */
  label: ReactNode;
  /** What it says while the submission is in flight. Must SAY something. */
  pendingLabel?: ReactNode;
  className?: string;
  buttonClassName?: string;
  /** The fields. Rendered before the button, which is where every caller had it. */
  children?: ReactNode;
}) {
  const [isPending, startTransition] = useTransition();

  return (
    // `async` and `await`, not a bare call: the transition stays pending for as
    // long as the action is in flight, which is the whole point. A callback that
    // returns void would clear isPending on the next tick and re-enable the
    // button while the request was still open.
    <form
      action={(formData) => startTransition(async () => { await action(formData); })}
      className={className}
    >
      {children}
      <button
        type="submit"
        disabled={isPending}
        aria-busy={isPending}
        className={`${buttonClassName ?? ""} disabled:opacity-70`}
      >
        {isPending ? pendingLabel : label}
      </button>
    </form>
  );
}
