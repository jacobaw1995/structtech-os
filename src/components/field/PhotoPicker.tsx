"use client";

import { useRef, useState, useTransition } from "react";
import { addCheckInPhoto, removeCheckInPhoto } from "@/lib/field/actions";

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
      {photos.length > 0 && (
        <div className="grid grid-cols-3 gap-2">
          {photos.map((photo, i) => (
            <div key={i} className="relative aspect-square overflow-hidden rounded-lg border border-border group-data-[outdoor=true]/field:border-white/30">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={photo} alt="" className="h-full w-full object-cover" />
              <button
                type="button"
                onClick={() => handleRemove(photo)}
                disabled={isPending}
                aria-label="Remove photo"
                className="absolute right-1 top-1 flex h-7 w-7 items-center justify-center rounded-full bg-black/70 text-xs text-white disabled:opacity-60"
              >
                ✕
              </button>
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
        className="flex min-h-14 items-center justify-center rounded-lg border-2 border-dashed border-border text-sm text-muted disabled:opacity-60 group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:text-white/70"
      >
        {isPending ? "Saving photo…" : "📷 tap to add job photos"}
      </button>
      {pendingError && (
        <p className="text-xs text-warn">{pendingError}</p>
      )}
    </div>
  );
}
