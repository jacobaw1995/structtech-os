// A session refresh that does not answer must not block the request.
//
// WHAT THIS FIXES, measured rather than argued. With Supabase auth reachable
// but silent — connections accepted, nothing ever answered — a production
// build of this app served NOTHING on any matched route. Measured 2026-09-11
// with an expired session cookie: /login, / and /w/<org>/coordination each
// returned no response at all after 45 SECONDS, at which point the client gave
// up. It is not a thirty-second hang; it is an unbounded one. The only route
// that answered was /api/health (4.9 ms), because it had already been excluded
// from the middleware.
//
// THE EXPOSURE IS A PERSON, NOT A CHECK. The monitor sends no cookie, so it
// never triggers a refresh and would report every door green throughout. The
// caller who hangs is someone carrying a stale session — on 7 October, a crew
// member on a roof. SCOPE §2.8: a spinner that never resolves is worse than a
// refusal, because the user cannot tell it from the app being dead.
//
// WHY THE FETCH LAYER AND NOT THE MIDDLEWARE. `auth.getSession()` is called in
// 18 files — every page, every server action. Bounding it in the middleware
// would have fixed the middleware and left every page still hanging. Binding
// the timeout to the HTTP call means all 18 inherit it without being touched.
//
// WHY ONLY THE AUTH PATHS. Every request blocks on the auth round-trip;
// nothing else is on that critical path. Data queries are left exactly as they
// were, because they are legitimately slower and bounding them would trade
// this defect for a new one: measured over the 24 h to 2026-09-11, rest and
// storage ran p50 258 ms, p99 2058 ms, max 5356 ms. A 2.5 s bound applied to
// those would start failing real queries.
//
// THE NUMBERS, AND WHAT THEY COST.
//   Per attempt: 2500 ms. Real token refreshes on this project over the same
//   window ran min 61 ms, p50 152 ms, p95 453 ms, max 513 ms (n=7). 2500 ms is
//   ~4.9x the slowest one actually seen, and above the p99 of every other
//   Supabase call measured. The single auth call that exceeded 3 s in 24 h was
//   /auth/v1/settings at 3069 ms — a cold start on an endpoint that is not on
//   this path.
//   Per request: 3000 ms total across all auth calls. The stub showed one
//   attempt per request, not a retry storm, so in practice the per-attempt
//   bound is the binding one; the budget exists so that a retry under some
//   other failure mode cannot stack attempts past ~3 s.
//
//   THE COST IS A SPURIOUS LOGOUT. If a refresh legitimately takes longer than
//   the bound, the request proceeds with no session and the route's own guard
//   sends the user to /login. That is a real cost and it is the trade being
//   made: a login prompt is recoverable and legible; an unbounded spinner is
//   neither. At ~4.9x the worst observed refresh, this should be rare — but
//   "should be" is a prediction, and if it turns out to bite, the number is
//   one constant in this file.

const AUTH_ATTEMPT_MS = 2500;
const AUTH_BUDGET_MS = 3000;

// WHY A SYNTHETIC 400 AND NOT A THROWN ERROR — measured, and the first version
// of this file got it wrong. Aborting the fetch is not enough: gotrue-js
// classifies a failed fetch as AuthRetryableFetchError and RETRIES it with
// exponential backoff. Instrumented on 2026-09-11, the abort fired correctly at
// 2509 ms and the budget remainder at 494 ms, and then gotrue simply kept
// calling — seven attempts and still going at 20 s. The per-call bound was
// real and the request still hung, because nothing bounded the LOOP.
//
// A 4xx with a gotrue-shaped body is terminal: gotrue raises AuthApiError,
// which `retryable()` does not retry. So the timeout is reported as a refusal
// rather than a network blip, the loop stops on the first one, and the request
// proceeds with no session.
function terminalTimeoutResponse(waitedMs: number): Response {
  return new Response(
    JSON.stringify({
      error: "invalid_grant",
      error_description: `structtech-os: session refresh exceeded ${waitedMs}ms and was abandoned so the request could proceed`,
    }),
    { status: 400, headers: { "content-type": "application/json" } }
  );
}

/** True for Supabase auth endpoints — the only ones on the blocking path. */
function isAuthCall(url: string): boolean {
  try {
    return new URL(url).pathname.startsWith("/auth/v1/");
  } catch {
    return url.includes("/auth/v1/");
  }
}

/**
 * Build a fetch bounded for auth calls. Create ONE PER SUPABASE CLIENT — the
 * budget is per-client, and this app builds a client per request, which is
 * what makes the budget per-request without any request-context plumbing.
 */
export type BoundedFetch = {
  fetch: typeof fetch;
  /** True once an auth call has been abandoned on time in this request. */
  timedOut: () => boolean;
};

export function createBoundedFetch(): BoundedFetch {
  let authSpentMs = 0;
  let timedOut = false;

  const boundedFetch = async function boundedFetch(input, init) {
    const url =
      typeof input === "string"
        ? input
        : input instanceof URL
          ? input.toString()
          : input.url;

    if (!isAuthCall(url)) return fetch(input, init);

    const remaining = AUTH_BUDGET_MS - authSpentMs;
    if (remaining <= 0) {
      // Budget spent. Answer immediately rather than opening another socket.
      timedOut = true;
      return terminalTimeoutResponse(authSpentMs);
    }

    const budget = Math.min(AUTH_ATTEMPT_MS, remaining);
    const started = Date.now();
    try {
      // AbortSignal rather than a bare Promise.race: this actually cancels the
      // request and releases the socket. A race would leave the original fetch
      // running and the connection open.
      return await fetch(input, { ...init, signal: AbortSignal.timeout(budget) });
    } catch (err) {
      // Only OUR deadline is converted into a refusal. A genuine network error
      // keeps its old behaviour — gotrue may retry it, which is correct when
      // the failure is transient rather than a stall.
      if ((err as Error)?.name === "TimeoutError") {
        timedOut = true;
        return terminalTimeoutResponse(Date.now() - started);
      }
      throw err;
    } finally {
      authSpentMs += Date.now() - started;
    }
  } as typeof fetch;

  return { fetch: boundedFetch, timedOut: () => timedOut };
}
