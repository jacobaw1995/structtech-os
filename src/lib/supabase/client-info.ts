// The tenant tag we put on every outbound Supabase request.
//
// WHY THIS FILE EXISTS. `ejlhrykcdfcyeooooodx` is a SHARED project: StructTech
// OS and Material Matrix both run against it, and the edge log holds both
// tenants' rows in one stream with no tenant column. Measured 2026-09-04, over
// the 21.7-hour window the log then held:
//
//   · An AUTHENTICATED row does carry a user id, in
//     `request.sb.jwt.authorization.payload.subject`, and it resolves through
//     org_members. But it attributes a USER, not a TENANT, and the two come
//     apart on the account that matters most: Jacob belongs to StructTech,
//     Brothers Metal Roofing AND Material Matrix, and on 2026-08-28 his
//     subject was 112 of the 130 authenticated rows in that window — the
//     majority of authenticated traffic is inherently ambiguous. (A first
//     enumeration of this log's fields showed no `subject` at all. It was
//     wrong: the window sampled happened to hold no authenticated traffic, so
//     the field was absent rather than nonexistent. A field list is only as
//     complete as the traffic that produced it — do not infer "does not
//     exist" from "cannot see".)
//   · An ANON row carries no subject at all. The roadmap token path is anon,
//     so for the decision this file exists to serve, subject is no help.
//   · Every anon request in the log — ours AND Material Matrix's — carries the
//     SAME signature_prefix `_bqBae`, because it is the same shared anon key.
//     Two of those rows came from Amazon IPs (MM's edge functions) and are
//     byte-identical to ours in every auth field.
//   · What separated the two tenants today was user_agent and ASN, and both are
//     accidents of hosting: we happened to call from Metronet and Azure with
//     `curl`/`node`, they happened to call from AWS with Deno. The day either
//     side changes runtime, the separation is gone and nobody is told.
//
// `x-client-info` is one of the few REQUEST HEADERS the edge log captures
// (present on 495 of 600 rows in that window), and it is ours to set. Setting
// it turns "we can usually tell our traffic apart" into a field that says so.
//
// WHAT THIS DOES NOT DO. It tags OUR clients only. A third party calling a
// public endpoint sends whatever they like, and an attacker sends whatever
// they like. So this cannot prove a request IS ours — it can only let us
// subtract ours and look at the remainder. That subtraction is the whole point:
// when the anon-EXECUTE decision on the roadmap path comes up, "zero live
// callers" has to mean zero callers that were not us, and without this tag
// that sentence has no way to be true.

const APP = "structtech-os";

/**
 * @param surface which of our clients is calling — so a row identifies not
 *   just the tenant but the code path, which is what makes a surprise in the
 *   log answerable rather than merely visible.
 */
export function clientInfo(surface: "server" | "browser" | "middleware"): string {
  return `${APP}/${surface}`;
}

/** Ready to spread into a supabase-js `global` option. */
export function clientInfoHeaders(
  surface: "server" | "browser" | "middleware"
): { headers: Record<string, string> } {
  return { headers: { "x-client-info": clientInfo(surface) } };
}

// ---------------------------------------------------------------------------
// THE CANONICAL QUERY.
//
// THE FILTER IS UNANCHORED, AND THAT IS THE WHOLE POINT. `@supabase/ssr` does
// not REPLACE x-client-info with the value passed in `global.headers` — it
// APPENDS ours to its own. The real header on the deployed roadmap route,
// read out of the edge log 2026-09-05 10:22 EDT, is:
//
//     "supabase-ssr/0.12.0 createServerClient, structtech-os/server"
//
// An anchored `like 'structtech-os/%'` does not match that. This file shipped
// on 2026-09-04 with the anchored form, and it "passed" because it was proved
// with a raw curl that set the header directly and had no library prefix in
// front of it. Measured over the 24 h to 2026-09-05 14:30Z, against a
// denominator of 124 edge rows: the anchored filter matched 1 row — the curl
// proof itself — and the unanchored filter matched 2, the second being the
// only real application traffic there was. THE ANCHORED FILTER MISSED EXACTLY
// THE TRAFFIC IT EXISTS TO FIND, and it did so while reporting a pass.
//
//   select
//     count(*)                                                as denominator,
//     countIf(log_attributes['request.headers.x_client_info']
//               like '%structtech-os/%')                      as ours,
//     countIf(log_attributes['request.headers.x_client_info']
//               not like '%structtech-os/%')                  as not_ours
//   from logs
//   where source = 'edge_logs'
//     and log_attributes['request.path'] like '/rest/v1/rpc/fetch_roadmap%'
//
// READ `not_ours` AGAINST `denominator`, NEVER ALONE. A zero with no live
// denominator beside it is not a reading — it is equally consistent with a
// logging outage. The query window caps at 24 hours; retention runs longer
// (rows from 2026-08-28 were still readable on 2026-09-04), so a zero is
// established by walking consecutive windows, not by one call.
// ---------------------------------------------------------------------------
