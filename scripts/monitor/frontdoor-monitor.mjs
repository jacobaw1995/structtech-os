#!/usr/bin/env node
/**
 * StructTech OS — front-door monitor.  Track X, X-W1.1, 2026-09-02.
 *
 * WHY THIS EXISTS, AND WHY IT NEVER LOOKS AT A STATUS CODE ALONE
 * -------------------------------------------------------------
 * Both P0s this backend has had returned HTTP 200 throughout:
 *   · 2026-08-20 — a storefront path died on an uncaught TypeError from a
 *     dereferenced null embed.  200 with nulls, for the whole outage.
 *   · the same class, inverted — 200 with everything, when a grant that
 *     should be closed is open.
 * A status-code monitor shows a green check for the duration of either.
 * So every check below asserts on CONTENT: a specific string, a specific
 * PostgREST error code, a specific asset resolving.
 *
 * THE THREE-STATE RULE — THIS IS THE WHOLE DESIGN
 * ----------------------------------------------
 * Material Matrix shipped a deploy-drift guard that reported all six pairs
 * drifted because the build image had neither `cmp` nor `diff`; the failure
 * surfaced as `command not found` and was reported as a finding.  It failed
 * closed for the wrong reason, which is indistinguishable from working right
 * up until it is indistinguishable from an outage.
 *
 * Therefore this monitor has THREE outcomes, never two:
 *
 *   PASS   the door answered and the required content was there.
 *   FAIL   the door answered with a well-formed HTTP response and the
 *          required content was ABSENT or WRONG.  This is an outage claim.
 *   ERROR  the monitor could not determine anything — DNS, TLS, timeout,
 *          abort, malformed transport, missing configuration.  This is a
 *          claim about the MONITOR, not about the door, and it is never
 *          allowed to masquerade as FAIL.
 *
 * The boundary is drawn once, in `probe()`: anything thrown by the transport
 * becomes ERROR before a classifier ever sees it.  Classifiers are pure
 * functions over a well-formed response and can only ever return PASS/FAIL.
 * That is what makes MM's failure mode structurally impossible here rather
 * than merely unlikely.
 *
 * ZERO DEPENDENCIES, ZERO EXTERNAL BINARIES.
 * Node built-ins only — no curl, no jq, no cmp, no diff, no npm install.
 * The MM guard died on a binary missing from the image; nothing here can.
 *
 * NO SECRETS.  The monitor holds none.  It reads the Supabase URL and the
 * publishable anon key out of the live results.html — the same values the
 * live page serves to every visitor — so it can never drift from production
 * and there is nothing to rotate, store, or leak.  The key is redacted from
 * all output regardless, because this repo is public.
 */

import { appendFileSync } from 'node:fs';

const DEFAULTS = {
  // Overridable so D1.4's branches can be exercised against a locally built
  // instance — a 404, a null sha and a valid sha cannot all be induced against
  // production, and a branch that is never executed is not a tested branch.
  // Production sets neither variable, so the defaults are what actually runs.
  osBase:    process.env.MONITOR_OS_BASE    || 'https://os.structtek.com',
  auditBase: process.env.MONITOR_AUDIT_BASE || 'https://audit.structtek.com',
};

const FAULT = process.env.MONITOR_FAULT || '';

// See D1.4. A 404 on /api/health is tolerated until this date and a failure
// after it. Deliberately a literal: an env var could be set to silence it.
const HEALTH_ROUTE_DUE = '2026-09-14T00:00:00Z';
const SELFTEST = process.env.MONITOR_SELFTEST === '1';
const BASE_TIMEOUT_MS = Number(process.env.MONITOR_TIMEOUT_MS || 15000);

