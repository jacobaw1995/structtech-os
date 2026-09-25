// Why a field action did not land, as a CODE the job page looks up.
// Track U, U-W1.20 (2026-09-17) · hints taken U-W1.33 (2026-09-25).
//
// CONTROLLER RULING 2026-09-15: a URL parameter is a code that gets looked up;
// the text always comes from us; no URL parameter is ever rendered as text.
//
// THE HINT IS THE CONTRACT, AND IT NOW EXISTS. Measured 2026-09-22 across the
// eleven RPCs this file classifies plus assert_work_order_level: SEVEN distinct
// refusals, exactly ONE carrying a hint, and this file read `code` and `message`
// only — so it had a sentence for ZERO hints. Track S closed that in migration
// 20260923204542. Measured again today over the same functions: 27 raise sites,
// 27 of them hinted, 7 distinct hints. So the codes below ARE S's hint names,
// one for one, and classification is a lookup rather than a guess.
//
// THE PROSE REGEXES STAY, AS THE FALLBACK AND ONLY THAT. They are a coupling to
// wording S may change without touching a caller — and two of them had already
// drifted once ("…can delete it" gained "— ask the office to remove it") and
// matched afterwards only because the new words landed after the matched part.
// They are kept for a deployment whose database predates the hints, and for a
// future raise that arrives without one. Every path they cover now resolves to
// the SAME code the hint would give, so the fallback cannot disagree with the
// contract.
//
// THE `not_found` COLLAPSE IS CLOSED BY THIS. One code used to answer for a
// missing check-in, a missing packet and a missing work order alike, because
// the message was all three had in common. S's hints separate them, so the
// screen can now say WHICH thing was not found.

export type FieldError =
  // Track S's hint names, verbatim (migration 20260923204542).
  | "check_in_not_found"
  | "production_packet_not_found"
  | "work_order_not_found"
  | "wrong_work_order_level"
  | "delete_needs_author_or_office"
  | "change_needs_author_or_office"
  | "not_signed_in"
  | "qc_work_order_not_recordable"
  | "crew_required"
  // OURS, and not refusals: these describe THIS surface's own situation, which
  // the database has no sentence for because it never saw the request.
  | "hours_use_clear"
  | "save_failed"
  | "save_unconfirmed";

export const FIELD_ERROR_COPY: Record<FieldError, string> = {
  check_in_not_found: "That check-in couldn't be found for your account. Nothing was changed.",
  production_packet_not_found: "That packet couldn't be found for your account. Nothing was changed.",
  work_order_not_found: "That job couldn't be found for your account. Nothing was changed.",
  wrong_work_order_level: "This job can't take check-ins or a packet. Nothing was changed.",
  delete_needs_author_or_office:
    "Only the person who recorded this check-in, or the office, can delete it. Ask the office to remove it.",
  change_needs_author_or_office:
    "Only the person who recorded this check-in, or the office, can change it. Ask the office to correct it.",
  not_signed_in: "You're signed out. Sign in and try again — nothing was changed.",
  qc_work_order_not_recordable: "Checks can't be recorded on this job. Nothing was recorded.",
  crew_required: "Choose a crew, or type who is doing the work.",
  // update_check_in keeps the old figure when hours are blank; clearing is its
  // own action (clear_check_in_hours). Said, so an emptied box is never mistaken
  // for a save.
  hours_use_clear:
    "Hours weren't changed by emptying the box. To mark them not recorded, use Clear hours. Other changes were saved.",
  save_failed: "That wasn't saved. Nothing was changed — please try again.",
  // No database answer at all: it may or may not have committed.
  save_unconfirmed: "We couldn't confirm that was saved. Check the check-in below before trying again.",
};

export function isFieldError(v: unknown): v is FieldError {
  return typeof v === "string" && Object.prototype.hasOwnProperty.call(FIELD_ERROR_COPY, v);
}

/**
 * Classify a PostgREST error from a field RPC.
 *
 * ORDER MATTERS AND IS THE POINT:
 *   1. no SQLSTATE  -> the database never answered; it may or may not have
 *      committed, which is a different sentence from any refusal.
 *   2. a hint we know -> the database naming its own reason. Believe it.
 *   3. the prose fallback, for a database older than the hints.
 *   4. named, never shown as text.
 *
 * An UNKNOWN hint falls through to the prose rather than being trusted: a hint
 * this file has never seen has no sentence, and inventing one would be worse
 * than reading the message.
 */
export function classifyFieldError(error: { code?: string; message?: string; hint?: string | null }): FieldError {
  if (!error.code) return "save_unconfirmed";
  if (isFieldError(error.hint)) return error.hint;
  const m = error.message ?? "";
  if (/only the person who recorded this check-in.*can delete/i.test(m)) return "delete_needs_author_or_office";
  if (/only the person who recorded this check-in.*can change/i.test(m)) return "change_needs_author_or_office";
  if (/requires a .* work order/i.test(m)) return "wrong_work_order_level";
  if (/check-in not found or not accessible/i.test(m)) return "check_in_not_found";
  if (/production packet not found or not accessible/i.test(m)) return "production_packet_not_found";
  if (/work order not found or not accessible/i.test(m)) return "work_order_not_found";
  if (/not signed in/i.test(m)) return "not_signed_in";
  return "save_failed";
}
