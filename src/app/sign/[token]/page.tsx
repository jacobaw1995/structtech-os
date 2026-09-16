import type { Metadata } from "next";
import { createClient } from "@/lib/supabase/server";
import { SigningView } from "@/components/signing/SigningView";
import { parseLinkView, type LinkView } from "@/lib/signing/link-states";

/**
 * THE CUSTOMER SIGNING PAGE — U-W1.18, 2026-09-16.
 *
 * PROPERTY: a customer who is not a user of this system opens one link, sees one
 * document, signs it, and the link grants nothing else.
 *
 *  - PUBLIC. No session is required and nothing here redirects to /login. The
 *    middleware refreshes a session if a cookie exists and guards nothing.
 *  - ONE READ: signing_link_view(token). No estimate id, org id or link id is in
 *    its answer or in this HTML; the only identifier on the page is the token the
 *    person already holds, and it is never printed as text.
 *  - ONE WRITE: sign_estimate_by_link (lib/signing/link-actions.ts).
 *  - STATES ARE NAMED (lib/signing/link-states.ts). Revoked is not one of them,
 *    because the database deliberately answers a revoked token exactly as it
 *    answers an unknown one.
 *  - NO URL PARAMETER IS RENDERED AS TEXT. `?r=` and `?copy=` are codes; an
 *    unknown value renders nothing.
 */

export const dynamic = "force-dynamic";

// A signing link is a bearer credential in the path. Never indexed; never sent
// to a third party in a Referer header.
export const metadata: Metadata = {
  title: "Review and sign your estimate",
  robots: { index: false, follow: false },
  referrer: "no-referrer",
};

async function loadView(token: string): Promise<LinkView | "error"> {
  const supabase = createClient();
  await supabase.auth.getSession(); // anon unless a session cookie exists; not branched on
  const { data, error } = await supabase.rpc("signing_link_view", { p_token: token });
  if (error) return "error";
  return parseLinkView(data);
}

export default async function SignPage({
  params,
  searchParams,
}: {
  params: { token: string };
  searchParams: { r?: string; copy?: string };
}) {
  const view = await loadView(params.token);
  return <SigningView view={view} token={params.token} searchParams={searchParams} />;
}
