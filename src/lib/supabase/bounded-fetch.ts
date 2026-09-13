// A session refresh that does not answer must not block the request — and must
// not announce a sign-out that did not happen.
//
// WHAT THIS FIXES, measured. With Supabase auth reachable but silent, a
// production build of this app served NOTHING on any matched route: /login, /
// and /w/<org>/coordination each returned no response at all after 45 SECONDS
// (2026-09-11). Only /api/health answered, because it was already excluded.
//
// ── THE FIRST FIX, AND WHAT IT BROKE (2026-09-12) ────────────────────────────
// Version one aborted the fetch and returned a SYNTHETIC 400 shaped like a
// gotrue error, because gotrue treats a failed fetch as retryable and loops.
// That bounded the request. It also made the timeout look like a revoked
// session. Measured with a listener on the client:
//
//     stalled refresh  -> SIGNED_OUT, INITIAL_SESSION(null)   at 2530 ms
//     revoked token    -> SIGNED_OUT, INITIAL_SESSION(null)   at   40 ms
//
// IDENTICAL. Any subscriber — "your session expired, sign in again" — would have
// told a user on a slow connection that they had been signed out, and a
// confident message for the wrong cause is worse than none: it stops people
// looking for the real one. Nothing in src/ subscribed on the day it was found,
// so it reached nobody. That is luck, not a control.
//
// The mechanism, read from @supabase/auth-js rather than guessed:
//   _callRefreshToken: a NON-retryable error calls _removeSession() -> SIGNED_OUT.
//   _refreshAccessToken: a RETRYABLE error loops with backoff while
//     elapsed < AUTO_REFRESH_TICK_DURATION_MS (30 * 1000). That constant is the
//     origin of every "thirty seconds" in this week's reports.
// So at the fetch layer there is no third option: terminal means SIGNED_OUT,
// retryable means a loop. The fix has to live one layer up.
//
// ── THIS VERSION ─────────────────────────────────────────────────────────────
// 1. The fetch layer bounds each ATTEMPT and lets the timeout stay RETRYABLE,
//    so gotrue never calls _removeSession and never emits SIGNED_OUT.
// 2. `boundGetSession` races the whole `auth.getSession()` call, so the REQUEST
//    proceeds without a session at the bound while gotrue's retry loop finishes
//    in the background on a client that is discarded with the request.
// 3. Once a client has given up, every later getSession() on it — including the
//    one PostgREST makes to fetch an access token for a query — returns "no
//    session" immediately. Without this, the next query in the same request
//    awaits gotrue's in-flight refresh promise and the hang comes straight back.
//
// Measured against a stub that stalls auth but answers data:
//   stalled refresh -> getSession 3019 ms, follow-on query 16 ms, NO events
//   revoked token   -> getSession   40 ms, SIGNED_OUT  (a real sign-out still says so)
//   healthy         -> getSession   40 ms, TOKEN_REFRESHED
//   watched 39 s past gotrue's 30 s cap: 8 background attempts, 0 cookie
//   removals, no SIGNED_OUT at any point.
//
// ── THE NUMBERS ──────────────────────────────────────────────────────────────
// 2500 ms. Real token refreshes on this project over 24 h ran min 61 / p50 152 /
// p95 453 / max 513 ms (n=7), from Vercel to Supabase in the same region, so
// 2500 is ~4.9x the slowest seen. The one auth call over 3 s in that window was
// /auth/v1/settings at 3069 ms, a cold start on an endpoint not on this path.
// COST: a refresh legitimately slower than 2500 ms leaves the request without a
// session, and the route's own guard asks the user to sign in.
//
// WHY ONLY AUTH. Data queries are untouched: rest and storage measured p50 258,
// p99 2058, max 5356 ms, and a 2500 ms bound on those would fail real queries.

/** Per-attempt socket bound, and the bound on the whole getSession() call. */
export const AUTH_BOUND_MS = 2500;

// Total socket-time a single client may spend on auth before further attempts
// fail instantly. The race above ends the REQUEST; this ends the BACKGROUND loop's
// socket use, so a stalled auth service does not leave a trail of open
// connections behind every request that hit it.
const AUTH_SOCKET_BUDGET_MS = 3000;

function isAuthCall(url: string): boolean {
  try {
    return new URL(url).pathname.startsWith("/auth/v1/");
  } catch {
    return url.includes("/auth/v1/");
  }
}

/** A fetch whose auth calls are bounded but stay retryable. One per client. */
export function createBoundedFetch(): typeof fetch {
  let authSpentMs = 0;

  return async function boundedFetch(input, init) {
    const url =
      typeof input === "string"
        ? input
        : input instanceof URL
          ? input.toString()
          : input.url;

    if (!isAuthCall(url)) return fetch(input, init);

    const remaining = AUTH_SOCKET_BUDGET_MS - authSpentMs;
    if (remaining <= 0) {
      // A TypeError is what a real network failure looks like, so gotrue treats
      // it as retryable — no session removal, no SIGNED_OUT — and no socket.
      throw new TypeError("fetch failed: supabase auth socket budget exhausted");
    }

    const started = Date.now();
    try {
      return await fetch(input, {
        ...init,
        signal: AbortSignal.timeout(Math.min(AUTH_BOUND_MS, remaining)),
      });
    } finally {
      authSpentMs += Date.now() - started;
    }
  } as typeof fetch;
}

type SessionResult = Awaited<
  ReturnType<{ auth: { getSession: () => Promise<unknown> } }["auth"]["getSession"]>
>;

/**
 * Race `client.auth.getSession()` against AUTH_BOUND_MS. Returns an accessor
 * reporting whether this client gave up. Mutates the client in place, so every
 * caller — including supabase-js's own token lookup for queries — goes through
 * the bound without any of the 18 call sites changing.
 */
export function boundGetSession(client: {
  auth: { getSession: () => Promise<unknown> };
}): () => boolean {
  const original = client.auth.getSession.bind(client.auth);
  let gaveUp = false;
  const noSession = { data: { session: null }, error: null } as SessionResult;

  client.auth.getSession = async () => {
    if (gaveUp) return noSession;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const deadline = new Promise<SessionResult>((resolve) => {
      timer = setTimeout(() => {
        gaveUp = true;
        resolve(noSession);
      }, AUTH_BOUND_MS);
    });
    try {
      return await Promise.race([original(), deadline]);
    } finally {
      clearTimeout(timer);
    }
  };

  return () => gaveUp;
}