// ---------------------------------------------------------------------------
// Fault injection.  Used ONLY to exercise the monitor's own failure paths in
// the environment it really runs in.  Every mode rewrites configuration; none
// of them reaches into the classifiers, so a fault run exercises the real
// transport and the real grading, not a mock of them.
// ---------------------------------------------------------------------------
function config() {
  const c = { ...DEFAULTS, timeoutMs: BASE_TIMEOUT_MS };
  switch (FAULT) {
    case '':
      break;
    case 'network':
      // Unresolvable host.  Must come back ERROR, never FAIL: the doors may
      // be perfectly healthy and the monitor simply blind.
      c.osBase = c.auditBase = 'https://frontdoor-monitor.does-not-resolve.invalid';
      break;
    case 'timeout':
      // A timeout is the monitor being too slow, not the door being down.
      c.timeoutMs = 1;
      break;
    case 'content':
      // Real hosts, real 200s, none of the required content.  This is the one
      // mode that MUST come back FAIL — it is a genuine outage signature.
      c.osBase = c.auditBase = 'https://example.com';
      break;
    case 'noconfig':
      // Configuration missing.  Must be ERROR.  "I was never told where to
      // look" is not "the door is down".
      c.osBase = c.auditBase = '';
      break;
    default:
      throw new Error(`unknown MONITOR_FAULT: ${FAULT}`);
  }
  return c;
}

// ---------------------------------------------------------------------------
// Transport.  The ONLY place ERROR is minted from an exception.
// ---------------------------------------------------------------------------
class Undetermined extends Error {}

// The monitor's own tag. MEASURED 2026-09-06: over the 24 h to 14:40Z the edge
// log held 61 rows, of which 24 were this monitor's requests to Supabase and
// ALL 24 WERE UNTAGGED — it calls `fetch` directly and never touches a
// Supabase client, so `src/lib/supabase/client-info.ts` never applies to it.
//
// That is not cosmetic. The instrument the roadmap-grant decision rests on is
// "tag ours, subtract, read the remainder", and on that day OUR OWN MONITOR
// WAS THE LARGEST SINGLE OCCUPANT OF THE REMAINDER. A method whose leftover
// bucket is dominated by our own traffic cannot answer "did a stranger call
// this endpoint" — every reading would have to be hand-corrected for the
// monitor, and a correction nobody remembers to apply is the absence-as-
// control failure this project keeps finding.
//
// Tagging changes nothing about what is probed: x-client-info carries no
// authorisation and PostgREST does not read it. D2.3 and D3.2 still reach the
// backend with exactly the anon key and headers a public caller would use.
// It labels our probe traffic as ours, which is all it claims to do.
const MONITOR_CLIENT_INFO = 'structtech-os/frontdoor-monitor';

async function probe(url, init, timeoutMs) {
  if (!url || !/^https?:\/\//.test(url)) {
    throw new Undetermined(`no usable URL configured (got ${JSON.stringify(url)})`);
  }
  let res;
  try {
    res = await fetch(url, {
      ...init,
      headers: { ...(init?.headers ?? {}), 'x-client-info': MONITOR_CLIENT_INFO },
      signal: AbortSignal.timeout(timeoutMs),
      redirect: 'follow',
    });
  } catch (err) {
    throw new Undetermined(`${err.name}: ${err.message}`);
  }
  let body;
  try {
    body = await res.text();
  } catch (err) {
    throw new Undetermined(`body read failed — ${err.name}: ${err.message}`);
  }
  return { status: res.status, url: res.url, body, headers: res.headers };
}

// ---------------------------------------------------------------------------
// Classifiers — pure, total, and only ever PASS or FAIL.
// ---------------------------------------------------------------------------
const pass = (detail) => ({ status: 'PASS', detail });
const fail = (detail) => ({ status: 'FAIL', detail });

/** A document door: the response must contain every required literal. */
function classifyContains(res, required) {
  const missing = required.filter((s) => !res.body.includes(s));
  if (missing.length) {
    return fail(`HTTP ${res.status} but missing ${missing.length}/${required.length} required string(s): ${missing.map((s) => JSON.stringify(s)).join(', ')}`);
  }
  return pass(`HTTP ${res.status}, all ${required.length} required string(s) present`);
}

/**
 * The audit.structtek.com write-path probe.
 *
 * Graded on the MESSAGE, per CLAUDE.md rule 11 — the three refusal forms are
 * not distinguishable by status code alone.
 *
 *   400 + a DATA error code (22P02 / 23502 / …)  → PASS.  The privilege check
 *        was passed and Postgres got as far as evaluating the row.  The anon
 *        INSERT grant on audit_leads is intact and the lead form works.
 *   401/403 or 42501 or "permission denied"      → FAIL.  Form 1.  The grant
 *        is gone.  Every lead submitted from now on is silently dropped —
 *        results.html swallows the rejection in a .catch and shows the
 *        visitor a success screen regardless.
 *   any 2xx                                      → FAIL.  A row was accepted.
 *        The probe payload is deliberately invalid; if it inserted, the
 *        contract this check rests on has changed and the check is lying.
 */
