#!/usr/bin/env node
// Is the sending domain's DNS ready for transactional email?  Track X, X-W1.13.
// REWRITTEN 2026-09-15 (EDT). It was checking a domain that does not exist, in a
// record shape Resend did not issue. Both halves were wrong and only one was noticed.
//
// WHAT WAS WRONG, part 1 — THE DOMAIN. This script hardcoded
// `notify.structtek.com`, because that subdomain was named in the original
// instructions. Wix does not support MX records on a subdomain, so the domain was
// deleted and re-added at the APEX, `structtek.com`. Nothing told this script.
// It went on resolving a hostname that has never existed and reporting the empty
// answers as missing records — a confident NOT READY about a domain nobody uses.
// FIXED BY REMOVING THE CONSTANT: the domain is now derived from EMAIL_FROM, the
// same variable sendEmail() actually sends with, so the two cannot drift apart.
//
// WHAT WAS WRONG, part 2 — THE RECORD SHAPE, and this one would have survived
// fixing part 1. The script required, at `send.<domain>`, an `amazonses.com` MX
// and an SPF `include:amazonses.com`. That is ONE of the two record sets Resend
// issues. The re-added domain got the other. Measured at structtek.com 2026-09-15:
//
//   resend._domainkey.structtek.com  TXT    p=MIGfMA0...           (DKIM)
//   send.structtek.com               CNAME  send.forge.rmta.net    (return path)
//     -> resolves to MX feedback.forge.rmta.net, TXT v=spf1 ip4:... ~all
//   rsend.structtek.com              CNAME  rsend.forge.rmta.net
//     -> resolves to TXT v=spf1 include:amazonses.com ~all
//
// So the live, Resend-VERIFIED, working configuration would have been graded NOT
// READY by the old checks: the MX is `forge.rmta.net`, not `amazonses.com`, and
// the SPF at `send.` is ip4 literals, not an include. Pointing the old script at
// the right domain would have produced the same wrong verdict with more authority.
//
// SO THIS GRADES THE FUNCTION, NOT THE VENDOR'S CURRENT HOSTNAMES. A sending
// domain needs three things to be true, and each is checked as itself:
//   DKIM         a TXT at resend._domainkey.<domain> carrying a p= public key
//   RETURN PATH  an MX at send.<domain> that resolves to some host
//   SPF          exactly one v=spf1 TXT covering that return path
// The specific hostnames are REPORTED, so drift is visible, but they are not the
// pass condition. A checker that pins a vendor's internal hostnames fails the day
// the vendor changes them and blames the operator.
//
// The apex SPF check is unchanged and independent: it is about Google Workspace,
// LeadConnector and Mailgun sending AS structtek.com, and does not gate Resend,
// which signs DKIM and aligns via its own subdomain.
//
// exit 0 both ready · exit 1 at least one not ready · exit 2 could not resolve
//
// Usage: node scripts/email/verify-email-dns.mjs
//        EMAIL_DOMAIN=... overrides the domain derived from EMAIL_FROM.
//        APEX=...         overrides the apex derived from that domain.

import { Resolver } from 'node:dns/promises';
import { readFileSync } from 'node:fs';

