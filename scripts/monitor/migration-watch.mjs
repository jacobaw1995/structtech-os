#!/usr/bin/env node
// A new row in supabase_migrations.schema_migrations, from EITHER party, found
// without either party sending anything.  Track X, 2026-10-08.
//
//   node scripts/monitor/migration-watch.mjs [--hours N] [--since YYYYMMDDHHMMSS]
//
// WHY THIS EXISTS. On 2026-10-07 a migration applied during a freeze and we
// learned 34 hours later, from a message. Material Matrix described their own
// half exactly: "the notification was the entire control, and I placed it outside
// the path." Our schema track did the same thing the same night with the runbook's
// Rule One. BOTH NOTIFICATIONS WERE NOTES AND NEITHER WAS A STEP. A control that
// depends on the party who broke the rule choosing to mention it is not a control.
// This one reads the ledger, so it does not need anybody to send anything.
//
// ── WHAT I VERIFIED RATHER THAN ACCEPTED ───────────────────────────────────
// THE VERSION IS THE ONLY TIME SIGNAL THERE IS. The ledger's columns are
// version, statements, name, created_by, idempotency_key, rollback — measured,
// 2026-10-08. THERE IS NO applied_at. So the claim "the version IS the apply
// timestamp" is load-bearing, and taking it from Material Matrix or from the
// directive would have made this monitor rest on somebody's say-so.
//
// Tested independently: for every migration file with a parseable version and a
// git add, compare the stamp against the file's FIRST commit. n = 77.
//   · committed BEFORE its stamp:  0
//   · median git-minus-version:    +8.2 min
//   · within 60 min:               76 of 77   (the outlier is baseline.sql, +249)
// A stamp is never later than the file, and is minutes earlier. That is what you
// see when the stamp is generated at apply and the file is written to match.
//
// THE LIMIT, STATED BECAUSE IT DOES NOT CHANGE THE ANSWER AND WOULD OTHERWISE
// LOOK LIKE A GAP I MISSED: this evidence cannot separate "stamped at apply"
// from "stamped at creation and applied immediately". Under BOTH stories the
// stamp lands within minutes of the apply, which is the only property this
// monitor needs. I am not claiming the stronger version of the fact.
//
// FILENAMES ARE UTC BY PROJECT CONVENTION — ordering keys, not day labels. Every
// line below prints UTC and America/New_York, because 20261008180116 is "Oct 8"
// in one and can be the previous day in the other, and CLAUDE.md records that
// exact mistake costing a day twice.
//
// ── WHOSE ROW IS IT ────────────────────────────────────────────────────────
// `created_by` LOOKS like the answer and is NOT: 258 of 267 rows carry the same
// address, Material Matrix's wh_ rows included, because both tracks apply under
// one account. Measured, not assumed.
//
// So attribution is three-state, and the third state is the honest one:
//   OURS         a file with this version exists in supabase/migrations/
//                (or _archive_pre_baseline/ for the squashed history)
//   THEIRS       the name begins wh_ and no file of ours matches
//   UNATTRIBUTED neither — reported as unattributed, never guessed
// A MONITOR THAT GUESSES "THEIRS" ON AN UNKNOWN ROW BECOMES AN ALARM ABOUT THEM;
// one that guesses "ours" becomes an alarm about us. Both get ignored.
// Sized today: 76 ours, 10 archived, 108 theirs, 73 unattributed of 267 — and
// every unattributed row is older than 2026-09-06, so the class is historical.
// Nothing applied in the last month is ambiguous.
//
// ── WHAT THIS DOES NOT CATCH, and the first one is the big one ─────────────
// 1. DELIVERY. This tells the truth the moment it RUNS. It does not run itself.
//    Hung off the existing GitHub Actions cron it inherits that cron's measured
//    delivery — median 5.61 h, p90 6.96 h, worst 7.37 h (READINESS_LOG, verified
//    2026-10-08), which is 38 minutes of margin against the 8 h Healthchecks
//    threshold. SO ON THAT CRON "the same hour" IS NOT AVAILABLE: the honest
//    figure is the same five-to-six hours, and the 34 hours becomes ~6, not ~1.
//    One hour needs a scheduler that runs when it says it does. That is the same
//    recommendation made on 2026-09-30 for the dead-man ping and it is Jacob's.
// 2. A schema change with NO LEDGER ROW — the Supabase Table Editor or the SQL
//    editor (CLAUDE.md rule 14). This watches the ledger, so it is blind to any
//    change that never writes one.
// 3. A row applied and then DELETED from the ledger before the next run.
// 4. WHAT the migration did. It reports that one appeared, never whether it was
//    safe. Reading it is a human's job and this does not pretend otherwise.
// 5. It cannot attribute a row that is neither filed nor wh_ — it says so.
//
// ── OUTPUT DISCIPLINE ──────────────────────────────────────────────────────
// The front-door workflow writes `::error::` lines from inside its own self-test,
// so on a one-hour log budget an error there can be the probe rather than the
// product. This writes NO error-level line on a quiet run — a quiet run prints
// one ordinary line and exits 0. An error line from this script means a row
// appeared, and it always names the version, so a reader never has to work out
// whether they are looking at an alarm or at a monitor testing itself.

