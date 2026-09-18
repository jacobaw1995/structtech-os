import { listOrgFiles, signOrgFiles } from "@/lib/storage/org-files";
import { deleteWorkOrderFile } from "@/lib/storage/work-order-file-actions";
import { FILES_COPY, orgFilesEnabled, type FilesState } from "@/lib/storage/work-order-files-states";
import { WorkOrderFileUpload } from "@/components/files/WorkOrderFileUpload";

// Roof data and photos attached to one work order. X-W1.15 (A4.7).
//
// The same component serves the office (coordination: add, remove) and the crew
// (field: view). `canManage` only decides which CONTROLS render; what a caller may
// read, add or remove is decided by the storage.objects policies with their own
// identity — a crew member who forged the delete form would remove nothing.
export async function WorkOrderFiles({
  orgId,
  workOrderId,
  canManage,
  state,
  outdoor = false,
  surface = "office",
}: {
  orgId: string;
  workOrderId: string;
  canManage: boolean;
  state: FilesState | null;
  outdoor?: boolean;
  /** Where the page is, so a file that fails to open returns the user to it. */
  surface?: "office" | "field";
}) {
  const heading = "text-xs font-semibold uppercase tracking-wide text-muted group-data-[outdoor=true]/field:text-white/60";

  if (!orgFilesEnabled()) {
    return (
      <section id="files" data-files-state="off" className="rounded-lg border border-border bg-surface p-3">
        <h2 className={`mb-2 ${heading}`}>Roof data + photos</h2>
        <p className="text-sm text-muted">{FILES_COPY.off.text}</p>
      </section>
    );
  }

  const listed = await listOrgFiles({ orgId, category: "office-uploads", entityId: workOrderId });
  const files = listed.ok ? listed.data : [];
  const signed = files.length ? await signOrgFiles({ orgId, paths: files.map((f) => f.path) }) : null;
  const urls = signed?.ok ? signed.data : {};

  return (
    <section id="files" data-files-state={state ?? "idle"} className={`rounded-lg border border-border p-3 ${outdoor ? "" : "bg-surface"}`}>
      <h2 className={`mb-2 ${heading}`}>Roof data + photos</h2>
      {state ? (
        <p role={FILES_COPY[state].tone === "warn" ? "alert" : "status"} className={`mb-2 rounded-md px-3 py-2 text-sm text-text ${FILES_COPY[state].tone === "warn" ? "bg-warn-soft" : "bg-accent-soft"}`}>
          {FILES_COPY[state].text}
        </p>
      ) : null}
      {!listed.ok ? (
        <p className="text-sm text-muted">The file list couldn&apos;t be loaded. Refresh to try again.</p>
      ) : files.length === 0 ? (
        <p className="text-sm text-muted">No roof data or photos on this job yet.</p>
      ) : (
        <ul className="flex flex-col divide-y divide-border">
          {files.map((f) => {
            const display = f.name.replace(/^[0-9a-f]{8}-/, "");
            const url = urls[f.path];
            return (
              <li key={f.path} className="flex min-h-11 items-center gap-3 py-2">
                {url && f.mimeType?.startsWith("image/") ? (
                  // eslint-disable-next-line @next/next/no-img-element -- short-lived signed url
                  <img src={url} alt="" className="h-12 w-12 rounded object-cover" />
                ) : null}
                {url ? (
                  /* X-W1.19: opened through /files/open, which signs at the moment of
                     opening and records file_opened by a hash of the path. The
                     thumbnail above still uses the page's signed url: seeing a
                     thumbnail is not opening the file. */
                  <a
                    href={`/w/${orgId}/files/open?path=${encodeURIComponent(f.path)}&from=${surface}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="flex-1 truncate text-sm text-accent-strong underline"
                  >
                    {display}
                  </a>
                ) : (
                  <span className="flex-1 truncate text-sm text-muted">{display}</span>
                )}
                {canManage ? (
                  <form action={deleteWorkOrderFile}>
                    <input type="hidden" name="orgId" value={orgId} />
                    <input type="hidden" name="workOrderId" value={workOrderId} />
                    <input type="hidden" name="path" value={f.path} />
                    <button type="submit" className="min-h-11 rounded-md px-3 text-sm text-muted underline">
                      Remove
                    </button>
                  </form>
                ) : null}
              </li>
            );
          })}
        </ul>
      )}
      {canManage ? <WorkOrderFileUpload orgId={orgId} workOrderId={workOrderId} /> : null}
    </section>
  );
}
