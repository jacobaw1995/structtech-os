#!/usr/bin/env node
// Browser-auth tripwire.  Track X, X-W1.11, 2026-09-12.
//
// WHAT IT GUARDS. `src/lib/supabase/client.ts` builds a browser Supabase client
// with NO bound on its session refresh. Today that is harmless for one reason
// only: nothing imports it. Measured 2026-09-12 three independent ways —
//   · no import of it anywhere in src/, static, dynamic or relative;
//   · no gotrue code in any of the 38 files a browser can download
//     (positive control: temporarily importing it made the same scan find
//     `_callRefreshToken`, `SIGNED_OUT` and the project ref), with 5 of 6
//     deployed assets byte-identical to that build;
//   · a real browser loading four pages with an expired session made ZERO
//     requests to Supabase (positive control: a deliberate fetch to the same
//     host did appear in the same network log).
//
// That is CLOSED BY ACCIDENT (CLAUDE.md rule 13). The single change that would
// reopen it is "somebody imports the browser client", which is an absence
// standing in for a control: no owner, no review, no alarm. This script is the
// alarm.
//
// WHY IT IS NOT JUST "NEVER IMPORT IT". The client exists to be used one day.
// So the check fails on the reopening event and clears when the right thing
// has been done: it passes if the browser client is imported AND bounded.
//
// WHAT "BOUNDED" MUST MEAN THERE, and why the server's work does not transfer:
//   1. THE NUMBER. The server bound (2500 ms) came from `origin_time` in the
//      edge log — Supabase's own service time, Vercel to Supabase in the same
//      region. A browser refresh adds the device's own round trip, and for a
//      crew on cellular that is the dominant term. `origin_time` does not
//      contain it, so the edge log cannot derive the browser number at all.
//      It needs client-side timing from real devices. Reusing 2500 would be a
//      habit, not a bound.
//   2. THE SIGNAL. Browser code is where auth-state subscribers live. A bound
//      that reports a stall as a terminal auth error makes gotrue emit
//      SIGNED_OUT — measured identical to a real revocation — straight into
//      the code that tells a user "your session expired". The server fix keeps
//      the timeout retryable for exactly this reason; the browser must too.
//   3. THE LIFECYCLE. The browser client refreshes on a timer, not per
//      request, so "race the call and discard the client" does not map onto it.
//
// exit 0  the browser client is unused, or used and bounded
// exit 1  the browser client is imported and NOT bounded — the gap reopened
// exit 2  UNDETERMINED — could not read the source tree

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const ROOT = process.argv[2] || process.cwd();
const SRC = join(ROOT, 'src');
const CLIENT = join(SRC, 'lib', 'supabase', 'client.ts');

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    if (name === 'node_modules' || name.startsWith('.')) continue;
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) walk(p, out);
    else if (/\.(tsx?|jsx?|mjs|cjs)$/.test(name)) out.push(p);
  }
  return out;
}

let files, clientSrc;
try {
  files = walk(SRC);
  clientSrc = readFileSync(CLIENT, 'utf8');
} catch (e) {
  console.log(`UNDETERMINED: could not read the source tree (${e.message}). This is not a claim that the gap is open.`);
  process.exit(2);
}

// Matches `@/lib/supabase/client` and relative forms ending in `supabase/client`
// or `./client` from inside lib/supabase — and deliberately NOT `client-info`.
const IMPORT = /(?:from\s*|import\s*\(\s*)['"]((?:@\/lib\/supabase|(?:\.\.?\/)+(?:lib\/)?supabase|\.)\/client)['"]/g;

const importers = [];
for (const f of files) {
  if (f === CLIENT) continue;
  const text = readFileSync(f, 'utf8');
  for (const m of text.matchAll(IMPORT)) {
    const spec = m[1];
    // `./client` only means the browser client when written from lib/supabase.
    if (spec === './client' && !f.startsWith(join(SRC, 'lib', 'supabase'))) continue;
    importers.push(`${relative(ROOT, f)}  (${spec})`);
  }
}

// Comments are stripped before matching. The first version of this check passed
// on a file whose only mention of a bound was `// uses boundGetSession(client)`
// — a comment could have silenced the alarm. It detects bounding CODE, and it
// still cannot tell whether that code's number was measured; the exit message
// asks for that, because a script cannot.
const codeOnly = clientSrc.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
const bounded = /boundGetSession|createBoundedFetch|AbortSignal\.timeout/.test(codeOnly);

console.log('------------------------------------------------------------------------');
console.log(`browser client importers : ${importers.length}`);
for (const i of importers) console.log(`  ${i}`);
console.log(`browser client bounded   : ${bounded}`);
console.log('------------------------------------------------------------------------');

if (importers.length === 0) {
  console.log('OK: the browser Supabase client is unused, so no browser session refresh can stall.');
  process.exit(0);
}
if (bounded) {
  console.log('OK: the browser client is in use and carries a bound. Confirm the number was derived from client-side timing, not copied from the server.');
  process.exit(0);
}
console.log('GAP REOPENED: the browser Supabase client is imported and has NO bound on its session refresh.');
console.log('A stalled refresh in the browser now has no limit. Before bounding it, read the header of');
console.log('scripts/monitor/browser-auth-tripwire.mjs: the server number does not transfer, and a bound');
console.log('that reports a stall as a terminal auth error will emit a false SIGNED_OUT.');
process.exit(1);
