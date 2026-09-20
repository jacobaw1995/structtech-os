"use client";

import { useRef, useState, useTransition } from "react";
import { recordQcItem } from "@/lib/field/qc-actions";
import { preparePhoto } from "@/lib/field/photo";

// Take the photo one QC requirement asks for. X-W1.20.
// Uses preparePhoto() — Track U's fix for photos over 1 MiB being silently
// truncated in transit — and then the ordinary QC action, which saves it through
// add_check_in_photo(). No second upload path.
export function QcPhotoButton({
  orgId,
  workOrderId,
  checkInId,
  requirementKey,
  label,
  retake,
}: {
  orgId: string;
  workOrderId: string;
  checkInId: string | null;
  requirementKey: string;
  label: string;
  retake: boolean;
}) {
  const input = useRef<HTMLInputElement>(null);
  const [pending, startTransition] = useTransition();
  const [tooLarge, setTooLarge] = useState<string | null>(null);

  async function onFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;
    const prepared = await preparePhoto(file);
    if (!prepared.ok) {
      setTooLarge(prepared.reason);
      return;
    }
    setTooLarge(null);
    const form = new FormData();
    form.set("orgId", orgId);
    form.set("workOrderId", workOrderId);
    form.set("checkInId", checkInId ?? "");
    form.set("requirementKey", requirementKey);
    form.set("photo_data_url", prepared.dataUrl);
    startTransition(() => {
      recordQcItem(form);
    });
  }

  return (
    <div className="flex flex-col gap-1">
      <label className="flex min-h-14 cursor-pointer items-center justify-center rounded-md bg-accent-strong px-4 text-sm font-medium text-white">
        <input ref={input} type="file" accept="image/*" capture="environment" className="sr-only" disabled={pending} onChange={onFile} />
        {pending ? "Saving…" : retake ? `Retake ${label}` : `Take ${label} photo`}
      </label>
      {tooLarge && <p className="text-xs text-text group-data-[outdoor=true]/field:text-white">{tooLarge}</p>}
    </div>
  );
}