const DATA_ERROR_CODES = ['22P02', '23502', '23514', '22007', '22003', '23505'];

function classifyWriteProbe(res) {
  const body = res.body || '';
  if (res.status >= 200 && res.status < 300) {
    return fail(`HTTP ${res.status} — the deliberately-invalid probe payload was ACCEPTED. A row may have been written to audit_leads and this check's premise is void.`);
  }
  if (res.status === 401 || res.status === 403 || body.includes('42501') || body.includes('permission denied')) {
    return fail(`HTTP ${res.status} — rule 11 FORM 1 on the anon INSERT grant. The audit.structtek.com lead form is silently dropping every lead (results.html swallows this in a .catch and still shows the success screen). Body: ${body.slice(0, 200)}`);
  }
  const hit = DATA_ERROR_CODES.find((c) => body.includes(c));
  if (res.status === 400 && hit) {
    return pass(`HTTP 400 / ${hit} — privilege check passed, Postgres evaluated the row and rejected it on data. Grant intact, no row written.`);
  }
  return fail(`HTTP ${res.status} with an unrecognised body — expected 400 + one of ${DATA_ERROR_CODES.join('/')}. Body: ${body.slice(0, 200)}`);
}

/**
 * The anon-read invariant on a closed table.
 *
 * CLAUDE.md rule 11 in force: on `anon`, an empty 200 result is FORM 2 and is
 * NOT a pass — it means the table grant survived and RLS alone is holding the
 * door.  That is precisely the state migration 20260829142743 removed across
 * 49 tables, and precisely what one stray `grant execute on my_org_ids() to
 * anon` in someone else's migration would restore.  Nothing else watches for
 * it: the advisor is a change detector on a surface shared with another
 * project, so a number that does not move proves nothing (rule 9).
 */
function classifyAnonClosed(res, table) {
  const body = res.body || '';
  if ((res.status === 401 || res.status === 403) && body.includes('42501') && body.includes(`permission denied for table ${table}`)) {
    return pass(`HTTP ${res.status} / 42501 "permission denied for table ${table}" — rule 11 FORM 1. Table grant closed.`);
  }
  if (res.status >= 200 && res.status < 300) {
    return fail(`HTTP ${res.status} — anon READ SUCCEEDED on ${table}. If the body is [] this is rule 11 FORM 2: the table grant is back and only RLS is holding. SECURITY REGRESSION. Body: ${body.slice(0, 200)}`);
  }
  if (body.includes('42501') && !body.includes(`permission denied for table ${table}`)) {
    return fail(`HTTP ${res.status} / 42501 but naming something other than table ${table} — rule 11 FORM 3 (a helper's EXECUTE bit stopped us, the table's own grant is untested). Body: ${body.slice(0, 200)}`);
  }
  return fail(`HTTP ${res.status} — expected 401/42501 "permission denied for table ${table}". PostgREST or the database may be down. Body: ${body.slice(0, 200)}`);
}

// ---------------------------------------------------------------------------
// Checks
// ---------------------------------------------------------------------------
const results = [];

function record(id, door, layer, status, detail) {
  results.push({ id, door, layer, status, detail });
  const mark = status === 'PASS' ? 'PASS ' : status === 'FAIL' ? 'FAIL ' : 'ERROR';
  console.log(`[${mark}] ${id}  (${door} · ${layer})\n         ${detail}`);
}

async function check(id, door, layer, fn) {
  try {
    const r = await fn();
    record(id, door, layer, r.status, r.detail);
    return r;
  } catch (err) {
    if (err instanceof Undetermined) {
      record(id, door, layer, 'ERROR', `monitor could not determine — ${err.message}`);
    } else {
      record(id, door, layer, 'ERROR', `monitor threw — ${err.name}: ${err.message}`);
    }
    return { status: 'ERROR' };
  }
}

