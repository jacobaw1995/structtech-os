import { NextResponse, type NextRequest } from "next/server";
import { isAuthApiError, isAuthRetryableFetchError, type EmailOtpType } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import type { ResetState } from "@/lib/auth/reset-states";

// Where an emailed reset link lands.  Track X, X-W1.14, 2026-09-14.
//
// Accepts BOTH link shapes, because which one arrives depends on a dashboard
// setting this code cannot see:
//   ?token_hash=…&type=recovery — Supabase's recommended SSR template. Works in any
//      browser. Needs the Reset Password email template changed (instructions).
//   ?code=… — what the DEFAULT template produces under PKCE. Only works in the
//      browser that asked for the reset, because the code verifier is a cookie
//      there. Opened anywhere else it fails with its OWN named state rather than
//      "expired", which would send the user round a loop that never works.
//
// `next` is not honoured as a free-form path: the only destination is
// /reset-password, so this route cannot be used as an open redirect.

export const dynamic = "force-dynamic";

function to(request: NextRequest, path: string) {
  return NextResponse.redirect(new URL(path, request.nextUrl.origin));
}

function linkFailure(request: NextRequest, error: unknown) {
  let state: ResetState = "link_invalid";
  if (isAuthRetryableFetchError(error)) state = "auth_unreachable";
  else if ((error as { name?: string })?.name === "AuthPKCECodeVerifierMissingError") state = "link_other_browser";
  else if (
    isAuthApiError(error) &&
    (error.code === "otp_expired" || error.code === "flow_state_expired" || error.code === "flow_state_not_found")
  ) state = "link_expired";
  else if (isAuthApiError(error) && (error.status === 401 || error.status === 403)) state = "link_expired";
  return state === "auth_unreachable"
    ? to(request, `/reset-password?state=${state}`)
    : to(request, `/forgot-password?state=${state}`);
}

export async function GET(request: NextRequest) {
  const url = request.nextUrl;
  const tokenHash = url.searchParams.get("token_hash");
  const type = url.searchParams.get("type") as EmailOtpType | null;
  const code = url.searchParams.get("code");

  const supabase = createClient();

  if (tokenHash) {
    if (type !== "recovery") return to(request, "/forgot-password?state=link_invalid");
    try {
      const { error } = await supabase.auth.verifyOtp({ type, token_hash: tokenHash });
      return error ? linkFailure(request, error) : to(request, "/reset-password");
    } catch (error) {
      return linkFailure(request, error);
    }
  }

  if (code) {
    try {
      const { error } = await supabase.auth.exchangeCodeForSession(code);
      return error ? linkFailure(request, error) : to(request, "/reset-password");
    } catch (error) {
      // exchangeCodeForSession THROWS AuthPKCECodeVerifierMissingError rather than
      // returning it (auth-js 2.110.2, GoTrueClient.js:1581).
      return linkFailure(request, error);
    }
  }

  return to(request, "/forgot-password?state=link_invalid");
}
