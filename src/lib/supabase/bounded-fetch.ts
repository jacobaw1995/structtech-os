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

// ── AUTH CALLS THAT SEND EMAIL GET THEIR OWN BOUND (2026-09-14) ───────────────
// GoTrue sends the message INSIDE the request for these endpoints: the response
// only comes back after its SMTP handoff. The 2500 ms above was derived from token
// refreshes (max 513 ms observed), which send nothing, so applying it here would
// abort requests whose mail was already on its way and report a failure that did
// not happen. A bound borrowed from a different call is a habit, not a bound.
//
// THIS NUMBER IS NOT DERIVED, AND CANNOT BE YET. The thing it bounds — GoTrue's
// SMTP handoff — does not exist on this project until custom SMTP is configured.
// The only measurement available is a floor: /auth/v1/recover for an address with
// no account (so nothing sent) answered in 0.72 s on 2026-09-14. 10 s is a ceiling
// on how long a person is asked to wait, the same ceiling send.ts uses for its own
// handoff. Callers must treat a timeout here as UNCONFIRMED, never as failed, so a
// bound that proves too short produces an honest sentence rather than a false one.
// Re-derive from edge_logs origin_time on /auth/v1/recover once SMTP is live.
//
// These calls are also excluded from the per-client socket budget below, which
// exists to cap a stalled REFRESH loop; spending it here would starve the refresh
// a later call in the same request needs.
export const AUTH_EMAIL_BOUND_MS = 10_000;
const EMAIL_SENDING_AUTH_PATHS = ["/auth/v1/recover", "/auth/v1/otp", "/auth/v1/magiclink", "/auth/v1/invite"];

function authPath(url: string): string | null {
  let path: string;
  try {
    path = new URL(url).pathname;
  } catch {
    const i = url.indexOf("/auth/v1/");
    if (i < 0) return null;
    path = url.slice(i).split("?")[0];
  }
  return path.startsWith("/auth/v1/") ? path : null;
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

    const path = authPath(url);
    if (!path) return fetch(input, init);

    if (EMAIL_SENDING_AUTH_PATHS.includes(path)) {
      return fetch(input, { ...init, signal: AbortSignal.timeout(AUTH_EMAIL_BOUND_MS) });
    }

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
// Which clients gave up on their session. Keyed by the client object so any code
// holding a client can ask, without createClient() changing shape for its callers.
// A page that finds no session needs this to tell "your link expired" from "the
// sign-in service did not answer" — two causes that want opposite advice.
const GAVE_UP = new WeakMap<object, () => boolean>();

/** True if this client's session lookup was abandoned at the bound. */
export function authGaveUp(client: object): boolean {
  return GAVE_UP.get(client)?.() ?? false;
}

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

  const accessor = () => gaveUp;
  GAVE_UP.set(client, accessor);
  return accessor;
}

// ── THE BROWSER CLIENT (2026-09-22) ──────────────────────────────────────────
// Everything above is written for a SERVER client, which lives for one request:
// a per-client socket budget and a one-way "gave up" latch are safe there,
// because the client is discarded with the request. A BROWSER client lives for
// the whole tab. Give it the same budget and latch and a bad minute on a roof
// becomes permanent: the budget is spent, every later getSession() answers "no
// session" instantly, and the person is locked out of their own screens until
// they reload. So the browser gets the per-attempt bound and NOTHING ELSE.
//
// THE NUMBER. 7736 ms = the slowest of 12 real round trips to this project's
// /auth/v1/settings measured 2026-09-22 (min 57, p50 79, max 967 ms) x 8. The x8
// is for a phone on one bar, where RTT inflates several fold. It is NOT measured
// on a roof — nothing has been, because no browser code path has used this client
// yet — and it sits well inside gotrue's own AUTO_REFRESH_TICK_DURATION_MS
// (30 000 ms), so the screen proceeds while the library keeps retrying behind it.
// Re-derive from field_events page_ready durations once crew phones produce them.
export const BROWSER_AUTH_BOUND_MS = 7736;

/** A browser fetch whose auth calls are bounded per attempt and stay retryable. */
export function createBrowserBoundedFetch(): typeof fetch {
  return async function browserBoundedFetch(input, init) {
    const url =
      typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
    const path = authPath(url);
    if (!path) return fetch(input, init);
    const bound = EMAIL_SENDING_AUTH_PATHS.includes(path) ? AUTH_EMAIL_BOUND_MS : BROWSER_AUTH_BOUND_MS;
    // An aborted fetch looks like a network failure to gotrue, which is RETRYABLE:
    // it never calls _removeSession, so a slow auth service cannot sign anyone out.
    return fetch(input, { ...init, signal: AbortSignal.timeout(bound) });
  } as typeof fetch;
}

/**
 * Race each `auth.getSession()` against the bound, per call and with no memory.
 * The screen proceeds without a session; the session itself is untouched, and the
 * very next call can succeed. Nothing here clears storage or emits SIGNED_OUT —
 * that is the whole point: PROCEEDING WITHOUT A SESSION MUST NOT DESTROY ONE.
 */
export function boundGetSessionPerCall(client: { auth: { getSession: () => Promise<unknown> } }): void {
  const original = client.auth.getSession.bind(client.auth);
  const noSession = { data: { session: null }, error: null } as SessionResult;
  client.auth.getSession = async () => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    const deadline = new Promise<SessionResult>((resolve) => {
      timer = setTimeout(() => resolve(noSession), BROWSER_AUTH_BOUND_MS);
    });
    try {
      return await Promise.race([original(), deadline]);
    } finally {
      clearTimeout(timer);
    }
  };
}