const redact = (s) => String(s).replace(/eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, 'eyJ<REDACTED-JWT>').replace(/sb_(publishable|secret)_[A-Za-z0-9_-]+/g, 'sb_$1_<REDACTED>');

async function run() {
  const cfg = config();
  console.log(`StructTech OS front-door monitor · ${new Date().toISOString()}`);
  console.log(`timeout=${cfg.timeoutMs}ms  fault=${FAULT || '(none)'}\n`);

  // === DOOR 1 · os.structtek.com — the application front door ==============

  // 1.1 SHALLOW LAYER, AND LABELLED AS SUCH. This string is chrome. It proves
  //     Vercel is serving THIS BUILD rather than a deployment-not-found page,
  //     an auth wall, or a parked domain — all of which are things a status
  //     code cannot tell you apart. It is not evidence the app works.
  const osHome = await check('D1.1', 'os.structtek.com', 'shell/chrome', async () => {
    const res = await probe(`${cfg.osBase}/`, {}, cfg.timeoutMs);
    return classifyContains(res, ['Sign in to your workspace.', 'name="password"', '<title>StructTech OS</title>']);
  });

  // 1.2 THE DATA-DRIVEN LAYER FOR THIS DOOR, and the reason it is here:
  //     a Next.js deploy can serve fresh HTML that references chunk hashes
  //     from a build that no longer exists. The page returns 200, the shell
  //     paints, and the app dies on ChunkLoadError in the browser — a failure
  //     CLAUDE.md names by hand (Supabase/App Router pattern 8) and one no
  //     status-code check can see. The asset hashes are emitted by the build,
  //     so this asserts on data the deployment produced, not on markup we
  //     wrote.
  await check('D1.2', 'os.structtek.com', 'build integrity', async () => {
    if (osHome.status === 'ERROR') throw new Undetermined('D1.1 did not return a document to parse');
    const res = await probe(`${cfg.osBase}/`, {}, cfg.timeoutMs);
    const assets = [...res.body.matchAll(/(?:href|src)="(\/_next\/static\/[^"]+\.(?:css|js))"/g)].map((m) => m[1]);
    if (assets.length === 0) return fail('the served HTML references ZERO /_next/static assets — this is not a rendered Next.js build');
    const bad = [];
    for (const a of assets.slice(0, 8)) {
      const r = await probe(`${cfg.osBase}${a}`, { method: 'GET' }, cfg.timeoutMs);
      if (r.status !== 200 || r.body.length === 0) bad.push(`${a} -> HTTP ${r.status}, ${r.body.length}B`);
    }
    if (bad.length) return fail(`the HTML references build assets that do not resolve — ChunkLoadError in every browser while the page still returns 200: ${bad.join('; ')}`);
    return pass(`${Math.min(assets.length, 8)} of ${assets.length} referenced build assets resolve with a non-empty body`);
  });

  // 1.3 THE ROADMAP ROUTE, AND THE REASON IT NEEDS ITS OWN ASSERTION.
  //     /roadmap/<token> is the only PUBLIC, UNAUTHENTICATED page this build
  //     serves. D1.1 and D1.2 both probe `/`, which is the login shell — they
  //     would stay green with this route 500ing or deleted, because nothing
  //     they look at touches it.
  //
  //     IT ASSERTS THE ROUTE RENDERS ONE OF ITS DESIGNED BRANCHES, NOT ONE
  //     PARTICULAR BRANCH. With a token that cannot exist, exactly two of the
  //     four outcomes in the route are correct: `restricted` (today — anon
  //     holds no EXECUTE on fetch_roadmap_by_token, so the call is refused
  //     42501) and `not_found` (after that grant lands, since the token is
  //     still nonsense). Pinning the assertion to today's branch would turn
  //     the grant — a change we intend to make — into a red monitor, and a
  //     monitor that goes red for correct changes is one people learn to
  //     ignore. The branch actually taken is printed either way, so the
  //     transition is legible in the run log when it happens.
  //
  //     KNOWN GAP, STATED RATHER THAN PAPERED OVER: the route maps PGRST202
  //     into `restricted` too, and PGRST202 is what PostgREST returns when the
  //     function is ABSENT from its schema cache. So a DROPPED
  //     fetch_roadmap_by_token renders identically to a missing grant and this
  //     probe stays green. It cannot separate them from outside; only the
  //     printed detail string distinguishes them, and only to a reader. This
  //     check covers "the route is serving", not "the function still exists".
  await check('D1.3', 'os.structtek.com', 'public roadmap route', async () => {
    // A token that cannot collide with a real one, so this never opens a
    // client's roadmap and never needs a real token to run.
    const res = await probe(`${cfg.osBase}/roadmap/frontdoor-monitor-nonexistent-token`, {}, cfg.timeoutMs);

    if (res.status !== 200) {
      return fail(`HTTP ${res.status} from the public roadmap route — the only unauthenticated page in the build is not serving. Body: ${res.body.slice(0, 200)}`);
    }

    // Chrome first: proves this is OUR page and not an edge/CDN error document
    // that happens to contain prose.
    const chrome = classifyContains(res, ['Operations Roadmap', 'StructTech']);
    if (chrome.status !== 'PASS') return chrome;

    // Copy chosen to avoid the typographic apostrophes in the headings — the
    // headings render U+2019 raw, and matching on it is a byte-level
    // dependency on a character nobody would think to preserve in an edit.
    const RESTRICTED = 'The link is being held by StructTech and is not readable from here yet.';
    const NOT_FOUND  = 'The link may have been mistyped';
    const ERRORED    = 'This is a problem on our end, not with your link.';

    if (res.body.includes(ERRORED)) {
      return fail('the roadmap route rendered its ERROR branch — the RPC failed with something other than a permissions/absence code, which is a backend fault, not a closed door');
    }
    if (res.body.includes(RESTRICTED)) {
      const code = res.body.match(/(42501|PGRST202|PGRST301)/)?.[1] ?? 'code not printed';
      return pass(`HTTP 200, designed branch = restricted (${code}) — the route is serving and refusing correctly`);
    }
    if (res.body.includes(NOT_FOUND)) {
      return pass('HTTP 200, designed branch = not_found — the RPC was reachable and matched nothing, so anon EXECUTE has landed');
    }
    return fail('HTTP 200 with our chrome but NONE of the route\'s designed branch copy — the page rendered something it has no code path to render');
  });

  // 1.4 WHAT IS DEPLOYED. On 2026-09-07 this question had no answer available
  //     to anyone outside the Vercel account: the Vercel API returns 403 to
  //     us, the served HTML exposes no buildId, and the only build-derived
  //     strings are content hashes that name a bundle rather than a commit.
  //     "Is the fix live?" could be answered only by reasoning. /api/health
  //     ends that, and this probe is what keeps it answerable — a health route
  //     nobody reads rots exactly as quietly as no health route at all.
  //
  //     THE 404 BRANCH IS A DEADLINE, NOT AN EXEMPTION. The route ships in the
  //     same change as this check, so between merge and deploy it legitimately
  //     does not exist, and a red monitor for a known reason is how people
  //     learn to ignore red. So a 404 reads UNDETERMINED — until
  //     HEALTH_ROUTE_DUE, after which it reads FAIL. The allowance expires by
  //     the calendar rather than by somebody remembering to tighten it, which
  //     is the difference between a control and an intention.
  // Probed ONCE, outside check(), because "the route is not deployed yet" is
  // not one of the three verdicts this monitor has. It is not a door being
  // down (FAIL) and it is not the monitor being blind (ERROR) — and routing it
  // through ERROR is exactly the mistake this block exists to correct.
  //
  // FOUND BY THE GUARD-ON-THE-GUARD, 2026-09-07T23:03Z. The first version of
  // D1.4 threw Undetermined on a 404, which made the whole run UNDETERMINED,
  // which exits 2, which FAILS the workflow step — turning every scheduled run
  // red for a reason everybody already knew, which is the precise outcome the
  // 404 branch was written to avoid. The fault-injection job caught it on the
  // first push ("fault mode '' exited 2, wanted 0"). It got past local testing
  // because the local check read `$?` after piping the monitor into grep and
  // graded grep's exit status instead of the monitor's.
  //
  // So: when the route is absent and the deadline has not passed, D1.4
  // REGISTERS NO VERDICT. It prints, and the run is unaffected. After
  // HEALTH_ROUTE_DUE a 404 is a real failure and is graded as one.
  const healthPre = await probe(`${cfg.osBase}/api/health`, {}, cfg.timeoutMs).catch(() => null);
  const healthOverdue = Date.now() > Date.parse(HEALTH_ROUTE_DUE);

  if (healthPre?.status === 404 && !healthOverdue) {
    console.log(`[ --  ] D1.4  (os.structtek.com · deployed commit is readable)`);
    console.log(`         not deployed yet — /api/health returns 404. NOT GRADED until ${HEALTH_ROUTE_DUE}, a failure after it.`);
  } else {
  await check('D1.4', 'os.structtek.com', 'deployed commit is readable', async () => {
    const res = healthPre ?? await probe(`${cfg.osBase}/api/health`, {}, cfg.timeoutMs);

    if (res.status === 404) {
      return fail(`/api/health returns 404 — the deployment cannot report its own commit, and the ${HEALTH_ROUTE_DUE} grace period has expired.`);
    }
    if (res.status !== 200) return fail(`HTTP ${res.status} from /api/health. Body: ${res.body.slice(0, 200)}`);

    let payload;
    try {
      payload = JSON.parse(res.body);
    } catch {
      return fail(`/api/health returned 200 but not JSON — something other than the route is answering that path. Body: ${res.body.slice(0, 120)}`);
    }

    // `sha` null is the route's HONEST answer when VERCEL_GIT_COMMIT_SHA is
    // absent — which on the production host means the build was not produced
    // from a git commit Vercel could name. That is a real defect in the
    // deployment, not a monitor problem, so it FAILS rather than erroring.
    if (typeof payload.sha !== 'string' || !/^[0-9a-f]{40}$/.test(payload.sha)) {
      return fail(`/api/health answered but reports sha=${JSON.stringify(payload.sha)} — the deployment cannot name its own commit, so "is the fix live?" is still unanswerable`);
    }
    // DEPLOY DRIFT — REPORTED, NOT GRADED, and the distinction is the point.
    //
    // GITHUB_SHA on a scheduled run IS the default branch's head at dispatch,
    // so comparing it to the deployed sha answers "is production running main?"
    // for free — no API call, no token, no new permission. It is read from the
    // runner's own environment, so outside Actions it is simply absent and the
    // comparison is omitted rather than guessed at.
    //
    // It is NOT graded because a deploy legitimately lags a merge by minutes,
    // and this monitor has no memory — it cannot tell "mid-deploy" from "stuck
    // three days behind", which is the only distinction that would make a
    // verdict meaningful. Inventing a threshold here would be building a gate
    // out of a statistic, which is exactly the error the cron mean already
    // taught us. Report the two SHAs, let a reader who can see history judge.
    const headSha = process.env.GITHUB_SHA;
    const drift = !headSha
      ? ''
      : headSha === payload.sha
        ? ' · matches default branch'
        : ` · DEFAULT BRANCH IS ${headSha.slice(0, 7)} — production is not running it`;

    // Printed on every run ON PURPOSE: the run log then carries a deployment
    // history for free, and a deploy becomes visible as a change in this line.
    return pass(`deployed sha=${payload.sha.slice(0, 7)} env=${payload.env ?? '(none)'}${drift}`);
  });
  }

  // === DOOR 2 · audit.structtek.com — the live lead-capture revenue path ===

  await check('D2.1', 'audit.structtek.com', 'shell/chrome', async () => {
    const res = await probe(`${cfg.auditBase}/`, {}, cfg.timeoutMs);
    return classifyContains(res, ['START MY FREE SCAN', 'href="scan.html"']);
  });

  // 2.2 THE DATA-DRIVEN ASSERTION FOR THIS DOOR.
  //     audit.structtek.com is static HTML on GitHub Pages: every visible
  //     element renders identically whether the backend is alive or dead, so
  //     no visible string on it can be evidence of anything. The one part of
  //     the site that is not chrome is the capture machinery in results.html
  //     — the fetch that turns a completed scan into a row. A redeploy that
  //     drops, renames or breaks it leaves a page that looks perfect, returns
  //     200, and captures nothing.
  let writePath = null;
  await check('D2.2', 'audit.structtek.com', 'capture machinery', async () => {
    const res = await probe(`${cfg.auditBase}/results.html`, {}, cfg.timeoutMs);
    const verdict = classifyContains(res, [
      '/rest/v1/audit_leads',
      "'Prefer': 'return=minimal'",
      'var SUPA_URL',
      'var SUPA_KEY',
    ]);
    if (verdict.status === 'PASS') {
      const url = res.body.match(/var SUPA_URL\s*=\s*'([^']+)'/)?.[1];
      const key = res.body.match(/var SUPA_KEY\s*=\s*'([^']+)'/)?.[1];
      if (!url || !key) return fail('the SUPA_URL / SUPA_KEY assignments are present but unparseable — the write path has been restructured');
      writePath = { url, key };
    }
    return verdict;
  });

  // 2.3 THE LIVE WRITE PATH, EXERCISED — NON-DESTRUCTIVELY.
  //     Same endpoint, same headers and the same publishable key the live
  //     page ships, with a payload that cannot become a row (`score` is
  //     `integer`; a non-numeric value fails coercion before any trigger
  //     fires). Postgres checks the INSERT privilege BEFORE it evaluates the
  //     row, so the two outcomes separate cleanly: 42501 means the grant is
  //     gone, 22P02 means it is intact. Verified on 2026-09-02 to write
  //     nothing: audit_leads rows with source='frontdoor-monitor' = 0.
  await check('D2.3', 'audit.structtek.com', 'live write path', async () => {
    if (!writePath) throw new Undetermined('D2.2 did not yield a write path to probe — nothing was tested');
    const res = await probe(`${writePath.url}/rest/v1/audit_leads`, {
      method: 'POST',
      headers: {
        apikey: writePath.key,
        Authorization: `Bearer ${writePath.key}`,
        'Content-Type': 'application/json',
        Prefer: 'return=minimal',
      },
      body: JSON.stringify({ email: null, score: '__frontdoor_monitor_probe__', source: 'frontdoor-monitor' }),
    }, cfg.timeoutMs);
    return classifyWriteProbe(res);
  });

  // === DOOR 3 · the shared backend both doors stand on =====================
  //     Supabase ejlhrykcdfcyeooooodx. Not a front door itself, but the only
  //     place where a change makes both doors return 200 and do nothing.

  await check('D3.1', 'supabase/auth', 'sign-in config', async () => {
    if (!writePath) throw new Undetermined('no backend URL available (D2.2 did not resolve one)');
    const res = await probe(`${writePath.url}/auth/v1/settings`, { headers: { apikey: writePath.key } }, cfg.timeoutMs);
    if (res.status !== 200) return fail(`HTTP ${res.status} from GoTrue — the identity provider that gates every os.structtek.com session is not answering. Body: ${res.body.slice(0, 200)}`);
    // Email/password is the ONLY enabled sign-in method (measured 2026-09-02:
    // every external provider reads false). If this flips, nobody can log in
    // while /login keeps returning a perfectly rendered 200.
    return classifyContains(res, ['"email":true']);
  });

  await check('D3.2', 'supabase/postgrest', 'anon closure invariant', async () => {
    if (!writePath) throw new Undetermined('no backend URL available (D2.2 did not resolve one)');
    const res = await probe(`${writePath.url}/rest/v1/deals?select=id&limit=1`, {
      headers: { apikey: writePath.key, Authorization: `Bearer ${writePath.key}` },
    }, cfg.timeoutMs);
    return classifyAnonClosed(res, 'deals');
  });

  return summarise();
}

