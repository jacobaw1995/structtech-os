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
  | "delete_failed"
  | "open_failed";

export const FILES_COPY: Record<FilesState, { tone: "info" | "warn"; text: string }> = {
  // U-W1.45 (2026-09-30) — ONE STATE, TWO TRUTHS, so it is two sentences.
  //
  // The crew job screen passes canManage={false} — view only, by design, and
  // WorkOrderFileUpload renders only under canManage, so there is no upload
  // control there and never was. VERIFIED BEFORE CHANGING ANYTHING: the literal
  // canManage={false} is in field/[workOrderId]/page.tsx, and the office page
  // passes can_view_master_work_order instead.
  //
  // So "can't be added here" was FALSE on the crew screen — it told a roofer he
  // could not do a thing he was never able to do, and implied a control existed
  // somewhere above him. On the OFFICE screen the same sentence is TRUE, which
  // is why the fix is a second sentence rather than a reword of the first.
  off: {
    tone: "warn",
    text: "File storage for work orders isn't switched on yet. Roof data and photos can't be added here until it is.",
  },
  uploaded: { tone: "info", text: "File added. The crew can see it on this job." },
  upload_refused: {
    tone: "warn",
    text: "That upload wasn't allowed for your account. Nothing was added — ask the office to add it.",
  },
  upload_failed: {
    tone: "warn",
    text: "The upload didn't finish, so we can't confirm the file was added. Check the list below before trying again.",
  },
  too_large: { tone: "warn", text: "That file is over 25 MB. Nothing was added." },
  wrong_type: { tone: "warn", text: "Only photos and PDFs can be added here. Nothing was added." },
  deleted: { tone: "info", text: "File removed." },
  delete_refused: { tone: "warn", text: "That file wasn't removed. Ask the office to remove it." },
  open_failed: { tone: "warn", text: "That file couldn't be opened. Refresh the page and try again." },
  delete_failed: {
    tone: "warn",
    text: "We couldn't confirm the file was removed. Refresh to check whether it's still listed.",
  },
};

/**
 * What the "off" state says on the CREW screen, where nothing can be added by
 * anyone: the office has not switched it on, so there is nothing to see yet.
 * No mention of adding, because adding was never on offer here.
 */
export const FILES_OFF_VIEW_ONLY =
  "The office hasn't switched on roof data and photos yet, so there's nothing to see here.";

export function isFilesState(v: unknown): v is FilesState {
  return typeof v === "string" && Object.prototype.hasOwnProperty.call(FILES_COPY, v);
}

/**
 * U-W1.48 (2026-10-01) — WHICH STATES EACH SURFACE MAY RENDER, AND IT IS NOT
 * THE SAME SET. A NARROWING OF THE `?files=` URL CONTRACT, deliberately.
 *
 * Reported on 2026-09-30 and not fixed then: `isFilesState` accepted the whole
 * map on either surface, so a hand-typed query string could show a CREW member
 * "That upload wasn't allowed for your account" — on a screen with no upload
 * control, about an action they cannot perform. Five states were reachable that
 * way: upload_refused, upload_failed, wrong_type, delete_refused, delete_failed.
 *
 * THE CREW SET IS DERIVED FROM WHAT CAN ACTUALLY HAPPEN THERE, not from taste.
 * The crew screen passes canManage={false}, so no upload and no delete control
 * renders. The only file action it offers is OPENING one, and the open route
 * (app/w/[orgId]/files/open/route.ts) sends back exactly one code:
 * `open_failed`. So that is the crew's whole set.
 *
 * `off` is not in it because it is not a URL state at all — it is read from
 * configuration before any query string is consulted.
 *
 * An out-of-set value renders NOTHING, exactly as an unknown code already did.
 * Nothing legitimate is lost: no path in this application sends a crew any
 * other code.
 */
export const FILES_STATES_BY_SURFACE: Record<"office" | "field", readonly FilesState[]> = {
  office: Object.keys(FILES_COPY) as FilesState[],
  field: ["open_failed"],
};

export function isFilesStateFor(surface: "office" | "field", v: unknown): v is FilesState {
  return isFilesState(v) && FILES_STATES_BY_SURFACE[surface].includes(v);
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
