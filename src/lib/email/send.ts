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

// RESEND_API_BASE exists for tests only — the same override verify-email-send.mjs
// takes — so the send path can be exercised against a stub without a real key.
// It is read per call and never NEXT_PUBLIC_; the env store is already the trust
// boundary for the key it would be sent with.
function resendUrl(): string {
  return `${(process.env.RESEND_API_BASE || "https://api.resend.com").replace(/\/+$/, "")}/emails`;
}
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
  /** Resend `attachments`: content is base64. Added 2026-09-14 for the signed copy. */
  attachments?: { filename: string; content: string }[];
  /**
   * What this email is FOR, as a short code (`signed_copy`, `email_check`). It
   * goes in the runtime log line and nowhere else. Never an address or a name.
   */
  purpose?: string;
};

// ── IS EMAIL SET UP? (2026-09-16) ────────────────────────────────────────────
// Track S keeps a copy of this check in src/lib/signing/email-setup.ts and asked
// for its home to be here, next to the send that refuses without it, so the two
// cannot drift. Presence by NAME only; no value leaves this function.
export type EmailSetupState = { configured: true } | { configured: false; missing: string[] };

export function emailSetup(): EmailSetupState {
  const missing = (["RESEND_API_KEY", "EMAIL_FROM"] as const).filter((name) => !process.env[name]);
  return missing.length === 0 ? { configured: true } : { configured: false, missing: [...missing] };
}

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

// ── ONE LOG LINE PER SEND (2026-09-16) ─────────────────────────────────────────
// Until today a send left no trace in the runtime log: "deployed" could not be
// told from "exercised", and it never had been. Every call now writes exactly one
// line, `[email.send] {json}`, carrying the outcome, the purpose code, the Resend
// id or status, and the elapsed time. It carries NO recipient, subject, body or
// key — a runtime log is read by more people than an inbox.
export async function sendEmail(input: SendEmailInput): Promise<SendEmailResult> {
  const started = Date.now();
  const result = await deliver(input);
  console.info(
    `[email.send] ${JSON.stringify({
      purpose: input.purpose ?? "unspecified",
      outcome: result.ok ? "sent" : result.reason,
      ...(result.ok ? { id: result.id } : {}),
      ...(!result.ok && result.reason === "rejected" ? { status: result.status } : {}),
      ...(!result.ok && result.reason === "not_configured" ? { missing: result.missing } : {}),
      ms: Date.now() - started,
    })}`
  );
  return result;
}

async function deliver(input: SendEmailInput): Promise<SendEmailResult> {
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
    res = await fetch(resendUrl(), {
      method: "POST",
      headers,
      body: JSON.stringify({
        from,
        to: input.to,
        subject: input.subject,
        html: input.html,
        text: input.text,
        ...(input.replyTo ? { reply_to: input.replyTo } : {}),
        ...(input.attachments?.length ? { attachments: input.attachments } : {}),
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