// ---------------------------------------------------------------------------
// Self-test of the classifiers.  These are the branches production must never
// reach, so they cannot be induced against the live doors — but they are the
// branches an outage would take, and shipping them untested is shipping an
// unproven guard.  Same functions, synthetic responses.
// ---------------------------------------------------------------------------
function selftest() {
  const cases = [
    ['write probe · 400 + 22P02 (grant intact)',            () => classifyWriteProbe({ status: 400, body: '{"code":"22P02","message":"invalid input syntax for type integer"}' }), 'PASS'],
    ['write probe · 401 + 42501 (grant revoked, leads lost)', () => classifyWriteProbe({ status: 401, body: '{"code":"42501","message":"permission denied for table audit_leads"}' }), 'FAIL'],
    ['write probe · 201 created (probe payload accepted)',   () => classifyWriteProbe({ status: 201, body: '' }), 'FAIL'],
    ['write probe · 503 gateway',                            () => classifyWriteProbe({ status: 503, body: 'upstream unavailable' }), 'FAIL'],
    ['anon closure · 401 + form 1 (closed)',                 () => classifyAnonClosed({ status: 401, body: '{"code":"42501","message":"permission denied for table deals"}' }, 'deals'), 'PASS'],
    ['anon closure · 200 [] (form 2 — grant is BACK)',       () => classifyAnonClosed({ status: 200, body: '[]' }, 'deals'), 'FAIL'],
    ['anon closure · 200 with rows (wide open)',             () => classifyAnonClosed({ status: 200, body: '[{"id":"abc"}]' }, 'deals'), 'FAIL'],
    ['anon closure · 401 naming my_org_ids (form 3)',        () => classifyAnonClosed({ status: 401, body: '{"code":"42501","message":"permission denied for function my_org_ids"}' }, 'deals'), 'FAIL'],
    ['contains · all present',                               () => classifyContains({ status: 200, body: 'alpha beta' }, ['alpha', 'beta']), 'PASS'],
    ['contains · one absent (200 with content gone)',        () => classifyContains({ status: 200, body: 'alpha' }, ['alpha', 'beta']), 'FAIL'],
  ];
  let bad = 0;
  console.log('Classifier self-test — the branches production must never reach:\n');
  for (const [name, fn, expected] of cases) {
    const got = fn().status;
    const ok = got === expected;
    if (!ok) bad++;
    console.log(`  ${ok ? 'ok  ' : 'FAIL'}  expected ${expected.padEnd(4)} got ${got.padEnd(4)}  ${name}`);
  }
  console.log(`\n${cases.length - bad}/${cases.length} classifier cases correct.`);
  return bad === 0 ? 0 : 1;
}

