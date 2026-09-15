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
// exit 0  no browser-capable Supabase client path, or every one is bounded
// exit 1  at least one unbounded browser-capable client path — the gap reopened
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
// ── WHAT IS WATCHED (second version, 2026-09-13) ─────────────────────────────
// The first version watched ONE thing: imports of src/lib/supabase/client.ts.
// Measured on 2026-09-13, three changes that put an unbounded Supabase auth
// client into the browser WITHOUT importing that file all passed it, each with
// the message "OK: the browser Supabase client is unused":
//   (b) a new `createBrowserClient<T>(...)` in a client component
//   (c) `createClient()` from @supabase/supabase-js in a client component
//   (d) `createBrowserClient(...)` in a helper that a client component imports
// A confident message for the wrong cause. The check watched a file's import
// graph instead of the property, which is "a browser-capable Supabase client
// exists outside the one place its bound decision is recorded". It now watches
// the property, and the OK line states what was counted rather than asserting
// "unused".
//
// Three ways in, each graded the same way (FAIL unless the file that constructs
// the client also carries bounding code):
//   1. an import of src/lib/supabase/client.ts (alias, relative or dynamic);
//   2. a `createBrowserClient(` construction ANYWHERE but client.ts — it has no
//      server use, so there is no legitimate place for a second one;
//   3. a runtime import of `createClient` from @supabase/supabase-js. CLAUDE.md
//      mandatory pattern 2 routes every server context through
//      @/lib/supabase/server, so a direct supabase-js client is not another
//      track doing its job correctly — it is exactly the path this watches.
// Type-only imports (`import type ... from "@supabase/..."`) are erased at compile
// and ship zero bytes, so they are ignored.

const IMPORT = /(?:from\s*|import\s*\(\s*)['"]((?:@\/lib\/supabase|(?:\.\.?\/)+(?:lib\/)?supabase|\.)\/client)['"]/g;
const BROWSER_CONSTRUCT = /createBrowserClient\s*(?:<[^>]*>)?\s*\(/;
const SUPABASE_JS_RUNTIME = /^\s*import\s+(?!type\b)[^;]*\bcreateClient\b[^;]*from\s*['"]@supabase\/supabase-js['"]/m;

// Comments are stripped before any matching. An earlier version passed on a file
// whose only mention of a bound was `// uses boundGetSession(client)`.
const stripComments = (t) => t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
const hasBound = (t) => /boundGetSession|createBoundedFetch|AbortSignal\.timeout/.test(t);

const findings = [];
for (const f of files) {
  const code = stripComments(readFileSync(f, 'utf8'));
  const rel = relative(ROOT, f);
  if (f !== CLIENT) {
    for (const m of code.matchAll(IMPORT)) {
      const spec = m[1];
      // `./client` only means the browser client when written from lib/supabase.
      if (spec === './client' && !f.startsWith(join(SRC, 'lib', 'supabase'))) continue;
      findings.push({ kind: 'imports client.ts', where: `${rel}  (${spec})`, bounded: hasBound(stripComments(clientSrc)) });
    }
    if (BROWSER_CONSTRUCT.test(code)) findings.push({ kind: 'new createBrowserClient', where: rel, bounded: hasBound(code) });
  }
  if (SUPABASE_JS_RUNTIME.test(code)) findings.push({ kind: 'supabase-js createClient', where: rel, bounded: hasBound(code) });
}

const open = findings.filter((x) => !x.bounded);
console.log('------------------------------------------------------------------------');
console.log(`source files scanned          : ${files.length}`);
console.log(`browser-capable client paths  : ${findings.length}`);
for (const x of findings) console.log(`  [${x.bounded ? 'bounded' : 'UNBOUNDED'}] ${x.kind} — ${x.where}`);
console.log('------------------------------------------------------------------------');

if (findings.length === 0) {
  console.log(`OK: 0 browser-capable Supabase client paths in ${files.length} source files — no import of client.ts, no createBrowserClient outside it, no runtime supabase-js createClient.`);
  process.exit(0);
}
if (open.length === 0) {
  console.log('OK: every browser-capable client path carries bounding code. Confirm each number was derived from client-side timing, not copied from the server.');
  process.exit(0);
}
console.log(`GAP REOPENED: ${open.length} unbounded browser-capable Supabase client path(s).`);
console.log('A stalled refresh in the browser now has no limit. Before bounding it, read the header of');
console.log('scripts/monitor/browser-auth-tripwire.mjs: the server number does not transfer, and a bound');
console.log('that reports a stall as a terminal auth error will emit a false SIGNED_OUT.');
process.exit(1);
