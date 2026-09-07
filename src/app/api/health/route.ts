import { NextResponse } from "next/server";

/**
 * What is deployed.
 *
 * WHY THIS EXISTS. On 2026-09-07 the question "which COMMIT is serving
 * os.structtek.com?" had no answer available to anyone outside the Vercel
 * account. Measured that day: the Vercel API returns 403 to us; the response
 * headers carry `server: Vercel` and an `x-vercel-id` request trace and
 * nothing that identifies a build; the `/_next/static/...` strings are content
 * hashes, which name a bundle and not a commit.
 *
 * WHAT IS ALREADY THERE, stated because a first pass here got it wrong. The
 * served HTML DOES carry a Next.js `buildId` — `nKpffDJrxXATyqaBVrv5_` on
 * 2026-09-07 — inside the flight payload, where the quotes are backslash-
 * escaped. An earlier grep for `"buildId":"` matched nothing and that absence
 * was written down as a fact. It was a bad regex, not a missing field.
 *
 * The buildId still does not answer the question, for a reason worth keeping:
 * it is a random per-deployment identifier, not a commit, and it is not
 * reproducible outside Vercel — the same source built locally the same day
 * produced `f7pl0iLrgdOE4SHkpAM4B`. So it can tell you THAT a redeploy
 * happened, which is more than nothing, but it cannot tell you WHICH COMMIT is
 * live, and that is the question. One line of JSON ends it.
 *
 * PUBLIC, DELIBERATELY, AND HERE IS THE TRADE.
 *
 * The cost is real and worth stating rather than waving away: the repository
 * is PUBLIC (verified 2026-09-05: `private=false`). Publishing the SHA
 * therefore tells anyone exactly WHICH public commit is live, and a reader can
 * diff it forward to see what has been fixed since and is presumably still
 * exploitable here. That is a genuine, if modest, uplift to an attacker.
 *
 * The benefit is that the reader who most needs this has no credentials at
 * all. The front-door monitor runs in GitHub Actions with no session and no
 * Vercel access, and its whole job is to assert things about the deployment
 * from outside. Gating this route means giving the monitor a credential to
 * hold forever — and a credential that expires quietly, taking an assertion
 * with it, is the exact failure this project has spent a week finding in other
 * forms. A control that depends on a secret nobody is watching is a control
 * with an expiry date nobody has written down.
 *
 * So: public, and MINIMAL. The commit, the environment, the time. No
 * environment variables, no dependency versions, no branch name, no build log,
 * no error detail. Nothing here that is not already derivable from the public
 * repository plus the fact that the site is up.
 *
 * THE CONDITION THAT REVERSES THIS DECISION: if the repository ever goes
 * private, the SHA stops being "which public commit" and becomes a pointer
 * into source nobody outside can read — a different disclosure with a
 * different answer. Gate it then.
 */

export const dynamic = "force-dynamic";

export async function GET() {
  // Vercel injects this at build time. Absent locally and on any non-Vercel
  // host, and the honest answer there is "unknown" — NOT a fabricated value
  // and NOT a 500. A monitor must be able to tell "this deployment cannot
  // report its commit" from "this deployment is down", and collapsing the two
  // is how an outage claim gets made about a healthy box.
  const sha = process.env.VERCEL_GIT_COMMIT_SHA ?? null;

  return NextResponse.json(
    {
      ok: true,
      sha,
      env: process.env.VERCEL_ENV ?? "local",
      time: new Date().toISOString(),
    },
    {
      status: 200,
      headers: {
        // Never cached: a stale SHA is worse than no SHA, because it answers
        // the question wrongly and with confidence.
        "cache-control": "no-store, max-age=0",
        "x-robots-tag": "noindex",
      },
    }
  );
}
