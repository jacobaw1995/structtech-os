#!/usr/bin/env node
// Can this app actually send email?  Track X, X-W1.13, 2026-09-14.
// REWRITTEN 2026-09-15 (EDT) after this script reported a WORKING key as refused.
//
// WHAT WENT WRONG, because the shape of the mistake matters more than the fix.
// This script had never once talked to real Resend — it was built and exercised
// entirely against a stub, because no key existed yet. A stub answers whatever it
// is written to answer, so the one thing it could not test was how REAL Resend
// refuses. The first real key produced HTTP 401 on GET /domains and this script
// said "Resend refused the key". The key was fine. Resend's 401 there means
// "this key is restricted to only send emails" — a PERMISSION answer, not an
// AUTHENTICATION answer — and a send-only key is the CORRECT key for an app that
// only sends. The verifier demanded an account-wide read scope the product never
// needs and then blamed the credential for not having it.
//
// This is CLAUDE.md rule 11 in another vendor's clothing: GRADE THE REFUSAL ON
// THE MESSAGE, NOT ON THE STATUS CODE. Measured against real Resend 2026-09-15:
//
//   endpoint      condition                    status  name
//   GET /domains  real key, send-scoped        401     restricted_api_key   <- VALID
//   POST /emails  real key, verified domain    200     (id returned)
//   GET /domains  fake key                     400     validation_error
//   POST /emails  fake key                     401     validation_error     <- INVALID
//   GET /domains  no Authorization header      401     missing_api_key
//   POST /emails  real key, unverified domain  403     "not authorized to send from X"
//
// THREE DIFFERENT CAUSES SHARE HTTP 401 AND TWO OF THEM ARE NOT AUTH FAILURES.
// Any grader that branches on `status === 401` reports a pass or a fail for
// reasons unrelated to what it claims to measure. Branch on `name`.
//
// HOW READINESS IS DETERMINED WITH A SEND-ONLY KEY. Such a key cannot read
// /domains, so "is the domain verified?" has no read route. It has a WRITE route:
// a send from an unverified domain is refused 403 with that exact reason. So the
// script posts one message to `delivered@resend.dev` — Resend's own sink, not a
// person — which exercises the identical path the product uses and returns the
// determination. It announces that it is doing so. `--no-probe` keeps the older
// "this script never sends anything" guarantee for anyone who wants it, at the
// cost of the answer.
//
// Mailing a REAL person is still gated behind --send-test-to <address>.
//
// exit 0 READY   the key authenticates and this account can send as EMAIL_FROM
// exit 1 NOT READY  a variable is missing, the key is invalid, or the domain is
//                   not authorised for this key
// exit 2 UNDETERMINED  Resend unreachable, an unexpected response shape, or
//                      --no-probe with a send-only key (readiness unknowable)
//
// No secret is printed. The key is reported by NAME and by presence only, and
// every upstream string is redacted before it is shown.
//
// Reads .env.local when the variables are not already in the environment.
// RESEND_API_BASE overrides https://api.resend.com for testing only.

import { readFileSync } from 'node:fs';

const BASE = process.env.RESEND_API_BASE || 'https://api.resend.com';
const argAfter = (flag) => {
  const i = process.argv.indexOf(flag);
  return i > -1 ? process.argv[i + 1] : null;
};
const TEST_TO = argAfter('--send-test-to');
const NO_PROBE = process.argv.includes('--no-probe');
const SINK = 'delivered@resend.dev';

function done(code, verdict, detail) {
  console.log('------------------------------------------------------------------------');
  console.log(`${verdict}: ${detail}`);
  process.exit(code);
}

// Redact anything that could carry the credential, before any upstream text is
// shown. Same reasoning as src/lib/email/send.ts: the promise "we never print the
// key" has to be a property of the code, not a sentence in a comment.
const redact = (s) =>
  String(s)
    .replace(/\bre_[A-Za-z0-9_]{8,}/g, '[redacted]')
    .replace(/Bearer\s+\S+/gi, 'Bearer [redacted]');

