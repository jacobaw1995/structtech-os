import type { Metadata } from "next";
import { createClient } from "@/lib/supabase/server";
import { RoadmapView } from "@/components/roadmap/RoadmapView";
import type { RoadmapRow } from "@/lib/roadmap/model";

/**
 * The public client roadmap viewer.
 *
 * Nine roadmaps have existed in production since July and none of them has
 * ever had a page to open — the tokens were correct, the route did not
 * exist. This is that route.
 *
 * Reads through `fetch_roadmap_by_token(text)` and nothing else. That
 * function is SECURITY DEFINER, STABLE and search_path-pinned, and it
 * deliberately does not return `token`, `lead_id` or `org_id` — so the token
 * never round-trips into the HTML, and this page has no way to leak the
 * tenant the roadmap belongs to. There is no second query and no
 * client-side filter standing in for a policy: the token IS the
 * authorisation, and it is checked in the database.
 *
 * KNOWN STATE ON SHIP: `anon` does not hold EXECUTE on that function, so a
 * logged-out request lands in the `restricted` branch below rather than
 * rendering. That is deliberate and it is not a bug in this file — the grant
 * is one line, it belongs to the migration track, and it goes last so that
 * granting it does not create an anonymous surface before there is a page
 * behind it.
 */

export const dynamic = "force-dynamic";

// A roadmap is private-by-token and names a real business. It must never be
// indexed, and the token must never travel in a referrer to a third party.
export const metadata: Metadata = {
  title: "Operations Roadmap · StructTech",
  robots: { index: false, follow: false },
  referrer: "no-referrer",
};

type Outcome =
  | { kind: "ok"; roadmap: RoadmapRow }
  | { kind: "not_found" }
  // `restricted` carries NO detail — see the ruling recorded in loadRoadmap().
  // Removing the field rather than merely not rendering it is the point: a
  // future edit that adds `detail={outcome.detail}` back to that branch now
  // fails to compile instead of quietly re-publishing a function name to
  // anonymous readers. The type is the control; a comment would not be.
  | { kind: "restricted" }
  | { kind: "error"; detail: string };

async function loadRoadmap(token: string): Promise<Outcome> {
  const supabase = createClient();

  // getSession() before any DB call: without it the client sends no auth
  // header and the caller is anon even when a session cookie exists
  // (CLAUDE.md). A missing session is NOT an error here — this page is meant
  // to work without one — so the result is deliberately not branched on.
  await supabase.auth.getSession();

  const { data, error } = await supabase.rpc("fetch_roadmap_by_token", {
    p_token: token,
  });

  if (error) {
    // The distinction this branch exists to protect: an error is never
    // evidence that the roadmap does not exist. A caller who lacks EXECUTE
    // on the function is told the link cannot be opened — not that the
    // record is missing, which would be a claim we have not established and
    // which would send a client chasing StructTech for a lost roadmap that
    // is sitting right there.
    //
    // 42501 is `permission denied for function`. PGRST202 is PostgREST
    // reporting the function as absent from its schema cache, which is what
    // a role with no EXECUTE sees — a 404-shaped answer to a permissions
    // question, and the single most misleading code on this path.
    //
    // ----------------------------------------------------------------------
    // CONTROLLER RULING, 2026-09-06 — THIS SUPERSEDES THE REASON THAT USED TO
    // BE RECORDED HERE, AND THE SUPERSEDED VERSION IS NAMED SO THE CHANGE IS
    // LEGIBLE RATHER THAN INVISIBLE.
    //
    // WAS: `restricted` carried a `detail` string and the page rendered it, on
    // the reasoning that a reader deserves the specific reason a request was
    // refused rather than a shrug. That reasoning was right about honesty and
    // wrong about audience.
    //
    // NOW: `restricted` renders NO detail. Track X measured the DEPLOYED route
    // printing `42501: permission denied for function fetch_roadmap_by_token`
    // to an anonymous visitor on a public URL. That is this application
    // handing an unauthenticated reader the exact function name to target,
    // on the one page in the build that has no login in front of it.
    //
    // The `error` branch KEEPS its detail. The two are not symmetric: a
    // `restricted` outcome is, by construction, a caller who is already
    // outside the fence and whose refusal message describes the fence. An
    // `error` outcome is a caller who is inside a supported path and hit a
    // fault, and its detail is what makes a support conversation possible.
    //
    // The diagnostic is not discarded, it is MOVED: it goes to the server log,
    // where an operator can read it and a visitor cannot. Losing it entirely
    // would trade one defect for another.
    // ----------------------------------------------------------------------
    const code = error.code ?? "";
    if (code === "42501" || code === "PGRST202" || code === "PGRST301") {
      console.error(
        `[roadmap] refused for token (restricted): ${code}: ${error.message}`
      );
      return { kind: "restricted" };
    }
    return { kind: "error", detail: `${code}: ${error.message}` };
  }

  const rows = (data ?? []) as unknown as RoadmapRow[];
  // Only this — a successful call that matched nothing — licenses saying the
  // roadmap does not exist.
  if (rows.length === 0) return { kind: "not_found" };

  return { kind: "ok", roadmap: rows[0] };
}

