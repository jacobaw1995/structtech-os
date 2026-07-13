"use client";

import { useRef, useTransition } from "react";
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

  function submit() {
    startTransition(() => {
      formRef.current?.requestSubmit();
    });
  }

  return (
    <div className="flex flex-col gap-3 rounded-2xl border-2 border-border bg-surface p-4 group-data-[outdoor=true]/field:border-white/30 group-data-[outdoor=true]/field:bg-black">
      <div className="flex items-center justify-between">
        <span className="text-xs uppercase tracking-wide text-muted group-data-[outdoor=true]/field:text-white/60">
          {formatDateOnly(checkIn.check_in_date)}
        </span>
        <form action={deleteCheckIn}>
          <input type="hidden" name="orgId" value={orgId} />
          <input type="hidden" name="workOrderId" value={workOrderId} />
          <input type="hidden" name="checkInId" value={checkIn.id} />
          <button
            type="submit"
            aria-label="Delete check-in"
            className="flex min-h-11 min-w-11 items-center justify-center text-muted hover:text-warn"
          >
            ✕
          </button>
        </form>
      </div>

      <form ref={formRef} action={updateCheckIn} className="flex flex-col gap-3">
        <input type="hidden" name="orgId" value={orgId} />
        <input type="hidden" name="workOrderId" value={workOrderId} />
        <input type="hidden" name="checkInId" value={checkIn.id} />

        <label className="flex flex-col gap-1 text-sm">
          <span className="text-muted group-data-[outdoor=true]/field:text-white/70">Crew</span>
          <input
            name="crew_name"
            defaultValue={checkIn.crew_name}
            disabled={isPending}
            onBlur={submit}
            className="min-h-14 rounded-lg border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent disabled:opacity-60 group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          <span className="text-muted group-data-[outdoor=true]/field:text-white/70">Hours</span>
          <input
            name="hours"
            type="number"
            step="any"
            defaultValue={checkIn.hours}
            disabled={isPending}
            onBlur={submit}
            className="min-h-14 rounded-lg border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent disabled:opacity-60 group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          <span className="text-muted group-data-[outdoor=true]/field:text-white/70">Materials used</span>
          <input
            name="materials_used"
            defaultValue={checkIn.materials_used ?? ""}
            disabled={isPending}
            onBlur={submit}
            placeholder="e.g. 18 panels, 2 boxes screws"
            className="min-h-14 rounded-lg border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent disabled:opacity-60 group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          <span className="text-muted group-data-[outdoor=true]/field:text-white/70">Blockers</span>
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
