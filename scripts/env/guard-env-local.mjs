#!/usr/bin/env node
// .env.local survives a bare `vercel env pull`.  Track X, 2026-10-06.
//
// THE HAZARD, MEASURED ON 2026-10-06 BY RUNNING THE REAL COMMAND — and it is NOT
// what I reported yesterday. I claimed "one bare `vercel env pull` destroys
// .env.local". I had inferred that from a pull into a FRESH path. Running it
// against the real existing file says otherwise, and the difference is the whole
// design of this guard:
//
//   · INTO AN EXISTING .env.local, the pull MERGES. `SUPABASE_DB_URL`, which is
//     not stored in Vercel at all, SURVIVED. The three Sensitive keys kept their
//     REAL local values rather than being replaced by `[SENSITIVE]`. Nothing was
//     destroyed. My yesterday's claim was wrong and is corrected here rather than
//     left in a report nobody re-reads.
//
//   · INTO A FRESH OR ABSENT FILE, the pull writes the literal `[SENSITIVE]` for
//     every Sensitive variable and contains no `SUPABASE_DB_URL`. That is the
//     real destructive case, and it is the one a NEW CLONE hits — the machine
//     least likely to have anyone who knows what the file should contain.
//
//   · EITHER WAY it INJECTS ~21 Vercel and Turbo system variables, and one of
//     them is live: `VERCEL_ENV=production`. `src/app/api/health/route.ts` reads
//     `process.env.VERCEL_ENV ?? "local"`, so after a pull a LOCAL dev server
//     reports itself as `"env":"production"`. Measured, not reasoned: it happened
//     to this worktree today and was cleaned up.
//
// SO THE GUARD WATCHES FOR BOTH SHAPES, and does not pretend the merge case is
// the dangerous one.
//
// WHY NOT A WRAPPER SCRIPT. A wrapper (`npm run env:pull`) only helps whoever
// remembers to use it, and the failure mode is someone typing the documented
// upstream command from muscle memory or from Vercel's own docs. A guard that
// depends on memory is not a guard. This one assumes the pull WILL happen and
// makes it survivable: every healthy run takes a backup, every run checks for the
// damage, and it is wired to `predev` and `prebuild` so it runs on the commands
// everyone already types. Nobody has to know it exists.
//
// WHAT IT DOES NOT PROTECT AGAINST, written down because a guard whose limits are
// unstated gets trusted past them:
//   1. The FIRST pull on a machine that has never run dev or build — no backup
//      exists, so there is nothing to restore. It refuses loudly instead, which is
//      the best available outcome: a Sensitive value is write-only and cannot be
//      recovered from Vercel by anyone.
//   2. A pull followed by real edits before the next dev/build; a restore would
//      discard them, so the damaged file is copied aside, never deleted.
//   3. A pull that writes a DIFFERENT file this guard does not watch.
//   4. `.env.proof.local`, which is unwatched and holds its own credentials.
//   5. Anything outside a dev/build run — CI, or a bare `node script.mjs`.
// It narrows a footgun; it does not remove it.

import { readFileSync, writeFileSync, existsSync, copyFileSync } from 'node:fs';
import { SENSITIVE_PLACEHOLDER, envValue } from '../lib/sensitive.mjs';

const LIVE = '.env.local';
const BACKUP = '.env.backup.local';   // matches .gitignore's `.env*.local`
const SALVAGE = '.env.clobbered.local';

const keysOf = (text) =>
  text.split('\n').filter((l) => /^[A-Za-z_][A-Za-z0-9_]*=/.test(l))
      .map((l) => [l.slice(0, l.indexOf('=')), envValue(l, l.slice(0, l.indexOf('=')))]);

if (!existsSync(LIVE)) {
  console.log(`[env-guard] ${LIVE} is absent. Nothing to protect and nothing to restore.`);
  process.exit(0);
}

const live = readFileSync(LIVE, 'utf8');
const present = keysOf(live);
const placeholders = present.filter(([, v]) => v === SENSITIVE_PLACEHOLDER).map(([k]) => k);
// The injected set. VERCEL_ENV is the one that actually misleads something:
// /api/health reports it verbatim, so a local server starts calling itself production.
const INJECTED = /^(VERCEL|VERCEL_.*|TURBO_.*|NX_DAEMON)$/;
const injected = present.map(([k]) => k).filter((k) => INJECTED.test(k));

if (injected.length) {
  console.error(`\n[env-guard] ${LIVE} contains ${injected.length} Vercel/Turbo system variable(s) that a \`vercel env pull\` injects: ${injected.join(', ')}`);
  if (injected.includes('VERCEL_ENV')) {
    console.error(`[env-guard] VERCEL_ENV is among them, and /api/health reports it verbatim — a LOCAL dev server will describe itself as production until it is removed.`);
  }
  console.error(`[env-guard] Remove those lines from ${LIVE}. Your app variables are unaffected.\n`);
  process.exit(1);
}

if (placeholders.length === 0) {
  // Healthy. Refresh the backup so the newest good state is the one we can return to.
  copyFileSync(LIVE, BACKUP);
  process.exit(0);
}

// Damaged: the only way a local file acquires this literal is a `vercel env pull`.
console.error(`\n[env-guard] ${LIVE} HAS BEEN OVERWRITTEN BY \`vercel env pull\`.`);
console.error(`[env-guard] ${placeholders.length} variable(s) now hold the literal ${SENSITIVE_PLACEHOLDER}: ${placeholders.join(', ')}`);
console.error(`[env-guard] A pull also DROPS any variable that is not stored in Vercel — SUPABASE_DB_URL is not, so the pilot scripts would lose the database.`);

if (!existsSync(BACKUP)) {
  console.error(`[env-guard] NO BACKUP EXISTS (${BACKUP}), so nothing can be restored automatically.`);
  console.error(`[env-guard] Rebuild ${LIVE} by hand from ${'.env.local.example'}. The values are NOT recoverable from Vercel: a Sensitive variable is write-only.`);
  process.exit(1);
}

copyFileSync(LIVE, SALVAGE);      // never delete what we did not write
copyFileSync(BACKUP, LIVE);
console.error(`[env-guard] RESTORED ${LIVE} from ${BACKUP}. The pulled file was kept at ${SALVAGE} — delete it once you have looked.`);
console.error(`[env-guard] Re-run your command.\n`);
process.exit(1);