function Message({
  title,
  body,
  detail,
}: {
  title: string;
  body: string;
  detail?: string;
}) {
  return (
    <div className="flex min-h-dvh items-center justify-center bg-bg px-4 py-12">
      <div className="w-full max-w-md">
        <div className="mb-6 flex items-center gap-2">
          <span className="flex h-6 w-6 items-center justify-center rounded bg-accent-strong font-mono text-xs font-bold text-white">
            S
          </span>
          <span className="text-sm font-semibold tracking-tight text-text">
            StructTech
          </span>
        </div>
        <h1 className="font-serif text-2xl font-semibold leading-snug text-text">
          {title}
        </h1>
        <p className="mt-3 text-[15px] leading-relaxed text-muted">{body}</p>
        {detail ? (
          <p className="mt-6 border-t border-border pt-4 font-mono text-[11px] leading-relaxed text-muted">
            {detail}
          </p>
        ) : null}
      </div>
    </div>
  );
}

export default async function RoadmapPage({
  params,
}: {
  params: { token: string };
}) {
  const outcome = await loadRoadmap(decodeURIComponent(params.token));

  // CONTROLLER DECISION 1.3 (2026-09-03) — the copy below no longer says "get
  // in touch" or "ask StructTech". This page has no contact affordance and
  // cannot have one until contact fields come through the RPC (Track S, W2),
  // so pointing at a channel that is not on the page was a promise the page
  // could not keep. It now points at the channel the reader demonstrably has:
  // whoever sent them the link. No contact details are invented here.
  switch (outcome.kind) {
    case "ok":
      return <RoadmapView roadmap={outcome.roadmap} />;

    case "not_found":
      return (
        <Message
          title="This roadmap link isn’t valid."
          body="The link may have been mistyped, or it may have been replaced with a newer one. Whoever sent you this link can send a current one, and it will open right here."
        />
      );

    case "restricted":
      // Still does not claim the roadmap is missing — that distinction is the
      // reason this branch exists and it survives intact. What is gone is the
      // MECHANISM: "being held by StructTech and is not readable from here
      // yet" described the shape of the refusal to a reader who, on this
      // route, may be anyone at all. It now says the link is not available
      // and what to do about it, and nothing about why.
      return (
        <Message
          title="This roadmap link isn’t available right now."
          body="Nothing has been lost. Reply to whoever sent you this link and they can get it opened up for you."
        />
      );

    case "error":
      return (
        <Message
          title="Something went wrong loading this roadmap."
          body="This is a problem on our end, not with your link. Try again in a moment; if it keeps happening, reply to whoever sent you this link."
          detail={outcome.detail}
        />
      );
  }
}
