// Every state the work-order files section can be in, and the sentence each shows.
// Track X, X-W1.15, 2026-09-15.
//
// URL PARAMETERS ARE CODES. The page reads `?files=<code>` and looks the code up
// here; text never comes from a URL (controller ruling 2026-09-15). An unknown
// code renders nothing.
//
// WHY "off" IS CONFIGURATION, NOT AN INFERENCE. Until Track S applies the
// org-files policies, a read returns an EMPTY list with no error — RLS hides the
// rows (fixture suite "before"). An empty list cannot tell "no files yet" from
// "storage is not switched on", so the page is told which by ORG_FILES_ENABLED,
// the same way password reset is told by AUTH_EMAIL_ENABLED.

export type FilesState =
  | "off"
  | "uploaded"
  | "upload_refused"
  | "upload_failed"
  | "too_large"
  | "wrong_type"
  | "deleted"
  | "delete_refused"
  | "delete_failed";

export const FILES_COPY: Record<FilesState, { tone: "info" | "warn"; text: string }> = {
  off: {
    tone: "warn",
    text: "File storage for work orders isn't switched on yet. Roof data and photos can't be added here until it is.",
  },
  uploaded: { tone: "info", text: "File added. The crew can see it on this job." },
  upload_refused: {
    tone: "warn",
    text: "Storage refused this upload for your role in this workspace. Nothing was added.",
  },
  upload_failed: {
    tone: "warn",
    text: "The upload didn't finish, so we can't confirm the file was added. Check the list below before trying again.",
  },
  too_large: { tone: "warn", text: "That file is over 25 MB. Nothing was added." },
  wrong_type: { tone: "warn", text: "Only photos and PDFs can be added here. Nothing was added." },
  deleted: { tone: "info", text: "File removed." },
  delete_refused: { tone: "warn", text: "That file wasn't removed — your role can't delete files in this workspace." },
  delete_failed: {
    tone: "warn",
    text: "We couldn't confirm the file was removed. Refresh to check whether it's still listed.",
  },
};

export function isFilesState(v: unknown): v is FilesState {
  return typeof v === "string" && Object.prototype.hasOwnProperty.call(FILES_COPY, v);
}

/** Configuration fact: have the org-files storage policies been applied? */
export function orgFilesEnabled(): boolean {
  return process.env.ORG_FILES_ENABLED === "true";
}

/** The bucket's own limit (org-files file_size_limit = 26214400, read 2026-09-15). */
export const MAX_FILE_BYTES = 26_214_400;

export function isAllowedFileType(type: string): boolean {
  return type.startsWith("image/") || type === "application/pdf";
}
