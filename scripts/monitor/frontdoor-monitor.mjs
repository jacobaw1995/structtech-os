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
  osBase:    'https://os.structtek.com',
  auditBase: 'https://audit.structtek.com',
};

const FAULT = process.env.MONITOR_FAULT || '';
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

async function probe(url, init, timeoutMs) {
  if (!url || !/^https?:\/\//.test(url)) {
    throw new Undetermined(`no usable URL configured (got ${JSON.stringify(url)})`);
  }
  let res;
  try {
    res = await fetch(url, { ...init, signal: AbortSignal.timeout(timeoutMs), redirect: 'follow' });
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
