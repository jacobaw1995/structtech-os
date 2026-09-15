"use client";

import { useRef, useState, useTransition } from "react";
import { addCheckInPhoto, removeCheckInPhoto } from "@/lib/field/actions";
import { TwoTapDelete } from "@/components/field/TwoTapDelete";

// Reads the picked file client-side into a base64 data URI and submits it
// via FormData (same manual-FormData-in-startTransition pattern as
// StepSign's signature capture) — no separate upload endpoint needed since
// check_ins.photos stores the data URI directly (migration header note 1).
// `capture="environment"` opens the rear camera directly on a phone instead
// of a gallery picker, matching the wireframe's "📷 tap to add job photos".
export function PhotoPicker({
  orgId,
  workOrderId,
  checkInId,
  photos,
}: {
  orgId: string;
  workOrderId: string;
  checkInId: string;
  photos: string[];
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [isPending, startTransition] = useTransition();
  const [pendingError, setPendingError] = useState<string | null>(null);

  function handleFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;

    const reader = new FileReader();
    reader.onload = () => {
      const dataUrl = reader.result;
      if (typeof dataUrl !== "string") {
        setPendingError("Could not read that photo — try again.");
        return;
      }
      setPendingError(null);
      const formData = new FormData();
      formData.set("orgId", orgId);
      formData.set("workOrderId", workOrderId);
      formData.set("checkInId", checkInId);
      formData.set("photo_data_url", dataUrl);
      startTransition(() => {
        addCheckInPhoto(formData);
      });
    };
    reader.onerror = () => setPendingError("Could not read that photo — try again.");
    reader.readAsDataURL(file);
  }

  function handleRemove(photoDataUrl: string) {
    const formData = new FormData();
    formData.set("orgId", orgId);
    formData.set("workOrderId", workOrderId);
    formData.set("checkInId", checkInId);
    formData.set("photo_data_url", photoDataUrl);
    startTransition(() => {
      removeCheckInPhoto(formData);
    });
  }

  return (
    <div className="flex flex-col gap-2">
      {/* U-W1.16 — the remove control was a 28x28px ✕ ON the photo, one tap,
          no confirm (measured at 375px). Two columns, not three, so a tile is
          wide enough to carry a 56dp control underneath it rather than on top. */}
      {photos.length > 0 && (
        <div className="grid grid-cols-2 gap-2">
          {photos.map((photo, i) => (
            <div key={i} className="flex flex-col gap-2">
              <div className="aspect-square overflow-hidden rounded-lg border border-border group-data-[outdoor=true]/field:border-white/30">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={photo} alt={`Photo ${i + 1}`} className="h-full w-full object-cover" />
              </div>
              <TwoTapDelete
                label="Remove"
                ariaLabel={`Remove photo ${i + 1}`}
                question={`Remove photo ${i + 1}?`}
                confirmLabel="Remove"
                disabled={isPending}
                onBeforeSubmit={() => handleRemove(photo)}
              />
            </div>
          ))}
        </div>
      )}

      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        capture="environment"
        onChange={handleFile}
        className="hidden"
      />
      <button
        type="button"
        disabled={isPending}
        onClick={() => inputRef.current?.click()}
        className="flex min-h-14 items-center justify-center rounded-lg border-2 border-dashed border-border text-base text-text disabled:opacity-60 group-data-[outdoor=true]/field:border-white/60 group-data-[outdoor=true]/field:text-white"
      >
        {isPending ? "Saving photo…" : "📷 tap to add job photos"}
      </button>
      {pendingError && (
        <p className="text-sm font-medium text-text group-data-[outdoor=true]/field:text-white">{pendingError}</p>
      )}
    </div>
  );
}
