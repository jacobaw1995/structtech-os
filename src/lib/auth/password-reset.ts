"use server";

// Self-serve password reset — the two writes.  Track X, X-W1.14, 2026-09-14.
//
// BEFORE THIS FILE, measured on production: /login offered no reset, and
// /forgot-password, /reset-password, /auth/confirm and /auth/callback were all 404.
// Someone who forgot their password had no path at all except asking Jacob.
//
// Every outcome ends in a redirect to a NAMED state (reset-states.ts). Nothing
// here returns data, and nothing collapses two causes into one sentence.
//
// BOUNDED. /auth/v1/recover runs through the server client's bounded fetch with
// AUTH_EMAIL_BOUND_MS (10 s) because GoTrue sends the email inside that request;
// every other auth call here keeps the 2500 ms refresh bound. A timeout is always
// reported as UNCONFIRMED, never as a failure — the mail may already be sent.

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import {
  isAuthApiError,
  isAuthRetryableFetchError,
  isAuthWeakPasswordError,
} from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import { authGaveUp } from "@/lib/supabase/bounded-fetch";
import { authEmailEnabled, weakReasons, type ResetState } from "@/lib/auth/reset-states";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * Where the emailed link comes back to. SITE_URL wins when set; otherwise the
 * request's own host. The Host header is caller-controlled, but it cannot send a
 * link anywhere useful: GoTrue only honours a redirect_to on the project's
 * Redirect URLs allow-list and otherwise falls back to the Site URL.
 */
function siteOrigin(): string {
  if (process.env.SITE_URL) return process.env.SITE_URL.replace(/\/+$/, "");
  const h = headers();
  const host = h.get("x-forwarded-host") ?? h.get("host") ?? "localhost:3001";
  const proto = h.get("x-forwarded-proto") ?? (host.startsWith("localhost") ? "http" : "https");
  return `${proto}://${host}`;
}

function forgot(state: ResetState): never {
  redirect(`/forgot-password?state=${state}`);
}

export async function requestPasswordReset(formData: FormData) {
  // Configuration first, and no network call when it is off. GoTrue answers 200 for
  // an address with no account (measured), so a request made without working email
  // would be told "check your inbox" and receive nothing.
  if (!authEmailEnabled()) forgot("off");

  const email = String(formData.get("email") ?? "").trim();
  if (!EMAIL_RE.test(email)) forgot("invalid_email");

  const supabase = createClient();
  let state: ResetState;
  try {
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${siteOrigin()}/auth/confirm?next=/reset-password`,
    });
    if (!error) state = "sent";
    else if (isAuthRetryableFetchError(error)) state = "unconfirmed";
    else if (
      error.status === 429 ||
      error.code === "over_email_send_rate_limit" ||
      error.code === "over_request_rate_limit"
    ) state = "rate_limited";
    else if (error.code === "email_address_invalid") state = "invalid_email";
    else state = "request_rejected";
  } catch {
    // A throw that is not a returned AuthError is still not evidence the mail failed.
    state = "unconfirmed";
  }
  forgot(state);
}

export async function updatePassword(formData: FormData) {
  const password = String(formData.get("password") ?? "");
  const confirm = String(formData.get("confirm") ?? "");
  if (password !== confirm) redirect("/reset-password?state=mismatch");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) {
    // Two causes with opposite advice: the service stalled (the link is fine, try
    // again) or there is no recovery session (the link expired — ask for another).
    if (authGaveUp(supabase)) redirect("/reset-password?state=auth_unreachable");
    forgot("link_expired");
  }

  let failed: ResetState | null = null;
  let reasons: string[] = [];
  try {
    const { error } = await supabase.auth.updateUser({ password });
    if (error) {
      if (isAuthRetryableFetchError(error)) failed = "update_unconfirmed";
      else if (isAuthWeakPasswordError(error)) {
        failed = "weak_password";
        // Codes only (length / characters / pwned) — never GoTrue's text, which the
        // page would otherwise render from a URL anyone can write. reset-states.ts.
        reasons = weakReasons(error.reasons.join(","));
      } else if (isAuthApiError(error) && error.code === "same_password") failed = "same_password";
      else failed = "update_rejected";
    }
  } catch {
    failed = "update_unconfirmed";
  }
  if (failed) {
    const q = reasons.length ? `&reasons=${reasons.join(",")}` : "";
    redirect(`/reset-password?state=${failed}${q}`);
  }

  // The password has changed. Now sign out every session, including any held by
  // whoever prompted the reset. If that step fails the password is STILL changed,
  // and the user is told exactly that rather than "done".
  let sessionsCleared = false;
  try {
    const { error } = await supabase.auth.signOut({ scope: "global" });
    sessionsCleared = !error;
  } catch {
    sessionsCleared = false;
  }
  redirect(`/reset-password?state=${sessionsCleared ? "done" : "done_sessions_unconfirmed"}`);
}
