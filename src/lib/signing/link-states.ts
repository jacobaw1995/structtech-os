// THE CUSTOMER SIGNING LINK — what the database says, and every sentence the
// signer can see. Track U, U-W1.18, 2026-09-16. PURE and client-safe.
//
// READ FROM THE LIVE BODIES (20260915004736 + later), not from a summary:
//   signing_link_view(token)  → { state: 'ready', business, expires_at, document, document_version }
//                             | { state: 'already_signed', business, signed_at }
//                             | { state: 'expired', business, expired_at }
//                             | { state: 'document_changed', business }
//                             | { state: 'unavailable' }
//   sign_estimate_by_link(…)  → the same states, or { state: 'signed', business, signed_at, signature_id },
//                               or RAISES one of three sentences for a missing name, role or drawing.
//
// "UNAVAILABLE" IS FOUR THINGS ON PURPOSE. An unknown token, a malformed one, a
// REVOKED one (including a link replaced by a newer send) and an estimate that is
// no longer presented all return the byte-identical {"state":"unavailable"} — Track
// S's no-enumeration condition. So "revoked" is NOT a state this page can name: the
// database will not say it, and inventing it would tell a stranger which tokens
// were once real. The sentence below covers all four without claiming which.
//
// NO URL PARAMETER IS RENDERED AS TEXT (controller ruling 2026-09-15). The page
// reads `?r=` and `?copy=` only as CODES checked against the maps below; a value
// that is not a key renders nothing. Words come from this file, and names/dates
// come from the database answer — never from the address bar.

import { SIGN_FAILURE_COPY, classifySignError } from "@/lib/estimating/sign-states";

export type SigningDocument = {
  business: string | null;
  estimate_number: string | null;
  estimate_date: string | null;
  valid_until: string | null;
  contact_name: string | null;
  site_address: string | null;
  notes_terms: string | null;
  subtotal: number | null;
  tax_rate: number | null;
  tax_amount: number | null;
  total: number | null;
  lines: { description: string | null; quantity: number | null; unit: string | null; unit_price: number | null; line_total: number | null }[];
};

export type LinkView =
  | { state: "ready"; business: string | null; expires_at: string; document: SigningDocument; document_version: string }
  | { state: "already_signed"; business: string | null; signed_at: string | null }
  | { state: "expired"; business: string | null; expired_at: string | null }
  | { state: "document_changed"; business: string | null }
  | { state: "unavailable" };

/** Anything the database returns that is not one of the shapes above is treated as unavailable. */
export function parseLinkView(data: unknown): LinkView {
  const v = (data ?? {}) as Record<string, unknown>;
  const str = (k: string) => (typeof v[k] === "string" ? (v[k] as string) : null);
  switch (v.state) {
    case "ready":
      if (typeof v.document === "object" && v.document && str("document_version") && str("expires_at")) {
        return {
          state: "ready",
          business: str("business"),
          expires_at: str("expires_at") as string,
          document: v.document as SigningDocument,
          document_version: str("document_version") as string,
        };
      }
      return { state: "unavailable" };
    case "already_signed":
      return { state: "already_signed", business: str("business"), signed_at: str("signed_at") };
    case "expired":
      return { state: "expired", business: str("business"), expired_at: str("expired_at") };
    case "document_changed":
      return { state: "document_changed", business: str("business") };
    default:
      return { state: "unavailable" };
  }
}

// ---------------------------------------------------------------------------
// OUTCOME OF PRESSING "SIGN" — a code in `?r=`, looked up here.
// ---------------------------------------------------------------------------
export type SignOutcome =
  | "signed"
  | "name_missing"
  | "role_missing"
  | "drawing_missing"
  | "document_changed"
  | "sign_failed"
  | "sign_unconfirmed";

export const SIGN_OUTCOME_COPY: Record<Exclude<SignOutcome, "signed">, string> = {
  name_missing: "Enter the name of the person signing. Nothing was signed.",
  role_missing: "Say who is signing — for example, Homeowner. Nothing was signed.",
  drawing_missing: "Draw your signature in the box before signing. Nothing was signed.",
  document_changed:
    "The estimate changed while this page was open, so nothing was signed. The version below is the current one — read it before signing.",
  // Track X's words for the two outcomes both signing paths share (sign-states.ts).
  sign_failed: SIGN_FAILURE_COPY.sign_failed,
  sign_unconfirmed: SIGN_FAILURE_COPY.sign_unconfirmed,
};

export function isSignOutcome(v: unknown): v is SignOutcome {
  return v === "signed" || (typeof v === "string" && Object.prototype.hasOwnProperty.call(SIGN_OUTCOME_COPY, v));
}

/** Classify an error raised by sign_estimate_by_link. Its three validation sentences are its own. */
export function classifyLinkSignError(error: { code?: string; message?: string }): SignOutcome {
  const m = error.message ?? "";
  if (error.code) {
    if (/name of the person signing/i.test(m)) return "name_missing";
    if (/who is signing/i.test(m)) return "role_missing";
    if (/draw a signature/i.test(m)) return "drawing_missing";
  }
  const shared = classifySignError(error);
  return shared === "sign_unconfirmed" ? "sign_unconfirmed" : "sign_failed";
}

// ---------------------------------------------------------------------------
// THE SIGNED COPY, as the signer is told about it. Codes are Track X's
// SignedCopyState values (signed-copy.ts); the sentences are for a customer, so
// the provider distinctions an office needs collapse to "it did not go out" —
// the signature is saved in every case, and each sentence says so first.
// ---------------------------------------------------------------------------
export function copyLineForSigner(copy: string | undefined, business: string | null): string | null {
  const who = business ?? "the business that sent this link";
  switch (copy) {
    case "sent":
      return "A signed copy has been emailed to you.";
    case "no_email":
      return `No email address is on file, so no copy was emailed. Ask ${who} for your signed copy.`;
    case "not_configured":
    case "rejected":
    case "unavailable":
    case "render_failed":
      return `Your signature is saved. The emailed copy did not go out, and ${who} has a record that a copy is owed to you.`;
    default:
      return null;
  }
}
