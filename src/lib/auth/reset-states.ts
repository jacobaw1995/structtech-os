// Every state the password-reset flow can be in, and the one sentence each shows.
// Track X, X-W1.14, 2026-09-14.
//
// One place, because each state is a claim about WHY, and a claim that drifts
// between two pages is how a user gets told their link expired when the sign-in
// service was merely slow. The states are split by what the user should DO,
// never merged into "something went wrong":
//
//   the feature is off        → ask an administrator; do not wait for mail
//   the request was accepted  → check your inbox (worded so it is true whether or
//                               not an account exists — the API cannot tell us)
//   we could not confirm it   → a link may still arrive; wait before retrying
//   the link is bad/expired   → request a new one
//   the link is in the wrong browser → open it where you asked for it
//   sign-in did not answer    → try again shortly; your link is still good
//
// MEASURED 2026-09-14, before this flow existed: GoTrue's /auth/v1/recover
// answered HTTP 200 `{}` for an address with no account — byte-identical to a
// real send. The response can never be used to decide whether mail left, which is
// why "off" is a configuration fact (AUTH_EMAIL_ENABLED) rather than an inference.

export type ResetState =
  | "off"
  | "sent"
  | "unconfirmed"
  | "rate_limited"
  | "mailer_restricted"
  | "invalid_email"
  | "request_rejected"
  | "link_invalid"
  | "link_expired"
  | "link_other_browser"
  | "auth_unreachable"
  | "mismatch"
  | "weak_password"
  | "same_password"
  | "update_unconfirmed"
  | "update_rejected"
  | "done"
  | "done_sessions_unconfirmed";

export type StateCopy = { tone: "info" | "warn"; title: string; body: string };

export const RESET_COPY: Record<ResetState, StateCopy> = {
  off: {
    tone: "warn",
    title: "Password reset by email isn't switched on yet",
    body: "This workspace can't send reset emails yet, so nothing will arrive if you ask for one. Ask your administrator to reset your password for you.",
  },
  sent: {
    tone: "info",
    title: "Check your email",
    body: "If an account exists for that address, a link to reset your password is on its way. It can take a few minutes — check your spam folder too. The link works once.",
  },
  unconfirmed: {
    tone: "warn",
    title: "We couldn't confirm your request went through",
    body: "The sign-in service didn't answer in time. A reset email may still arrive — wait a few minutes and check your inbox before asking again.",
  },
  rate_limited: {
    tone: "warn",
    title: "Too many reset requests",
    body: "Reset emails for this address are paused for a little while. Wait a few minutes, then try again — or use the link from an email you already received.",
  },
  // MEASURED 2026-09-16: production reset mail leaves via Supabase's BUILT-IN mailer
  // (auth log mail_from noreply@mail.app.supabase.io), not custom SMTP. Supabase
  // documents that mailer as refusing any address outside the Supabase
  // organization's team, with code email_address_not_authorized. Until custom SMTP
  // exists that is every crew member and every client, so it gets its own sentence
  // instead of "refused". The distinct answer reveals an account exists; GoTrue
  // already gives that same distinct answer to anyone holding the public anon key,
  // so blurring it here would hide nothing and mislead the person waiting for mail.
  mailer_restricted: {
    tone: "warn",
    title: "Reset emails can't be sent to this address yet",
    body: "This workspace's email isn't fully set up, so no reset email will arrive. Ask your administrator to reset your password for you.",
  },
  invalid_email: {
    tone: "warn",
    title: "That doesn't look like an email address",
    body: "Check the address and try again.",
  },
  request_rejected: {
    tone: "warn",
    title: "The reset request was refused",
    body: "The sign-in service rejected the request. Try again, and if it keeps happening ask your administrator.",
  },
  link_invalid: {
    tone: "warn",
    title: "This reset link is incomplete",
    body: "The link is missing part of what it needs — often from being copied or wrapped by an email program. Request a new one below.",
  },
  link_expired: {
    tone: "warn",
    title: "This reset link has expired or was already used",
    body: "Each link works once and only for a short time. Request a new one below.",
  },
  link_other_browser: {
    tone: "warn",
    title: "Open the link in the browser you asked from",
    body: "For security, a reset link only works in the same browser where you requested it. Open the email on that device, or request a new link from the browser you're using now.",
  },
  auth_unreachable: {
    tone: "warn",
    title: "The sign-in service didn't answer",
    body: "Nothing is wrong with your link — we just couldn't reach the service that checks it. Wait a minute and open the link again.",
  },
  mismatch: {
    tone: "warn",
    title: "The passwords don't match",
    body: "Type the same new password in both boxes.",
  },
  weak_password: {
    tone: "warn",
    title: "Choose a stronger password",
    body: "That password doesn't meet this workspace's requirements.",
  },
  same_password: {
    tone: "warn",
    title: "That's your current password",
    body: "Choose a password you haven't used for this account.",
  },
  update_unconfirmed: {
    tone: "warn",
    title: "We couldn't confirm your password changed",
    body: "The sign-in service didn't answer in time. Try signing in with your new password; if that doesn't work, request a new reset link.",
  },
  update_rejected: {
    tone: "warn",
    title: "Your password wasn't changed",
    body: "The sign-in service refused the change. Request a new reset link and try again.",
  },
  done: {
    tone: "info",
    title: "Your password has been changed",
    body: "You've been signed out everywhere. Sign in with your new password.",
  },
  // The password DID change; only the follow-up failed. Said separately so a user
  // who reset because they suspected someone else had their password knows that
  // other devices may still be signed in.
  done_sessions_unconfirmed: {
    tone: "warn",
    title: "Your password has been changed — but other devices may still be signed in",
    body: "We couldn't confirm that every other signed-in device was signed out. Sign in with your new password, and if you reset because you think someone else had it, sign out on your other devices yourself.",
  },
};

// WHY A WEAK PASSWORD CARRIES CODES, NOT TEXT. The first version put GoTrue's
// message in `?detail=` and rendered it. That renders whatever a URL says, on our
// domain, under our heading: /reset-password?state=weak_password&detail=<anything>
// is a phishing line nobody wrote. Found by exercising the state, not by reading it.
// The URL now carries only GoTrue's reason codes, and only known codes render.
export const WEAK_REASON_COPY: Record<string, string> = {
  length: "It's too short.",
  characters: "It needs a mix of character types — for example letters, numbers and symbols.",
  pwned: "It has appeared in a known data breach. Choose one you haven't used anywhere else.",
};

export function weakReasons(raw: unknown): string[] {
  if (typeof raw !== "string") return [];
  return raw.split(",").filter((r) => Object.prototype.hasOwnProperty.call(WEAK_REASON_COPY, r));
}

/** States the reset-password page renders WITHOUT a session: they end or pause the flow. */
export const TERMINAL_STATES: ResetState[] = ["done", "done_sessions_unconfirmed", "auth_unreachable"];

export function isResetState(v: unknown): v is ResetState {
  return typeof v === "string" && Object.prototype.hasOwnProperty.call(RESET_COPY, v);
}

/** Server-side configuration fact: has custom SMTP been set up for auth email? */
export function authEmailEnabled(): boolean {
  return process.env.AUTH_EMAIL_ENABLED === "true";
}