function fromEnvFile(name) {
  try {
    for (const line of readFileSync('.env.local', 'utf8').split('\n')) {
      const m = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*(.*?)\s*$/);
      if (m && m[1] === name) return m[2].replace(/^["']|["']$/g, '').replace(/\r/g, '');
    }
  } catch { /* no file */ }
  return undefined;
}

// THE DOMAIN IS DERIVED, NEVER DECLARED. EMAIL_FROM is what sendEmail() puts in
// the From header; checking anything else checks a domain the product does not use.
const EMAIL_FROM = process.env.EMAIL_FROM || fromEnvFile('EMAIL_FROM');
const derived = EMAIL_FROM ? (EMAIL_FROM.match(/@([^>\s]+)>?\s*$/) || [])[1] : undefined;
const EMAIL_DOMAIN = process.env.EMAIL_DOMAIN || derived;

if (!EMAIL_DOMAIN) {
  console.log('UNDETERMINED: no sending domain. Set EMAIL_FROM (in the environment or .env.local),');
  console.log('              or pass EMAIL_DOMAIN=<domain> explicitly.');
  process.exit(2);
}
// Registrable-domain guess: the last two labels. Correct for structtek.com and for
// every domain this project uses. It is WRONG for multi-part public suffixes
// (example.co.uk), which is why APEX stays overridable rather than being trusted.
const APEX = process.env.APEX || EMAIL_DOMAIN.split('.').slice(-2).join('.');
const REQUIRED_SENDERS = ['_spf.google.com', 'spf.leadconnectorhq.com', 'mailgun.org'];

const r = new Resolver();
r.setServers(['1.1.1.1', '8.8.8.8']);

const soft = (e) => (e.code === 'ENOTFOUND' || e.code === 'ENODATA' ? null : undefined);
const txt = async (name) => {
  try { return (await r.resolveTxt(name)).map((chunks) => chunks.join('')); }
  catch (e) { if (soft(e) === null) return []; throw e; }
};
const mx = async (name) => {
  try { return (await r.resolveMx(name)).map((m) => m.exchange); }
  catch (e) { if (soft(e) === null) return []; throw e; }
};
const cname = async (name) => {
  try { return await r.resolveCname(name); }
  catch (e) { if (soft(e) === null) return []; throw e; }
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

const say = (s) => console.log(s);
let notReady = 0;

try {
  // ------------------------------------------------------------------ apex SPF
  say(`APEX ${APEX}`);
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

  // -------------------------------------------------------- Resend sending domain
  say(`RESEND ${EMAIL_DOMAIN}${derived && !process.env.EMAIL_DOMAIN ? '   (derived from EMAIL_FROM)' : ''}`);

  const dkimName = `resend._domainkey.${EMAIL_DOMAIN}`;
  const sendName = `send.${EMAIL_DOMAIN}`;
  const rsendName = `rsend.${EMAIL_DOMAIN}`;

  const dkim = await txt(dkimName);
  const dkimCname = await cname(dkimName);
  const sendMx = await mx(sendName);
  const sendCname = await cname(sendName);
  const sendSpf = (await txt(sendName)).filter((t) => t.startsWith('v=spf1'));
  const rsendCname = await cname(rsendName);
  const rsendSpf = (await txt(rsendName)).filter((t) => t.startsWith('v=spf1'));

  // PASS CONDITIONS — stated as the function each record performs, so that either
  // record shape Resend issues can satisfy them. The hostnames are shown, not graded.
  const okDkim = dkim.some((t) => t.includes('p='));
  const okMx = sendMx.length > 0;
  const okSpf = sendSpf.length === 1 || rsendSpf.length === 1;

  const shape = sendCname.length || rsendCname.length ? 'CNAME' : 'MX + TXT';

  say(`  record shape: ${shape}${shape === 'CNAME' ? '  (the variant Resend issues when the apex already has MX records)' : ''}`);
  say(`  DKIM   TXT ${dkimName}: ${okDkim ? `present (${dkim[0].slice(0, 24)}…)` : 'MISSING'}${dkimCname.length ? `  via CNAME ${dkimCname.join(', ')}` : ''}`);
  say(`  RETURN MX  ${sendName}: ${sendMx.length ? sendMx.join(', ') : 'MISSING'}${sendCname.length ? `  via CNAME ${sendCname.join(', ')}` : ''}`);
  say(`  SPF    TXT ${sendName}: ${sendSpf.length ? sendSpf.join(' | ') : '(none)'}`);
  say(`  SPF    TXT ${rsendName}: ${rsendSpf.length ? rsendSpf.join(' | ') : '(none)'}${rsendCname.length ? `  via CNAME ${rsendCname.join(', ')}` : ''}`);

  if (okDkim && okMx && okSpf) {
    say('  READY — DKIM key published, return path has an MX, and the return path is SPF-covered');
    say('  NOTE — DNS records are necessary, not sufficient. Only Resend can say the domain is');
    say('         Verified, and only a send proves it. verify-email-send.mjs determines both.');
  } else {
    notReady++;
    const why = [!okDkim && 'DKIM TXT', !okMx && 'return-path MX', !okSpf && 'return-path SPF'].filter(Boolean).join(', ');
    say(`  NOT READY — missing: ${why}. Add the records Resend shows for ${EMAIL_DOMAIN} at https://resend.com/domains`);
  }
} catch (e) {
  console.log('------------------------------------------------------------------------');
  console.log(`UNDETERMINED: DNS resolution failed (${e.code || e.name}). This says nothing about the records.`);
  process.exit(2);
}

console.log('------------------------------------------------------------------------');
console.log(notReady ? `NOT READY: ${notReady} of 2 checks` : 'READY: apex SPF and Resend sending domain');
process.exit(notReady ? 1 : 0);
