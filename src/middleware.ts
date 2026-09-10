import { type NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

export async function middleware(request: NextRequest) {
  return await updateSession(request);
}

export const config = {
  matcher: [
    // `api/health$` — EXACTLY that one path, anchored, and nothing else.
    //
    // RULING (Jacob, 2026-09-09): a health check that shares a dependency with
    // the thing it might be reporting on is a check that cannot fail
    // correctly. `updateSession()` constructs a Supabase client and calls
    // `auth.getSession()` on every matched request, so /api/health — whose
    // entire job is to say what is deployed when something is wrong — was
    // running an auth round-trip before it could answer.
    //
    // MEASURED BEFORE CHANGING IT, by temporarily having the middleware stamp
    // a header and probing paths against a real production build: the
    // middleware ran on /api/health, /login, /, /roadmap/*, /w/*/coordination,
    // /w/*/field and /api/does-not-exist, and did NOT run on /favicon.ico or
    // /_next/static/*. So the coupling was real and not theoretical.
    //
    // WHAT I COULD NOT DEMONSTRATE, stated because it bounds the claim: with
    // Supabase pointed at an unroutable host, /api/health still answered in
    // ~3 ms both with no cookie and with a synthetic session-shaped one.
    // `getSession()` short-circuits when there is no parseable session, so the
    // round-trip only happens for a request carrying a REAL stale session
    // cookie — which needs a real login, which I do not have. The dependency
    // is proved; the degradation is not. This change removes the coupling on
    // principle rather than on a reproduction.
    //
    // ANCHORED with `$` so it is one path and not a prefix: /api/healthcheck
    // or a future /api/health//deep would still get the session. The other
    // route in this build, the estimate PDF, reads the session and MUST keep
    // matching.
    "/((?!_next/static|_next/image|favicon.ico|api/health$|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
