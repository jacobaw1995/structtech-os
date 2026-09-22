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
  | "crew_required"
  | "not_accessible"
  | "wrong_level"
  | "delete_not_yours"
  | "change_not_yours"
  | "hours_use_clear"
  | "save_failed"
  | "save_unconfirmed";

export const FIELD_ERROR_COPY: Record<FieldError, string> = {
  // Track S's own sentence, reached by its own hint. Not a paraphrase.
  crew_required: "Choose a crew, or type who is doing the work.",
  not_accessible: "That item couldn't be found for your account. Nothing was changed.",
  // U-W1.24 — was "This is not a trade work order, so it can't take check-ins
  // or a packet." "Trade work order" is the office's distinction from a master,
  // and a crew member can neither say it nor act on it. The sentence says what
  // happened to what he was looking at.
  wrong_level: "This job can't take check-ins or a packet. Nothing was changed.",
  delete_not_yours: "Only the person who recorded this check-in, or the office, can delete it. Ask the office to remove it.",
  change_not_yours: "Only the person who recorded this check-in, or the office, can change it. Ask the office to correct it.",
  // update_check_in keeps the old figure when hours are blank; clearing is its own
  // action (clear_check_in_hours, Track S 2026-09-17). Said, so an emptied box is
  // never mistaken for a save.
  hours_use_clear:
    "Hours weren't changed by emptying the box. To mark them not recorded, use Clear hours. Other changes were saved.",
  save_failed: "That wasn't saved. Nothing was changed — please try again.",
  // No database answer: it may or may not have committed.
  save_unconfirmed: "We couldn't confirm that was saved. Check the check-in below before trying again.",
};

export function isFieldError(v: unknown): v is FieldError {
  return typeof v === "string" && Object.prototype.hasOwnProperty.call(FIELD_ERROR_COPY, v);
}

/**
 * Classify a PostgREST error from a field RPC. `code` is a SQLSTATE when the
 * database answered.
 *
 * U-W1.28 (2026-09-22) — THE HINT IS READ FIRST, AND UNTIL TODAY IT WAS NOT READ
 * AT ALL. `create_check_in` raises 'choose a crew, or type who is doing the
 * work' with `using hint = 'crew_required'`; this function looked only at `code`
 * and `message`, so the one refusal that named its own reason fell through to
 * save_failed — "That wasn't saved. Nothing was changed — please try again." A
 * crew member was told to retry the thing that cannot work. Track X found and
 * fixed its half and named this one. The same hint-first read already exists in
 * this tree, in lib/crews/crew-states.ts; this file simply never got it.
 *
 * MEASURED BEFORE THE FIX, across the 11 RPCs this file classifies plus
 * assert_work_order_level: the database raises SEVEN distinct refusals, and
 * exactly ONE of them carries a hint. This function had a sentence for ZERO
 * hints. So the hint channel is now read — and the other six are S's to add.
 *
 * WHY THE MESSAGE REGEXES STAY, AND WHY THEY ARE THE SECOND CHOICE. They are a
 * coupling to PROSE: six of the seven refusals can only be told apart by their
 * wording, and S may reword any of them at any time without touching a caller.
 * That is not theoretical — two of these messages have ALREADY been reworded
 * since these patterns were written ("…can delete it" gained "— ask the office
 * to remove it"), and they still matched only because the added words landed
 * after the part being matched. A hint is a contract; a sentence is not. Every
 * new refusal should arrive with a hint, and then this fallback shrinks.
 */
export function classifyFieldError(error: { code?: string; message?: string; hint?: string | null }): FieldError {
  const m = error.message ?? "";
  // No SQLSTATE means the database never answered — it may or may not have
  // committed, and that is a different sentence from any refusal.
  if (!error.code) return "save_unconfirmed";
  // A hint we know is the database naming its own reason: believe it.
  if (isFieldError(error.hint)) return error.hint;
  if (/only the person who recorded this check-in.*can delete/i.test(m)) return "delete_not_yours";
  if (/only the person who recorded this check-in.*can change/i.test(m)) return "change_not_yours";
  if (/requires a .* work order/i.test(m)) return "wrong_level";
  if (/not found or not accessible/i.test(m)) return "not_accessible";
  return "save_failed";
}
