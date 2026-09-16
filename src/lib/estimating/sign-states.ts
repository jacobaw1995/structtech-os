// Why a signature did not land, as a CODE the present page looks up.
// Track X, X-W1.16, 2026-09-15.
//
// CONTROLLER RULING 2026-09-15: a URL parameter is a code that gets looked up; the
// text always comes from us; no URL parameter is ever rendered as text. Before
// this file signEstimate put the database's own message in `?error=` and the
// present page ignored it, so a customer whose signature failed saw nothing at
// all — and rendering it as-is would have let any link put words on a
// customer-facing page.
//
// The messages matched below are the ones sign_estimate() and the signatures
// triggers raise (baseline + 20260915004736, read 2026-09-15). A message that
// matches none of them is still named — `sign_failed` — never shown.

export type SignFailure = "already_signed" | "not_presented" | "not_accessible" | "sign_failed" | "sign_unconfirmed";

export const SIGN_FAILURE_COPY: Record<SignFailure, string> = {
  already_signed: "This estimate has already been signed. A second signature isn't recorded.",
  not_presented: "This estimate isn't ready to sign — it needs to be presented again first. Nothing was signed.",
  not_accessible: "This estimate couldn't be opened for signing from this account. Nothing was signed.",
  sign_failed: "The signature wasn't saved. Nothing was signed — please try again.",
  // No database answer: it may or may not have committed. One signature per
  // estimate is enforced by the table, so signing again cannot record two.
  sign_unconfirmed:
    "We couldn't confirm the signature was saved. Check whether the estimate shows as signed before signing again.",
};

export function isSignFailure(v: unknown): v is SignFailure {
  return typeof v === "string" && Object.prototype.hasOwnProperty.call(SIGN_FAILURE_COPY, v);
}

/** Classify a PostgREST error from sign_estimate. `code` is a SQLSTATE when the database answered. */
export function classifySignError(error: { code?: string; message?: string }): SignFailure {
  const message = error.message ?? "";
  if (!error.code) return "sign_unconfirmed";
  if (/already signed/i.test(message)) return "already_signed";
  if (/must be presented/i.test(message)) return "not_presented";
  if (/not found/i.test(message)) return "not_accessible";
  return "sign_failed";
}
