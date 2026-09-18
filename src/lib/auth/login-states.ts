// Why a sign-in did not work, as a CODE the login page looks up.
// Track U, U-W1.20, 2026-09-17 — the pattern of Track X's reset-states.ts, whose
// flow shares this page.
//
// CONTROLLER RULING 2026-09-15: no URL parameter is ever rendered as text. The
// login page printed `?error=` verbatim, and it is the one page that needs no
// session — so ANYONE could send a link that put their words on our sign-in
// screen ("call this number to verify your account"). It now renders only these
// sentences.
//
// Classified from Supabase Auth's error `code` (the stable field), with the
// message as a fallback. The provider's text is never passed through.

export type LoginError = "missing" | "invalid_credentials" | "email_not_confirmed" | "rate_limited" | "unreachable" | "sign_in_failed";

export const LOGIN_ERROR_COPY: Record<LoginError, string> = {
  missing: "Enter your email and password.",
  invalid_credentials: "That email and password don't match an account. Check them and try again.",
  email_not_confirmed: "This account's email address hasn't been confirmed yet. Use the link in your invitation email first.",
  rate_limited: "Too many sign-in attempts. Wait a few minutes, then try again.",
  unreachable: "The sign-in service didn't answer. Try again in a moment.",
  sign_in_failed: "Sign-in didn't work. Try again, or reset your password below.",
};

export function isLoginError(v: unknown): v is LoginError {
  return typeof v === "string" && Object.prototype.hasOwnProperty.call(LOGIN_ERROR_COPY, v);
}

export function classifyLoginError(error: { code?: string; status?: number; message?: string }): LoginError {
  const code = error.code ?? "";
  const m = error.message ?? "";
  if (code === "invalid_credentials" || /invalid login credentials/i.test(m)) return "invalid_credentials";
  if (code === "email_not_confirmed" || /email not confirmed/i.test(m)) return "email_not_confirmed";
  if (code === "over_request_rate_limit" || error.status === 429) return "rate_limited";
  if (!error.status || error.status >= 500) return "unreachable";
  return "sign_in_failed";
}