import { execFileSync } from 'node:child_process';
import { readdirSync, existsSync } from 'node:fs';
import { q, dbAvailable } from '../pilot/db.mjs';

const args = process.argv.slice(2);
const hours = args.includes('--hours') ? Number(args[args.indexOf('--hours') + 1]) : 1;
const sinceArg = args.includes('--since') ? args[args.indexOf('--since') + 1] : null;

/** A 14-digit UTC stamp to a Date. Returns null rather than guessing. */
export function versionToUtc(v) {
  if (!/^\d{14}$/.test(v)) return null;
  const [y, mo, d, h, mi, s] = [v.slice(0, 4), v.slice(4, 6), v.slice(6, 8), v.slice(8, 10), v.slice(10, 12), v.slice(12, 14)].map(Number);
  const t = Date.UTC(y, mo - 1, d, h, mi, s);
  return Number.isNaN(t) ? null : new Date(t);
}

const fmt = (dt) => ({
  utc: dt.toISOString().replace('T', ' ').slice(0, 19) + ' UTC',
  ny: new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false }).format(dt).replace(',', '') + ' America/New_York',
});

function repoVersions() {
  const grab = (dir) => (existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith('.sql')).map((f) => f.split('_')[0]) : []);
  return { live: new Set(grab('supabase/migrations')), archived: new Set(grab('supabase/migrations/_archive_pre_baseline')) };
}

export function attribute(version, name, repo) {
  if (repo.live.has(version)) return { who: 'OURS', why: 'a file with this version is in supabase/migrations/' };
  if (repo.archived.has(version)) return { who: 'OURS', why: 'a file with this version is in _archive_pre_baseline/' };
  if (/^wh_/.test(name || '')) return { who: 'THEIRS', why: 'name begins wh_ and no file of ours matches' };
  return { who: 'UNATTRIBUTED', why: 'no file of ours, and the name does not begin wh_ — NOT guessed' };
}

if (!dbAvailable()) {
  console.log('UNDETERMINED: SUPABASE_DB_URL not available. Nothing was read, and that is not "no migrations".');
  process.exit(2);
}

const cutoff = sinceArg || (() => {
  const d = new Date(Date.now() - hours * 3600 * 1000);
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getUTCFullYear()}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}${p(d.getUTCHours())}${p(d.getUTCMinutes())}${p(d.getUTCSeconds())}`;
})();

const total = q('select count(*) from supabase_migrations.schema_migrations').trim();
const raw = q(`select version || chr(9) || coalesce(name, '') from supabase_migrations.schema_migrations where version >= '${cutoff}' order by version`).trim();
const rows = raw ? raw.split('\n').map((l) => l.trim().split('\t')) : [];
const repo = repoVersions();
const cutUtc = versionToUtc(cutoff);

// THE SIZE OF WHAT WAS EXAMINED, BESIDE THE RESULT (rule 24). A zero next to
// "0 rows examined" refutes itself; a zero out of 267 does not.
console.log(`migration-watch · ledger holds ${total} rows · window = versions >= ${cutoff}` +
  (cutUtc ? ` (${fmt(cutUtc).utc} / ${fmt(cutUtc).ny})` : ''));

if (rows.length === 0) {
  console.log(`QUIET: 0 new migration rows in the last ${sinceArg ? `window since ${cutoff}` : `${hours} hour(s)`}, of ${total} examined.`);
  process.exit(0);
}

for (const [version, name] of rows) {
  const dt = versionToUtc(version);
  const when = dt ? `${fmt(dt).utc}  |  ${fmt(dt).ny}` : 'version is not a 14-digit stamp — cannot convert';
  const a = attribute(version, name, repo);
  console.log(`::error::MIGRATION APPLIED — ${version} "${name}" [${a.who}] ${when}`);
  console.log(`    attribution: ${a.why}`);
}
console.log(`\n${rows.length} new migration row(s). This reports that they appeared, never whether they were safe — read them.`);
process.exit(1);
