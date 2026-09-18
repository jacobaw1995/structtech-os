#!/usr/bin/env node
// §4 checks 1-2 of supabase/proposals/20260915_x_w1_15_org_files_policies.md, against
// the REAL Storage API with REAL JWTs.  Track X, X-W1.19, 2026-09-17.
//
//   node scripts/storage/org-files-live-proof.mjs
//
// Needs a DISPOSABLE org created by Track S (never Brothers Metal Roofing) holding:
//   · one synthetic CREW member  (must be refused)
//   · one synthetic OFFICE/OWNER member (the control: must be allowed)
//   · one live TRADE work order
// Inputs come from .env.proof.local (gitignored by .env*.local), never argv, never
// printed:  PROOF_ORG_ID, PROOF_TRADE_WORK_ORDER_ID, PROOF_CREW_EMAIL,
// PROOF_CREW_PASSWORD, PROOF_OFFICE_EMAIL, PROOF_OFFICE_PASSWORD.
// The script refuses to run against the BMR org id.
//
//   CHECK 1  does the signed upload URL consult the INSERT policy?
//     office asks for a signed upload url on the trade work order → ISSUED  (control)
//     crew asks for the same kind of url on the same work order    → REFUSED
//     Only the identity differs, so a difference proves the policy was consulted.
//   CHECK 2  is the url bound to its path?
//     the office's issued url, PUT to its OWN path                  → 200   (control)
//     the same token, PUT to a DIFFERENT path in the same folder    → refused
//   Cleanup: the object written by the control is removed by the office user, and
//   the removal is confirmed by listing.
// exit 0 both proved · 1 a check failed · 2 could not run

import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const BMR = '9d32b5a9-e11e-401b-8fa7-969065b004ce';
const env = {};
for (const f of ['.env.local', '.env.proof.local']) {
  if (!existsSync(f)) continue;
  for (const line of readFileSync(f, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (m) env[m[1]] = m[2].replace(/^["']|["']$/g, '');
  }
}
const need = ['NEXT_PUBLIC_SUPABASE_URL', 'NEXT_PUBLIC_SUPABASE_ANON_KEY', 'PROOF_ORG_ID', 'PROOF_TRADE_WORK_ORDER_ID',
  'PROOF_CREW_EMAIL', 'PROOF_CREW_PASSWORD', 'PROOF_OFFICE_EMAIL', 'PROOF_OFFICE_PASSWORD'];
const missing = need.filter((k) => !env[k]);
const stop = (code, verdict, why) => { console.log('------------------------------------------------------------------------'); console.log(`${verdict}: ${why}`); process.exit(code); };
if (missing.length) stop(2, 'BLOCKED', `missing by name: ${missing.join(', ')} (in .env.proof.local)`);
if (env.PROOF_ORG_ID === BMR) stop(2, 'REFUSED TO RUN', 'PROOF_ORG_ID is Brothers Metal Roofing; the proof runs only in a disposable org');

const ORG = env.PROOF_ORG_ID, WO = env.PROOF_TRADE_WORK_ORDER_ID;
const client = () => createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
async function signIn(email, password, who) {
  const c = client();
  const { data, error } = await c.auth.signInWithPassword({ email, password });
  if (error || !data.session) stop(2, 'BLOCKED', `${who} could not sign in (${error?.code ?? 'no session'})`);
  return c;
}
const office = await signIn(env.PROOF_OFFICE_EMAIL, env.PROOF_OFFICE_PASSWORD, 'office');
const crew = await signIn(env.PROOF_CREW_EMAIL, env.PROOF_CREW_PASSWORD, 'crew');
const nonce = Math.random().toString(16).slice(2, 10);
const path = (tag) => `${ORG}/office-uploads/${WO}/${nonce}-${tag}.txt`;
const verdicts = [];
const say = (ok, line) => { verdicts.push(ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${line}`); };

// CHECK 1 ─────────────────────────────────────────────────────────────────────
const issued = await office.storage.from('org-files').createSignedUploadUrl(path('office'));
say(!issued.error && !!issued.data?.signedUrl, `control: office is issued a signed upload url (${issued.error ? issued.error.message : 'issued'})`);
const refused = await crew.storage.from('org-files').createSignedUploadUrl(path('crew'));
const rlsWords = /row-level security|unauthori[sz]ed|not allowed|403/i;
say(!!refused.error && rlsWords.test(String(refused.error.message) + String(refused.error.statusCode ?? '')),
  `check 1: crew is refused a signed upload url (${refused.error ? refused.error.message : 'ISSUED — the policy was not consulted'})`);

// CHECK 2 ─────────────────────────────────────────────────────────────────────
let written = null;
if (issued.data?.token) {
  const other = path('elsewhere');
  const moved = await client().storage.from('org-files').uploadToSignedUrl(other, issued.data.token, new Blob(['moved']), { contentType: 'text/plain' });
  say(!!moved.error, `check 2: the token is refused at a different path (${moved.error ? moved.error.message : 'ACCEPTED — the url is not bound to its path'})`);
  if (!moved.error) written = other;
  const own = await client().storage.from('org-files').uploadToSignedUrl(path('office'), issued.data.token, new Blob(['proof']), { contentType: 'text/plain' });
  say(!own.error, `control: the token works at its own path (${own.error ? own.error.message : 'uploaded'})`);
  if (!own.error) {
    const { data: removed, error } = await office.storage.from('org-files').remove([path('office'), ...(written ? [written] : [])]);
    const { data: left } = await office.storage.from('org-files').list(`${ORG}/office-uploads/${WO}`, { search: nonce });
    console.log(`cleanup: removed ${removed?.length ?? 0} object(s)${error ? ` (error ${error.message})` : ''}; left with this run's nonce: ${left?.length ?? 'unknown'}`);
  }
} else {
  say(false, 'check 2: not run — no url was issued to the control');
}

stop(verdicts.every(Boolean) ? 0 : 1, verdicts.every(Boolean) ? 'PROVED' : 'NOT PROVED', `${verdicts.filter(Boolean).length} of ${verdicts.length} checks passed`);
