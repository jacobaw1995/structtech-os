"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { MAX_FILE_BYTES, isAllowedFileType, type FilesState } from "@/lib/storage/work-order-files-states";

// Office-side upload for one work order. X-W1.15.
//
// Two requests: ask this app for a signed upload url (the gate), then PUT the file
// straight to storage with it. No Supabase client in the browser — plain fetch —
// so the browser-auth tripwire has nothing to find. The outcome is a CODE on the
// URL; the page renders the sentence.
export function WorkOrderFileUpload({ orgId, workOrderId }: { orgId: string; workOrderId: string }) {
  const router = useRouter();
  const input = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);

  function finish(state: FilesState) {
    setBusy(false);
    if (input.current) input.current.value = "";
    router.replace(`/w/${orgId}/coordination/${workOrderId}?files=${state}#files`);
    router.refresh();
  }

  async function upload(file: File) {
    if (file.size > MAX_FILE_BYTES) return finish("too_large");
    if (!isAllowedFileType(file.type)) return finish("wrong_type");
    setBusy(true);

    let ticket: { state?: string; signedUrl?: string };
    try {
      const res = await fetch(`/w/${orgId}/coordination/${workOrderId}/files/upload-url`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ filename: file.name, size: file.size, type: file.type }),
      });
      ticket = await res.json();
    } catch {
      return finish("upload_failed");
    }
    if (ticket.state !== "ready" || !ticket.signedUrl) {
      const known: FilesState[] = ["off", "upload_refused", "too_large", "wrong_type"];
      return finish(known.includes(ticket.state as FilesState) ? (ticket.state as FilesState) : "upload_failed");
    }

    // Same body shape storage-js uses for a Blob: multipart with the file unnamed.
    const body = new FormData();
    body.append("cacheControl", "3600");
    body.append("", file);
    try {
      const put = await fetch(ticket.signedUrl, { method: "PUT", headers: { "x-upsert": "false" }, body });
      if (put.ok) return finish("uploaded");
      if (put.status === 413) return finish("too_large");
      if (put.status === 401 || put.status === 403) return finish("upload_refused");
      return finish("upload_failed");
    } catch {
      // The PUT may have landed before the connection dropped: "failed" copy says
      // to check the list, not that nothing was added.
      return finish("upload_failed");
    }
  }

  return (
    <label className="mt-3 flex min-h-11 cursor-pointer items-center justify-center rounded-md border border-dashed border-border px-3 py-2 text-sm font-medium text-accent-strong">
      <input
        ref={input}
        type="file"
        accept="image/*,application/pdf"
        className="sr-only"
        disabled={busy}
        onChange={(e) => {
          const file = e.target.files?.[0];
          if (file) void upload(file);
        }}
      />
      {busy ? "Uploading…" : "Add roof data or a photo"}
    </label>
  );
}
