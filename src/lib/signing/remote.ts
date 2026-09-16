// SEND FOR SIGNATURE — the office side's state model. U-W1.15 (2026-09-14),
// rebuilt U-W1.19 (2026-09-16) on Track S's link table. PURE and client-safe.
//
// WHAT IS KNOWABLE, measured 2026-09-16:
//   estimate_sign_links (member-readable with view_estimates + view_financials):
//     created_at, expires_at, revoked_at, used_at — one row per link issued.
//   signatures: signer and signed_at.
// Nothing records whether an email was OPENED, so this model says nothing about
// opens. Nothing records a send attempt either — so the send action makes a
// LIVE LINK MEAN "THE EMAIL SERVICE ACCEPTED IT": when a send fails in any way,
// the action revokes the link it just created (lib/signing/send-actions.ts). A
// live link is therefore a sent one, and a failed send leaves a cancelled link
// plus a one-time result code on the redirect.
//
// NO URL TEXT. The result of a send arrives as `?send=<code>` and is looked up
// here; a code not in the map renders nothing. The email service's own message
// is never put in a URL, so the office copy for "refused" names the likely fix
// instead of quoting it.

import type { SendEmailResult } from "@/lib/email/send";

/** Track X's three failure reasons (src/lib/email/send.ts) — imported, not copied. */
export type SendFailureReason = Extract<SendEmailResult, { ok: false }>["reason"];

export type LinkRow = {
  created_at: string;
  expires_at: string;
  revoked_at: string | null;
  used_at: string | null;
};

export type SigningInput = {
  estimateStatus: string;
  signedAt: string | null;
  signerName: string | null;
  /** `null` when the link table could not be read — said, never guessed. */
  links: LinkRow[] | null;
  now: number;
};

export type SigningState =
  | { kind: "signed"; signedAt: string; signerName: string | null; viaLink: boolean }
  | { kind: "void" }
  | { kind: "not_presented"; status: string }
  | { kind: "unreadable" }
  | { kind: "not_sent" }
  | { kind: "awaiting"; link: LinkRow }
  | { kind: "link_expired"; link: LinkRow }
  | { kind: "link_cancelled"; link: LinkRow };

export function signingState(input: SigningInput): SigningState {
  const latest = input.links?.slice().sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at))[0];
  // A signature is the strongest fact and wins over any link history.
  if (input.signedAt) {
    return {
      kind: "signed",
      signedAt: input.signedAt,
      signerName: input.signerName,
      viaLink: Boolean(input.links?.some((l) => l.used_at)),
    };
  }
  if (input.estimateStatus === "void") return { kind: "void" };
  if (input.estimateStatus !== "presented") return { kind: "not_presented", status: input.estimateStatus };
  if (input.links === null) return { kind: "unreadable" };
  if (!latest) return { kind: "not_sent" };
  if (latest.revoked_at) return { kind: "link_cancelled", link: latest };
  if (Date.parse(latest.expires_at) <= input.now) return { kind: "link_expired", link: latest };
  return { kind: "awaiting", link: latest };
}

// ---------------------------------------------------------------------------
// THE RESULT OF PRESSING "SEND" — `?send=<code>`.
// ---------------------------------------------------------------------------
export type SendResult =
  | "sent"
  | SendFailureReason
  | "no_email"
  | "not_presented"
  | "already_signed"
  | "not_permitted"
  | "link_failed"
  | "cancel_failed";

export const SEND_RESULT_COPY: Record<SendResult, { headline: string; detail: string; tone: "ok" | "warn" }> = {
  sent: {
    headline: "Sent for signature",
    detail: "The email service accepted the message with the signing link. That is acceptance, not proof it reached the inbox.",
    tone: "ok",
  },
  // THREE FAILURES, THREE SENTENCES, never "couldn't send".
  not_configured: {
    headline: "Email is not set up, so nothing was sent",
    detail: "This workspace has no email sending configured. That is setup still to be done, not a failed delivery. The link that was created has been cancelled.",
    tone: "warn",
  },
  rejected: {
    headline: "The email service refused this message",
    detail: "Check the customer's email address on this estimate. Sending the same message again will be refused again. The link that was created has been cancelled.",
    tone: "warn",
  },
  unavailable: {
    headline: "The email service could not be reached",
    detail: "It may or may not have gone out. The link in it has been cancelled so it cannot be signed — send again to issue a working one. Trying again may work.",
    tone: "warn",
  },
  no_email: {
    headline: "Nothing was sent",
    detail: "This estimate has no customer email address. Add one, then send.",
    tone: "warn",
  },
  not_presented: {
    headline: "Nothing was sent",
    detail: "Only a presented estimate can be sent for signature. Present it first.",
    tone: "warn",
  },
  already_signed: {
    headline: "Nothing was sent",
    detail: "This estimate is already signed.",
    tone: "warn",
  },
  not_permitted: {
    headline: "Nothing was sent",
    detail: "Your role cannot send estimates for signature in this workspace.",
    tone: "warn",
  },
  link_failed: {
    headline: "Nothing was sent",
    detail: "The signing link could not be created. Try again.",
    tone: "warn",
  },
  // The send failed AND the link could not be cancelled: a live link exists that
  // was not confirmed delivered. The one case the "live means sent" rule cannot
  // hold, so it is said outright.
  cancel_failed: {
    headline: "The send failed, and its link is still live",
    detail: "The email did not go out as far as we can tell, but the link could not be cancelled. Sending again replaces it with a new one.",
    tone: "warn",
  },
};

export function isSendResult(v: unknown): v is SendResult {
  return typeof v === "string" && Object.prototype.hasOwnProperty.call(SEND_RESULT_COPY, v);
}

export const LINK_VALID_DAYS = 14;
