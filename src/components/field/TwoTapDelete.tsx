"use client";

import { useState } from "react";

/**
 * SCOPE §2.4 — a destructive control that one gloved thumb cannot fire by
 * accident. Same pattern CheckInRow already uses for a day's check-in (U-W1.10):
 * the first tap only ASKS, the second, on a separate 56dp button, does it, and
 * "Keep" sits beside it at the same size. Measured before this existed
 * (2026-09-15, 375px): the packet's Reset (48px) and a callout's ✕ (44px) each
 * deleted on ONE tap, and a photo's remove button was 28×28px on top of the
 * photo.
 */
export function TwoTapDelete({
  action,
  fields,
  label,
  confirmLabel,
  question,
  ariaLabel,
  onBeforeSubmit,
  disabled,
}: {
  action?: (formData: FormData) => void | Promise<void>;
  fields?: Record<string, string>;
  label: string;
  confirmLabel: string;
  /** Shown while confirming, so the second tap is made knowing what it removes. */
  question: string;
  ariaLabel?: string;
  /** For callers that submit through a transition instead of a form action. */
  onBeforeSubmit?: () => void;
  disabled?: boolean;
}) {
  const [confirming, setConfirming] = useState(false);

  if (!confirming) {
    return (
      <button
        type="button"
        disabled={disabled}
        aria-label={ariaLabel}
        onClick={() => setConfirming(true)}
        className="flex min-h-14 min-w-14 items-center justify-center rounded-lg border border-border px-3 text-base font-medium text-text disabled:opacity-60 group-data-[outdoor=true]/field:border-white/60 group-data-[outdoor=true]/field:text-white"
      >
        {label}
      </button>
    );
  }

  const confirmButton = (
    <button
      type={onBeforeSubmit ? "button" : "submit"}
      onClick={onBeforeSubmit ? () => { onBeforeSubmit(); setConfirming(false); } : undefined}
      className="flex min-h-14 flex-1 items-center justify-center rounded-lg bg-[var(--warn-strong)] px-3 text-base font-semibold text-white"
    >
      {confirmLabel}
    </button>
  );

  return (
    <div role="group" aria-label={question} className="flex w-full flex-col gap-2">
      <p className="text-sm font-medium text-text group-data-[outdoor=true]/field:text-white">{question}</p>
      <div className="flex gap-2">
        {action ? (
          <form action={action} className="flex flex-1">
            {Object.entries(fields ?? {}).map(([k, v]) => (
              <input key={k} type="hidden" name={k} value={v} />
            ))}
            {confirmButton}
          </form>
        ) : (
          confirmButton
        )}
        <button
          type="button"
          onClick={() => setConfirming(false)}
          className="flex min-h-14 flex-1 items-center justify-center rounded-lg border border-border px-3 text-base font-medium text-text group-data-[outdoor=true]/field:border-white/60 group-data-[outdoor=true]/field:text-white"
        >
          Keep
        </button>
      </div>
    </div>
  );
}
