"use client";

import { useRef, useState, useTransition } from "react";
import { updateCheckIn, deleteCheckIn } from "@/lib/field/actions";
import { PhotoPicker } from "@/components/field/PhotoPicker";
import { formatDateOnly } from "@/lib/coordination/stage";
import type { Database } from "@/lib/supabase/database.types";

type CheckIn = Database["public"]["Tables"]["check_ins"]["Row"];

// Same auto-submit-on-blur edit pattern as coordination's MaterialItemRow,
// stacked into a card instead of a row — this is the mobile single-thumb
// layout the field role requires, not a desktop table. Delete is a real
// control (SCOPE.md §2.6): a crew member fixing a check-in they got wrong.
export function CheckInRow({
  orgId,
  workOrderId,
  checkIn,
}: {
  orgId: string;
  workOrderId: string;
  checkIn: CheckIn;
}) {
  const formRef = useRef<HTMLFormElement>(null);
  const [isPending, startTransition] = useTransition();
  // U-W1.10 — two taps to delete. Measured at 375x812: this control was 44px,
  // under §2.4's 56dp floor, and four of them sat in thumb reach on the
  // check-in tab. It destroys a day's logged work, on a roof, with gloves on.
  // Local state rather than a URL param because this is already a client
  // component and the redirect after a real delete resets it anyway.
  const [confirming, setConfirming] = useState(false);

  function submit() {
    startTransition(() => {
      formRef.current?.requestSubmit();
    });
  }

  return (
    // Same tightened rhythm as AddCheckInForm — see that file's comment.
    <div className="flex flex-col gap-2.5 rounded-xl border border-border bg-surface p-3 group-data-[outdoor=true]/field:border-white/30 group-data-[outdoor=true]/field:bg-black">
      <div className="flex items-center justify-between">
        <span className="text-xs uppercase tracking-wide text-muted group-data-[outdoor=true]/field:text-white/60">
          {formatDateOnly(checkIn.check_in_date)}
        </span>
        {confirming ? (
          <div className="flex items-center gap-2">
            <form action={deleteCheckIn}>
              <input type="hidden" name="orgId" value={orgId} />
              <input type="hidden" name="workOrderId" value={workOrderId} />
              <input type="hidden" name="checkInId" value={checkIn.id} />
              <button
                type="submit"
                className="flex min-h-14 items-center justify-center rounded-lg bg-warn px-3 text-sm font-semibold text-white"
              >
                Delete
              </button>
            </form>
            <button
              type="button"
              onClick={() => setConfirming(false)}
              className="flex min-h-14 items-center justify-center rounded-lg border border-border px-3 text-sm font-medium text-text group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:text-white"
            >
              Keep
            </button>
          </div>
        ) : (
          <button
            type="button"
            onClick={() => setConfirming(true)}
            aria-label={`Delete the check-in for ${formatDateOnly(checkIn.check_in_date)}`}
            className="flex min-h-14 min-w-14 items-center justify-center text-muted hover:text-warn group-data-[outdoor=true]/field:text-white/60"
          >
            ✕
          </button>
        )}
      </div>

      <form ref={formRef} action={updateCheckIn} className="flex flex-col gap-2.5">
        <input type="hidden" name="orgId" value={orgId} />
        <input type="hidden" name="workOrderId" value={workOrderId} />
        <input type="hidden" name="checkInId" value={checkIn.id} />

        <label className="flex flex-col gap-1">
          <span className="text-xs font-medium text-muted group-data-[outdoor=true]/field:text-white/70">Crew</span>
          <input
            name="crew_name"
            defaultValue={checkIn.crew_name}
            disabled={isPending}
            onBlur={submit}
            className="min-h-14 rounded-lg border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent disabled:opacity-60 group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
          />
        </label>

        <label className="flex flex-col gap-1">
          <span className="text-xs font-medium text-muted group-data-[outdoor=true]/field:text-white/70">Hours</span>
          <input
            name="hours"
            type="number"
            inputMode="decimal"
            step="any"
            defaultValue={checkIn.hours}
            disabled={isPending}
            onBlur={submit}
            className="min-h-14 rounded-lg border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent disabled:opacity-60 group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
          />
        </label>

        <label className="flex flex-col gap-1">
          <span className="text-xs font-medium text-muted group-data-[outdoor=true]/field:text-white/70">Materials used</span>
          <input
            name="materials_used"
            defaultValue={checkIn.materials_used ?? ""}
            disabled={isPending}
            onBlur={submit}
            placeholder="e.g. 18 panels, 2 boxes screws"
            className="min-h-14 rounded-lg border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent disabled:opacity-60 group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
          />
        </label>

        <label className="flex flex-col gap-1">
          <span className="text-xs font-medium text-muted group-data-[outdoor=true]/field:text-white/70">Blockers</span>
          <input
            name="blockers"
            defaultValue={checkIn.blockers ?? ""}
            disabled={isPending}
            onBlur={submit}
            placeholder="None"
            className="min-h-14 rounded-lg border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent disabled:opacity-60 group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
          />
        </label>
      </form>

      <PhotoPicker
        orgId={orgId}
        workOrderId={workOrderId}
        checkInId={checkIn.id}
        photos={checkIn.photos}
      />
    </div>
  );
}
