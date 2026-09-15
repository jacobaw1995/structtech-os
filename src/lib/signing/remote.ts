// SEND FOR SIGNATURE — the office side's state model. U-W1.15, 2026-09-14.
// PURE and client-safe: no env, no client, no session.
//
// THE STATE IS NOT A BOOLEAN, and a state the data cannot show is NOT RENDERED
// AS A GUESS. Measured 2026-09-14, before building:
//   - `signatures` (estimate_id, signer_name, signer_role, signed_at, sign_token)
//     is the only signing record. All 4 live rows have sign_token NULL.
//   - There is NO table, column or function that records a SEND: nothing says an
//     estimate was emailed, to whom, when, whether the link was opened, or when it
//     expires. Track S's remote-signing token model has not landed.
// So today only three things are knowable: signed, void, and "this system has
// nowhere a send could be recorded". "Not sent" is NOT one of them — rendering
// it would assert an absence the data cannot see (§7.1). It becomes knowable the
// moment a send record exists, and this model already takes one.

/**
 * The failure arms of Track X's `SendEmailResult` (src/lib/email/send.ts,
 * X-W1.13a). A COPY, because that file is on track-x and not yet on main. When
 * it lands, import the type from there and delete this one; the shapes are
 * identical so nothing else changes.
 */
export type SendFailure =
  | { reason: "not_configured"; missing: string[] }
  | { reason: "rejected"; status: number; message: string }
  | { reason: "unavailable"; detail: string };

/** One attempt to send the signing link — the shape a send record will need. */
export type SendRecord = {
  attemptedAt: string;
  to: string;
  /** Null when the attempt succeeded. */
  failure: SendFailure | null;
  /** Null when the link does not expire. */
  expiresAt: string | null;
  /**
   * `undefined` means opens are NOT TRACKED, and nothing is said about them.
   * `null` means tracked and not opened. A string is when it was first opened.
   */
  openedAt?: string | null;
};

export type EmailSetup = { configured: true } | { configured: false; missing: string[] };

export type SigningInput = {
  estimateStatus: string;
  signedAt: string | null;
  signerName: string | null;
  /** `null` = there is no source of send records at all (today). */
  sendRecords: SendRecord[] | null;
  now: number;
};

export type SigningState =
  | { kind: "signed"; signedAt: string; signerName: string | null }
  | { kind: "void" }
  | { kind: "no_send_record_source" }
  | { kind: "not_sent" }
  | { kind: "send_failed"; attempt: SendRecord; failure: SendFailure }
  | { kind: "awaiting"; attempt: SendRecord; opened: "opened" | "not_opened" | "not_tracked" }
  | { kind: "link_expired"; attempt: SendRecord };

export function signingState(input: SigningInput): SigningState {
  // A signature is the strongest fact and wins over any send history.
  if (input.signedAt) return { kind: "signed", signedAt: input.signedAt, signerName: input.signerName };
  if (input.estimateStatus === "void") return { kind: "void" };
  if (input.sendRecords === null) return { kind: "no_send_record_source" };
  if (input.sendRecords.length === 0) return { kind: "not_sent" };

  const latest = [...input.sendRecords].sort((a, b) => Date.parse(b.attemptedAt) - Date.parse(a.attemptedAt))[0];
  if (latest.failure) return { kind: "send_failed", attempt: latest, failure: latest.failure };
  if (latest.expiresAt && Date.parse(latest.expiresAt) <= input.now) return { kind: "link_expired", attempt: latest };
  return {
    kind: "awaiting",
    attempt: latest,
    opened: latest.openedAt === undefined ? "not_tracked" : latest.openedAt === null ? "not_opened" : "opened",
  };
}

/**
 * THREE FAILURES, THREE SENTENCES. "Email is not set up" is a setup gap, not a
 * failed delivery; "refused" will be refused again unchanged; "unreachable" may
 * work on a retry. Collapsing them into "couldn't send" gives the wrong fix.
 * Variable NAMES only — never a value.
 */
export function failureText(f: SendFailure): { headline: string; detail: string; retryHelps: boolean } {
  switch (f.reason) {
    case "not_configured":
      return {
        headline: "Email is not set up, so nothing was sent",
        detail: `This workspace cannot send email until ${joinNames(f.missing)} ${f.missing.length === 1 ? "is" : "are"} set. That is setup, not a failed delivery.`,
        retryHelps: false,
      };
    case "rejected":
      return {
        headline: "The email service refused this message",
        detail: `It answered ${f.status}: ${f.message}. Sending the same message again will be refused again.`,
        retryHelps: false,
      };
    case "unavailable":
      return {
        headline: "The email service could not be reached",
        detail: `${f.detail.charAt(0).toUpperCase()}${f.detail.slice(1)}. Nothing was confirmed as sent. Trying again may work.`,
        retryHelps: true,
      };
  }
}

export function joinNames(names: string[]): string {
  if (names.length <= 1) return names[0] ?? "";
  return `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`;
}
