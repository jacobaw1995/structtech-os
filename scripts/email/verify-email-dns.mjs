#!/usr/bin/env node
// Is structtek.com's DNS ready for transactional email?  Track X, X-W1.13, 2026-09-14.
//
// Two independent questions, graded separately, because they fail for different
// people and are fixed by different records:
//
//   1. APEX SPF — measured 2026-09-14: TWO `v=spf1` TXT records at structtek.com
//        v=spf1 include:_spf.google.com ~all
//        v=spf1 include:spf.leadconnectorhq.com include:mailgun.org ~all
//      RFC 7208 §4.5: more than one record is a PermError. This breaks SPF for mail
//      sent AS structtek.com by Google Workspace, LeadConnector and Mailgun.
//      It does NOT gate Resend: Resend's own docs put its SPF on the `send`
//      subdomain of the sending domain and sign DKIM, so Resend mail aligns for
//      DMARC without the apex. Repaired anyway, because it is live and cheap.
//      PASS requires exactly one record, all three existing senders still
//      included, and ≤10 DNS lookups (RFC 7208 §4.6.4) counted recursively.
//
//   2. RESEND SENDING DOMAIN — PASS requires, for EMAIL_DOMAIN:
//        TXT  resend._domainkey.<domain>   starting "p=" or "k=rsa"   (DKIM)
//        MX   send.<domain>                 an amazonses.com host      (return path)
//        TXT  send.<domain>                 v=spf1 including amazonses.com
//      These are public records, so this proves the DNS side; it cannot prove
//      Resend marked the domain Verified. verify-email-send.mjs checks that.
//
// exit 0 both ready · exit 1 at least one not ready · exit 2 could not resolve
//
// Usage: EMAIL_DOMAIN=notify.structtek.com node scripts/email/verify-email-dns.mjs
//        (EMAIL_DOMAIN defaults to notify.structtek.com; APEX defaults to structtek.com)

import { Resolver } from 'node:dns/promises';

const APEX = process.env.APEX || 'structtek.com';
const EMAIL_DOMAIN = process.env.EMAIL_DOMAIN || 'notify.structtek.com';
const REQUIRED_SENDERS = ['_spf.google.com', 'spf.leadconnectorhq.com', 'mailgun.org'];

const r = new Resolver();
r.setServers(['1.1.1.1', '8.8.8.8']);

const txt = async (name) => {
  try {
    return (await r.resolveTxt(name)).map((chunks) => chunks.join(''));
  } catch (e) {
    if (e.code === 'ENOTFOUND' || e.code === 'ENODATA') return [];
    throw e;
  }
};
const mx = async (name) => {
  try {
    return (await r.resolveMx(name)).map((m) => m.exchange);
  } catch (e) {
    if (e.code === 'ENOTFOUND' || e.code === 'ENODATA') return [];
    throw e;
  }
};

/** Recursive DNS-lookup count for an SPF record's terms (RFC 7208 §4.6.4). */
async function lookups(record, seen = new Set(), depth = 0) {
  if (depth > 12) return Infinity;
  let n = 0;
  for (const term of record.split(/\s+/)) {
    const m = term.match(/^[+~?-]?(include:|redirect=)(.+)$/);
    if (m) {
      n += 1;
      const dom = m[2];
      if (seen.has(dom)) continue;
      seen.add(dom);
      const child = (await txt(dom)).find((t) => t.startsWith('v=spf1'));
      if (child) n += await lookups(child, seen, depth + 1);
    } else if (/^[+~?-]?(a|mx|ptr)(:|$)|^[+~?-]?exists:/.test(term)) {
      n += 1;
    }
  }
  return n;
}

const lines = [];
const say = (s) => { lines.push(s); console.log(s); };
let notReady = 0;

try {
  say(`APEX ${APEX}`);
  // SPF_RECORDS_OVERRIDE (JSON array of strings) replaces ONLY the apex fetch, so the
  // READY branch can be exercised before the real record exists. Lookups inside the
  // override are still resolved live. Never set in production use.
  const spf = (process.env.SPF_RECORDS_OVERRIDE ? JSON.parse(process.env.SPF_RECORDS_OVERRIDE) : await txt(APEX))
    .filter((t) => t.startsWith('v=spf1'));
  if (process.env.SPF_RECORDS_OVERRIDE) say('  (apex records from SPF_RECORDS_OVERRIDE — test mode)');
  say(`  v=spf1 records: ${spf.length}`);
  spf.forEach((s) => say(`    ${s}`));
  if (spf.length !== 1) {
    notReady++;
    say(`  NOT READY — ${spf.length} SPF records. Exactly one is allowed; ${spf.length > 1 ? 'more is a PermError (RFC 7208 §4.5)' : 'none leaves senders unauthorised'}.`);
  } else {
    const missing = REQUIRED_SENDERS.filter((d) => !spf[0].includes(`include:${d}`));
    const n = await lookups(spf[0]);
    say(`  DNS lookups: ${n} (limit 10)`);
    if (missing.length) { notReady++; say(`  NOT READY — the merged record dropped a live sender: ${missing.join(', ')}`); }
    else if (n > 10) { notReady++; say(`  NOT READY — ${n} lookups exceeds 10, which is also a PermError`); }
    else say('  READY — one record, all three existing senders kept, under the lookup limit');
  }

  say(`RESEND ${EMAIL_DOMAIN}`);
  const dkim = await txt(`resend._domainkey.${EMAIL_DOMAIN}`);
  const sendMx = await mx(`send.${EMAIL_DOMAIN}`);
  const sendSpf = (await txt(`send.${EMAIL_DOMAIN}`)).filter((t) => t.startsWith('v=spf1'));
  const okDkim = dkim.some((t) => /^(p=|k=rsa)/.test(t) || t.includes('p='));
  const okMx = sendMx.some((h) => /amazonses\.com$/i.test(h));
  const okSpf = sendSpf.length === 1 && /include:amazonses\.com/.test(sendSpf[0]);
  say(`  DKIM  TXT resend._domainkey.${EMAIL_DOMAIN}: ${okDkim ? 'present' : 'MISSING'}`);
  say(`  MX    send.${EMAIL_DOMAIN}: ${sendMx.length ? sendMx.join(', ') : 'MISSING'}${sendMx.length && !okMx ? ' (not amazonses.com)' : ''}`);
  say(`  SPF   TXT send.${EMAIL_DOMAIN}: ${sendSpf.length ? sendSpf.join(' | ') : 'MISSING'}${sendSpf.length && !okSpf ? ' (must be exactly one, including amazonses.com)' : ''}`);
  if (okDkim && okMx && okSpf) say('  READY — DKIM, return-path MX and return-path SPF all published');
  else { notReady++; say('  NOT READY — add the records Resend shows for this domain'); }
} catch (e) {
  console.log('------------------------------------------------------------------------');
  console.log(`UNDETERMINED: DNS resolution failed (${e.code || e.name}). This says nothing about the records.`);
  process.exit(2);
}

console.log('------------------------------------------------------------------------');
console.log(notReady ? `NOT READY: ${notReady} of 2 checks` : 'READY: apex SPF and Resend sending domain');
process.exit(notReady ? 1 : 0);
