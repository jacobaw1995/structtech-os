import "server-only";

// Transactional email. The one path every product email goes through: the
// remote-signing link, the signed copy, invites.  Track X, X-W1.13, 2026-09-14.
//
// WHAT EXISTED BEFORE THIS FILE, measured 2026-09-14: no email-sending code in
// src/, no email dependency in package.json, no email variable in any env file,
// and no Resend DKIM or return-path records in DNS. Nothing could send.
//
// NO NEW DEPENDENCY. Resend's REST API is one POST; `fetch` does it. Adding an SDK
// for one call would put a package on the security surface for no capability.
//
// THREE OUTCOMES, KEPT APART ON PURPOSE. A caller must be able to tell "email is
// not set up" from "Resend refused this message" from "Resend could not be
// reached", because each wants a different sentence in front of the user and a
// different fix. Collapsing them into `false` is how a configuration gap gets
// reported to a customer as "we couldn't send your document, try again" — a
// confident message for the wrong cause.
//   not_configured — RESEND_API_KEY or EMAIL_FROM is absent. Nothing was sent.
//   rejected       — Resend answered 4xx. The request is wrong; retrying won't help.
//   unavailable    — 5xx, network failure or timeout. Retrying may help.
//
// The key is read from the environment on every call and never logged. It is not
// NEXT_PUBLIC_, so Next.js never inlines it into a browser bundle, and
// `server-only` fails the build if a client component imports this file.
//
// UPSTREAM TEXT IS REDACTED BEFORE IT IS RETURNED. The first version of this file
// claimed the key was never included in an error, and passed Resend's message
// through verbatim. A hostile check — an upstream that echoes the key back — got
// the key out in 2 of 5 outcomes ("API key <key> is invalid", a gateway quoting the
// Bearer header). The claim was a sentence, not a property. Every string that
// originates outside this file now goes through redact().
//
// BOUNDED. A send is awaited inside a server action; an unbounded one would hang
// the request exactly as the auth refresh did (bounded-fetch.ts). 10 s.

const RESEND_URL = "https://api.resend.com/emails";
const SEND_TIMEOUT_MS = 10_000;

export type SendEmailInput = {
  to: string | string[];
  subject: string;
  html: string;
  text: string;
  replyTo?: string;
  /**
   * Resend deduplicates on this header, so a retried send of the same logical
   * message (a signed copy, an invite) is delivered once. Derive it from what
   * the email IS — e.g. `signed-copy:<signature id>` — never from a timestamp.
   */
  idempotencyKey?: string;
};

export type SendEmailResult =
  | { ok: true; id: string }
  | { ok: false; reason: "not_configured"; missing: string[] }
  | { ok: false; reason: "rejected"; status: number; message: string }
  | { ok: false; reason: "unavailable"; detail: string };

/**
 * Strip the literal key, any Resend-shaped token and any Bearer credential.
 * The literal replacement is skipped for anything too short to be a credential:
 * exercised with a one-character test key, an unguarded split redacted every
 * matching letter and turned "API key is invalid" into "API [redacted]ey is
 * invalid" — a redaction that destroys the diagnostic is its own wrong answer.
 * Real Resend keys are `re_`-prefixed and long, so the pattern still catches them.
 */
function redact(text: string, key: string): string {
  const literal = key.length >= 12 ? text.split(key).join("[redacted]") : text;
  return literal
    .replace(/\bre_[A-Za-z0-9_]{8,}/g, "[redacted]")
    .replace(/Bearer\s+\S+/gi, "Bearer [redacted]");
}

export async function sendEmail(input: SendEmailInput): Promise<SendEmailResult> {
  const key = process.env.RESEND_API_KEY;
  const from = process.env.EMAIL_FROM;
  const missing = [!key && "RESEND_API_KEY", !from && "EMAIL_FROM"].filter(
    (m): m is string => Boolean(m)
  );
  if (missing.length) return { ok: false, reason: "not_configured", missing };

  const headers: Record<string, string> = {
    Authorization: `Bearer ${key}`,
    "Content-Type": "application/json",
  };
  if (input.idempotencyKey) headers["Idempotency-Key"] = input.idempotencyKey;

  let res: Response;
  try {
    res = await fetch(RESEND_URL, {
      method: "POST",
      headers,
      body: JSON.stringify({
        from,
        to: input.to,
        subject: input.subject,
        html: input.html,
        text: input.text,
        ...(input.replyTo ? { reply_to: input.replyTo } : {}),
      }),
      signal: AbortSignal.timeout(SEND_TIMEOUT_MS),
      cache: "no-store",
    });
  } catch (err) {
    const name = (err as Error)?.name ?? "Error";
    return {
      ok: false,
      reason: "unavailable",
      detail: name === "TimeoutError" ? `no response within ${SEND_TIMEOUT_MS}ms` : name,
    };
  }

  let body: unknown = null;
  try {
    body = await res.json();
  } catch {
    // A non-JSON body is reported by status below; it is never echoed back.
  }

  if (res.ok) {
    const id = (body as { id?: unknown } | null)?.id;
    if (typeof id === "string" && id.length > 0) return { ok: true, id };
    // 2xx without an id is not a confirmed send. Do not tell a caller it went.
    return { ok: false, reason: "unavailable", detail: `HTTP ${res.status} without a message id` };
  }

  const resendMessage =
    typeof (body as { message?: unknown } | null)?.message === "string"
      ? (body as { message: string }).message
      : null;
  const safe = resendMessage === null ? null : redact(resendMessage, key as string);
  if (res.status >= 400 && res.status < 500) {
    return { ok: false, reason: "rejected", status: res.status, message: safe ?? `HTTP ${res.status}` };
  }
  return {
    ok: false,
    reason: "unavailable",
    detail: safe ? `HTTP ${res.status}: ${safe}` : `HTTP ${res.status}`,
  };
}