function fromEnvFile(name) {
  try {
    for (const line of readFileSync('.env.local', 'utf8').split('\n')) {
      const m = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*(.*?)\s*$/);
      // Trailing whitespace and a stray CR are stripped above. A value that
      // silently carries "\r" from a CRLF file produces a malformed Authorization
      // header and an auth failure that looks exactly like a bad key.
      if (m && m[1] === name) return m[2].replace(/^["']|["']$/g, '').replace(/\r/g, '');
    }
  } catch { /* no file */ }
  return undefined;
}

const key = process.env.RESEND_API_KEY || fromEnvFile('RESEND_API_KEY');
const from = process.env.EMAIL_FROM || fromEnvFile('EMAIL_FROM');
console.log(`RESEND_API_KEY: ${key ? 'present' : 'MISSING'}`);
console.log(`EMAIL_FROM:     ${from ? `present — ${from}` : 'MISSING'}`);
if (!key || !from) done(1, 'NOT READY', `missing ${[!key && 'RESEND_API_KEY', !from && 'EMAIL_FROM'].filter(Boolean).join(' and ')}.`);

const domain = (from.match(/@([^>\s]+)>?\s*$/) || [])[1];
if (!domain) done(1, 'NOT READY', 'EMAIL_FROM has no @domain — expected e.g. "StructTech OS <documents@structtek.com>".');
console.log(`sending domain: ${domain}   (derived from EMAIL_FROM, never hardcoded)`);

const BAD_KEY_BLOCK = [
  '',
  '  WHAT TO DO — this is the one step that needs you, because it is a credential:',
  '    1. https://resend.com/api-keys  ->  Create API Key',
  '    2. Permission "Sending access" is enough; this app only sends.',
  '    3. COPY IT FROM THE POPUP. The list view truncates the value, and a',
  '       truncated key fails exactly like an invalid one.',
  '    4. Replace the RESEND_API_KEY line in .env.local, and update it in Vercel',
  '       (Project -> Settings -> Environment Variables -> Production), then redeploy.',
].join('\n');

async function call(path, init = {}) {
  try {
    const res = await fetch(`${BASE}${path}`, {
      ...init,
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json', ...(init.headers || {}) },
      signal: AbortSignal.timeout(15_000),
    });
    let body = null;
    try { body = await res.json(); } catch { /* shape checked by caller */ }
    return { status: res.status, body, name: body?.name ?? null, message: body?.message ?? null };
  } catch (e) {
    done(2, 'UNDETERMINED', `Resend unreachable (${e.name}). This says nothing about the key or the domain.`);
  }
}

// ---------------------------------------------------------------- step 1: key
// Graded on `name`. See the table at the top: status alone cannot tell these apart.
const domains = await call('/domains');

if (domains.name === 'validation_error' || domains.name === 'missing_api_key') {
  console.log(`key check: REJECTED — Resend says "${redact(domains.message)}" (${domains.name}).`);
  console.log(BAD_KEY_BLOCK);
  done(1, 'NOT READY', 'the key itself is not accepted by Resend. Nothing downstream can work until it is replaced.');
}

let entry = null;
let restricted = false;

if (domains.name === 'restricted_api_key' || domains.status === 403) {
  restricted = true;
  console.log('key check: ACCEPTED — send-scoped key ("restricted_api_key").');
  console.log('           This is the CORRECT key type for this app, which only sends.');
  console.log('           It cannot read /domains, so domain status has no read route.');
} else if (domains.status === 200 && Array.isArray(domains.body?.data)) {
  console.log('key check: ACCEPTED — full-access key.');
  entry = domains.body.data.find((d) => String(d.name).toLowerCase() === domain.toLowerCase());
  console.log(`domains on the account: ${domains.body.data.length} · ${domain}: ${entry ? entry.status : 'NOT ADDED'}`);
  if (!entry) done(1, 'NOT READY', `${domain} is not added to this Resend account.`);
  if (entry.status !== 'verified') done(1, 'NOT READY', `${domain} is "${entry.status}", not "verified". Run verify-email-dns.mjs, then press Verify in Resend.`);
} else {
  done(2, 'UNDETERMINED', `unexpected /domains response (HTTP ${domains.status}${domains.name ? `, ${domains.name}` : ''}).`);
}

// ------------------------------------------------- step 2: can we send AS `from`
// The full-access branch already read this. The send-scoped branch has to write.
if (restricted) {
  if (NO_PROBE) {
    done(2, 'UNDETERMINED', `the key is valid and send-scoped, but --no-probe was passed. Whether ${domain} is authorised for it cannot be read with a send-only key — drop --no-probe to determine it.`);
  }
  console.log(`domain check: sending one message to ${SINK} (Resend's sink, not a person) to determine`);
  console.log(`              whether ${domain} is authorised for this key. An unverified domain is refused 403.`);
  const probe = await call('/emails', {
    method: 'POST',
    body: JSON.stringify({
      from,
      to: SINK,
      subject: 'StructTech OS — domain authorisation probe',
      text: 'Automated probe from verify-email-send.mjs. Discarded by Resend.',
    }),
  });
  if (probe.status === 403) {
    console.log(`domain check: REFUSED — "${redact(probe.message)}"`);
    done(1, 'NOT READY', `this key is not authorised to send as ${domain}. Add and verify ${domain} at https://resend.com/domains, then re-run.`);
  }
  if (probe.name === 'validation_error') {
    console.log(`key check: REJECTED on send — "${redact(probe.message)}".`);
    console.log(BAD_KEY_BLOCK);
    done(1, 'NOT READY', 'the key is not accepted by Resend.');
  }
  if (!(probe.status >= 200 && probe.status < 300 && typeof probe.body?.id === 'string')) {
    done(2, 'UNDETERMINED', `probe send returned HTTP ${probe.status}${probe.name ? ` (${probe.name})` : ''} without a message id.`);
  }
  console.log(`domain check: AUTHORISED — Resend accepted a message from ${domain} (probe id ${probe.body.id}).`);
}

// ------------------------------------------------ step 3: optional real message
if (!TEST_TO) {
  done(0, 'READY', `the key is accepted and this account can send as ${domain}. No message sent to a person (pass --send-test-to <address> to send one).`);
}

const sent = await call('/emails', {
  method: 'POST',
  body: JSON.stringify({
    from, to: TEST_TO,
    subject: 'StructTech OS — transactional email test',
    text: `This is a test from verify-email-send.mjs at ${new Date().toISOString()}. If it arrived, transactional email works.`,
  }),
});
if (sent.status >= 200 && sent.status < 300 && typeof sent.body?.id === 'string') {
  done(0, 'READY', `Resend accepted a test message to ${TEST_TO} (id ${sent.body.id}). Acceptance is not delivery — confirm it arrived, and check it is not in spam.`);
}
if (sent.status >= 400 && sent.status < 500) {
  done(1, 'NOT READY', `Resend refused the test send (HTTP ${sent.status}${sent.name ? `, ${sent.name}` : ''})${sent.message ? `: ${redact(sent.message)}` : ''}.`);
}
done(2, 'UNDETERMINED', `test send returned HTTP ${sent.status} without a message id.`);
