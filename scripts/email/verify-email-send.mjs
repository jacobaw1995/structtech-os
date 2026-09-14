#!/usr/bin/env node
// Can this app actually send email?  Track X, X-W1.13, 2026-09-14.
//
// verify-email-dns.mjs proves the public records exist. That is not the same as
// Resend having VERIFIED the domain, and neither is the same as a message being
// accepted. This checks the two things that need the key, and prints no secret:
//
//   1. RESEND_API_KEY and EMAIL_FROM are present — by NAME only.
//   2. Resend lists the EMAIL_FROM domain and reports it `verified`.
//   3. ONLY with --send-test-to <address>: send one test message there and report
//      the id Resend returns. Never runs without that flag — sending mail is an
//      action on Jacob's behalf and is his to take.
//
// exit 0 ready (and, with the flag, a message was accepted)
// exit 1 not ready: a variable is missing, the domain is absent or not verified,
//        or Resend refused the key or the send
// exit 2 UNDETERMINED: Resend unreachable, or its response had an unexpected shape
//
// Reads .env.local when the variables are not already in the environment.
// RESEND_API_BASE overrides https://api.resend.com for testing only.

import { readFileSync } from 'node:fs';

const BASE = process.env.RESEND_API_BASE || 'https://api.resend.com';
const i = process.argv.indexOf('--send-test-to');
const TEST_TO = i > -1 ? process.argv[i + 1] : null;

function done(code, verdict, detail) {
  console.log('------------------------------------------------------------------------');
  console.log(`${verdict}: ${detail}`);
  process.exit(code);
}

function fromEnvFile(name) {
  try {
    for (const line of readFileSync('.env.local', 'utf8').split('\n')) {
      const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
      if (m && m[1] === name) return m[2].replace(/^["']|["']$/g, '');
    }
  } catch { /* no file */ }
  return undefined;
}

const key = process.env.RESEND_API_KEY || fromEnvFile('RESEND_API_KEY');
const from = process.env.EMAIL_FROM || fromEnvFile('EMAIL_FROM');
console.log(`RESEND_API_KEY: ${key ? 'present' : 'MISSING'}`);
console.log(`EMAIL_FROM:     ${from ? 'present' : 'MISSING'}`);
if (!key || !from) done(1, 'NOT READY', `missing ${[!key && 'RESEND_API_KEY', !from && 'EMAIL_FROM'].filter(Boolean).join(' and ')}.`);

const domain = (from.match(/@([^>\s]+)>?\s*$/) || [])[1];
if (!domain) done(1, 'NOT READY', 'EMAIL_FROM has no @domain — expected e.g. "StructTech <estimates@notify.structtek.com>".');
console.log(`sending domain: ${domain}`);

async function call(path, init = {}) {
  try {
    const res = await fetch(`${BASE}${path}`, {
      ...init,
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json', ...(init.headers || {}) },
      signal: AbortSignal.timeout(15_000),
    });
    let body = null;
    try { body = await res.json(); } catch { /* shape checked by caller */ }
    return { status: res.status, body };
  } catch (e) {
    done(2, 'UNDETERMINED', `Resend unreachable (${e.name}). This says nothing about the key or the domain.`);
  }
}

const domains = await call('/domains');
if (domains.status === 401 || domains.status === 403) done(1, 'NOT READY', `Resend refused the key (HTTP ${domains.status}).`);
if (domains.status !== 200 || !Array.isArray(domains.body?.data)) done(2, 'UNDETERMINED', `unexpected /domains response (HTTP ${domains.status}).`);

const entry = domains.body.data.find((d) => String(d.name).toLowerCase() === domain.toLowerCase());
console.log(`domains on the account: ${domains.body.data.length} · ${domain}: ${entry ? entry.status : 'NOT ADDED'}`);
if (!entry) done(1, 'NOT READY', `${domain} is not added to this Resend account.`);
if (entry.status !== 'verified') done(1, 'NOT READY', `${domain} is "${entry.status}", not "verified". Run verify-email-dns.mjs, then press Verify in Resend.`);

if (!TEST_TO) done(0, 'READY', `${domain} is verified and the key is accepted. No message sent (pass --send-test-to <address> to send one).`);

const sent = await call('/emails', {
  method: 'POST',
  body: JSON.stringify({
    from, to: TEST_TO,
    subject: 'StructTech OS — transactional email test',
    text: `This is a test from verify-email-send.mjs at ${new Date().toISOString()}. If it arrived, transactional email works.`,
  }),
});
if (sent.status >= 200 && sent.status < 300 && typeof sent.body?.id === 'string') {
  done(0, 'READY', `Resend accepted a test message (id ${sent.body.id}). Acceptance is not delivery — confirm it arrived, and check it is not in spam.`);
}
if (sent.status >= 400 && sent.status < 500) done(1, 'NOT READY', `Resend refused the test send (HTTP ${sent.status}).`);
done(2, 'UNDETERMINED', `test send returned HTTP ${sent.status} without a message id.`);
