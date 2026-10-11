#!/usr/bin/env node
// The scheduled-run gap distribution, with its WINDOW attached to every number.
// Track X, 2026-10-11.
//
//   node scripts/pilot/cron-drift-figures.mjs [--since YYYY-MM-DD]
//
// WHY THIS EXISTS, AND IT IS NOT CONVENIENCE. "38 minutes of margin" was written
// into READINESS_LOG on 2026-09-30, quoted in six controller directives, and was
// FALSE OF THE INSTRUMENT the whole time. It was true of the window it was
// measured on (2026-09-30 → 10-08) and of nothing else: over the full history the
// worst gap is 21.71h against an 8h threshold, so the margin is NEGATIVE by
// almost fourteen hours.
//
// CONTROLLER RULING, 2026-10-11: A MARGIN MEASURED ON A CHOSEN WINDOW IS A FACT
// ABOUT THE WINDOW. The failure was not arithmetic — every figure was correctly
// computed. It was that a number travelled without its container, and the next
// reader could not tell a property of the monitor from a property of eight days
// in September. Same family as rule 39: the caveat does not travel with the
// number, so the container has to be IN the number.
//
// So this prints the window on the same line as every percentile, and refuses to
// emit a bare figure. Paste its output into READINESS_LOG rather than hand-typing
// a median — a hand-typed median is how the 38 minutes got in.
//
// WHERE IT LIVES, AND WHY NOT scripts/monitor/. That directory is asserted by the
// front-door workflow to need NO external binary, and this shells out to `gh`.
// Putting a psql-dependent script there on 2026-10-09 broke the monitor for four
// consecutive runs. The guard was right; the file was in the wrong place. Same
// reasoning, applied before making the mistake twice.
//
// WHAT IT CANNOT SEE: runs GitHub never started (they leave no row to measure, and
// the gap they create is attributed to the surrounding successes); the Healthchecks
// side of the story, which needs an API key this repo does not hold; and whether an
// alert that should have fired was READ by anyone.

import { execFileSync } from 'node:child_process';

const args = process.argv.slice(2);
const since = args.includes('--since') ? args[args.indexOf('--since') + 1] : null;
const PERIOD_H = 1, GRACE_H = 7, THRESHOLD_H = PERIOD_H + GRACE_H;

const raw = execFileSync('gh', ['run', 'list', '--workflow=frontdoor-monitor.yml', '--limit', '400',
  '--json', 'conclusion,event,createdAt'], { encoding: 'utf8' });
let runs = JSON.parse(raw).filter((r) => r.event === 'schedule');
if (since) runs = runs.filter((r) => r.createdAt >= since);
const ok = runs.filter((r) => r.conclusion === 'success').map((r) => new Date(r.createdAt)).sort((a, b) => a - b);

if (ok.length < 2) { console.log(`UNDETERMINED: ${ok.length} successful scheduled run(s) in range — too few to form a gap.`); process.exit(2); }

const gaps = ok.slice(1).map((d, i) => (d - ok[i]) / 3600000).sort((a, b) => a - b);
const pct = (p) => gaps[Math.min(gaps.length - 1, Math.round((p / 100) * (gaps.length - 1)))];
const med = gaps.length % 2 ? gaps[(gaps.length - 1) / 2] : (gaps[gaps.length / 2 - 1] + gaps[gaps.length / 2]) / 2;
const d = (x) => x.toISOString().slice(0, 10);
const WIN = `${d(ok[0])}→${d(ok[ok.length - 1])}, n=${gaps.length} gaps`;

// EVERY LINE CARRIES THE WINDOW. Not a header the reader may not copy — the window
// is in the same sentence as the figure, so a quoted line is still true.
console.log(`WINDOW ${WIN}  (${ok.length} successful scheduled runs of ${runs.length})`);
for (const [label, v] of [['median', med], ['p90', pct(90)], ['p99', pct(99)], ['MAX', gaps[gaps.length - 1]]]) {
  console.log(`  ${label.padEnd(7)} ${v.toFixed(2)}h   over ${WIN}`);
}
const worst = gaps[gaps.length - 1];
console.log(`  margin at the MAX vs the ${THRESHOLD_H}h threshold: ${((THRESHOLD_H - worst) * 60).toFixed(0)} minutes   over ${WIN}`);
const over = ok.slice(1).map((b, i) => [ok[i], b, (b - ok[i]) / 3600000]).filter(([, , h]) => h > THRESHOLD_H);
console.log(`  alert windows (gap > ${THRESHOLD_H}h): ${over.length}   over ${WIN}`);
for (const [a, b, h] of over) console.log(`     ${h.toFixed(1)}h  ${a.toISOString().slice(0, 16)}Z -> ${b.toISOString().slice(0, 16)}Z`);
// An OPEN window is not in the closed set above and is the one that matters now.
const sinceLast = (Date.now() - ok[ok.length - 1]) / 3600000;
console.log(`  hours since the last success: ${sinceLast.toFixed(1)}h` +
  (sinceLast > THRESHOLD_H ? `  *** AN ALERT WINDOW IS OPEN NOW and is not counted above — a closed gap needs a later success to measure against ***` : '  (no open window)'));
