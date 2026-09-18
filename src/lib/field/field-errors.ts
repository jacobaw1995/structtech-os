// Why a field action did not land, as a CODE the job page looks up.
// Track U, U-W1.20, 2026-09-17. Same pattern as Track X's sign-states.ts.
//
// CONTROLLER RULING 2026-09-15: a URL parameter is a code that gets looked up; the
// text always comes from us; no URL parameter is ever rendered as text. Until
// today every field action put the database's own message in `?error=` and the
// job page printed it — so any link could put any words in a warning banner on a
// crew member's screen.
//
// Matched against the raises in the field functions, read 2026-09-17:
//   "check-in not found or not accessible", "production packet not found or not
//   accessible", "work order not found or not accessible", "work order … is
//   kind=… — this action requires a … work order", and delete_check_in's "only
//   the person who recorded this check-in, or the office, can delete it".
// A message that matches none of them is still named — `save_failed` — never shown.

export type FieldError =
  | "not_accessible"
  | "wrong_level"
  | "delete_not_yours"
  | "hours_not_cleared"
  | "save_failed"
  | "save_unconfirmed";

export const FIELD_ERROR_COPY: Record<FieldError, string> = {
  not_accessible: "That item couldn't be found for your account. Nothing was changed.",
  wrong_level: "This is not a trade work order, so it can't take check-ins or a packet. Nothing was changed.",
  delete_not_yours: "Only the person who recorded this check-in, or the office, can delete it. Ask the office to remove it.",
  // The edit path cannot clear hours yet (update_check_in keeps the old value when
  // hours are blank). Said, rather than letting a cleared box look saved.
  hours_not_cleared:
    "Hours can't be cleared once recorded — the check-in still shows the hours it had. Other changes were saved.",
  save_failed: "That wasn't saved. Nothing was changed — please try again.",
  // No database answer: it may or may not have committed.
  save_unconfirmed: "We couldn't confirm that was saved. Check the check-in below before trying again.",
};

export function isFieldError(v: unknown): v is FieldError {
  return typeof v === "string" && Object.prototype.hasOwnProperty.call(FIELD_ERROR_COPY, v);
}

/** Classify a PostgREST error from a field RPC. `code` is a SQLSTATE when the database answered. */
export function classifyFieldError(error: { code?: string; message?: string }): FieldError {
  const m = error.message ?? "";
  if (!error.code) return "save_unconfirmed";
  if (/only the person who recorded this check-in/i.test(m)) return "delete_not_yours";
  if (/requires a .* work order/i.test(m)) return "wrong_level";
  if (/not found or not accessible/i.test(m)) return "not_accessible";
  return "save_failed";
}