// ---------------------------------------------------------------------------
function summarise() {
  const n = (s) => results.filter((r) => r.status === s).length;
  const fails = n('FAIL'), errors = n('ERROR'), passes = n('PASS');
  const verdict = fails ? 'OUTAGE' : errors ? 'UNDETERMINED' : 'HEALTHY';

  console.log(`\n${'-'.repeat(72)}`);
  console.log(`VERDICT: ${verdict}   (${passes} pass · ${fails} fail · ${errors} undetermined)`);
  if (fails) console.log('FAIL means a door answered and the content that proves it works was absent. Treat as an outage.');
  if (errors) console.log('UNDETERMINED means the MONITOR could not tell. It is NOT a claim that anything is down — and it is not a clean bill of health either.');
  console.log(`${'-'.repeat(72)}`);

  if (process.env.GITHUB_STEP_SUMMARY) {
    const rows = results.map((r) => `| ${r.status} | \`${r.id}\` | ${r.door} | ${r.layer} | ${redact(r.detail).replace(/\|/g, '\\|').slice(0, 300)} |`).join('\n');
    const md = `### Front-door monitor — **${verdict}**\n\n${passes} pass · ${fails} fail · ${errors} undetermined\n\n| | id | door | layer | detail |\n|---|---|---|---|---|\n${rows}\n`;
    try { appendFileSync(process.env.GITHUB_STEP_SUMMARY, md); } catch { /* summary is a nicety, never a verdict */ }
  }

  // Distinct exit codes so the runner log says WHICH kind of bad it was.
  return fails ? 1 : errors ? 2 : 0;
}

// ---------------------------------------------------------------------------
let code;
try {
  code = SELFTEST ? selftest() : await run();
} catch (err) {
  console.error(`\n[ERROR] the monitor itself failed to run — ${err.name}: ${err.message}`);
  console.error('This is UNDETERMINED, not an outage. Nothing about the front doors was established.');
  code = 2;
}
process.exit(code);
