#!/usr/bin/env node
// StructTech OS — schedule-drift check.  Track X, X-W1.3, 2026-09-04.
//
// WHY THIS EXISTS.  On 2026-09-04 the monitor's cron read `*/15 * * * *` and
// the platform delivered 6 runs in 19.01 hours — 7.9% of the 76 that interval
// asks for, mean gap 228 minutes, max gap 310 minutes.  Every run was green.
// Nothing anywhere compared the rate we ASKED for to the rate we GOT, so a
// config file asserting fifteen-minute coverage sat on top of three-and-a-half
// hour coverage and read as healthy for a day.
//
// That is the same shape as every other finding on this project: the control
// was an absence.  "The monitor is green" was doing the work of "the doors are
// watched every 15 minutes", and no instrument connected the two.
//
// WHAT THIS CHECK CAN AND CANNOT DO — read this before trusting it.
//   IT CATCHES DEGRADATION.  It runs inside a scheduled run, reads this
//   workflow's own recent `schedule` runs, and goes red when the gap since the
//   previous one exceeds the threshold.  Red emails the repo owner.
//   IT CANNOT CATCH DEATH.  If the schedule stops entirely, no run happens, so
//   this never executes and says nothing.  Silence remains silence.  Closing
//   that needs an external dead-man's switch on a third-party account — see
//   the report for X-W1.3 and track-x/ACCOUNT_INVENTORY.  DO NOT read a run of
//   green drift checks as evidence the schedule cannot stop.
//
// It classifies like the front-door monitor does, and for the same reason:
//   exit 0  the observed gap is within threshold
//   exit 1  the gap exceeded threshold — the schedule is under-delivering
//   exit 2  UNDETERMINED — could not read the run history.  A GitHub API
//           hiccup is not a schedule failure and must never be reported as one.

const REPO = process.env.GITHUB_REPOSITORY;
const TOKEN = process.env.GITHUB_TOKEN;
const RUN_ID = process.env.GITHUB_RUN_ID;
const EVENT = process.env.GITHUB_EVENT_NAME;
const API = process.env.GITHUB_API_URL || "https://api.github.com";

// The interval the workflow ASKS for, and the gap at which we call the
// delivered rate broken.  Kept as env so the cron and the threshold are
// changed together in one file rather than drifting apart.
const NOMINAL_MINUTES = Number(process.env.SCHEDULE_NOMINAL_MINUTES || "60");
const THRESHOLD_MINUTES = Number(process.env.SCHEDULE_MAX_GAP_MINUTES || "360");

const OK = 0, BROKEN = 1, UNDETERMINED = 2;

function say(line) { console.log(line); }
function undetermined(why) {
  say(`UNDETERMINED: ${why}`);
  say("This is NOT a claim that the schedule is broken. It is a claim that this check could not tell.");
  process.exit(UNDETERMINED);
}

if (EVENT !== "schedule") {
  say(`event is '${EVENT}', not 'schedule' — nothing to measure. Skipping.`);
  process.exit(OK);
}
if (!REPO || !TOKEN) {
  undetermined("GITHUB_REPOSITORY or GITHUB_TOKEN absent");
}

let runs;
try {
  const res = await fetch(
    `${API}/repos/${REPO}/actions/workflows/frontdoor-monitor.yml/runs?event=schedule&per_page=20`,
    {
      headers: {
        Authorization: `Bearer ${TOKEN}`,
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
      },
      signal: AbortSignal.timeout(20_000),
    }
  );
  if (!res.ok) undetermined(`GitHub API returned HTTP ${res.status}`);
  runs = (await res.json()).workflow_runs ?? [];
} catch (e) {
  undetermined(`could not reach the GitHub API: ${e.message}`);
}

// Order newest-first and drop the run we are currently inside; the gap we
// want is between THIS run and the one before it.
runs.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
const prior = runs.filter((r) => String(r.id) !== String(RUN_ID));

if (prior.length === 0) {
  say("no earlier scheduled run to measure against — first scheduled run, or history pruned.");
  process.exit(OK);
}

const now = Date.now();
const previous = new Date(prior[0].created_at).getTime();
const gapMin = (now - previous) / 60000;

// The trailing picture, so the number accumulates in the logs run over run
// even on the runs that do not trip. A single gap is an anecdote.
const sample = prior.slice(0, 10).map((r) => new Date(r.created_at).getTime());
const gaps = [];
for (let i = 0; i < sample.length - 1; i++) gaps.push((sample[i] - sample[i + 1]) / 60000);
const mean = gaps.length ? gaps.reduce((a, b) => a + b, 0) / gaps.length : gapMin;
const worst = gaps.length ? Math.max(...gaps, gapMin) : gapMin;

say("------------------------------------------------------------------------");
say(`asked for      : every ${NOMINAL_MINUTES} min   (cron in frontdoor-monitor.yml)`);
say(`gap to previous: ${gapMin.toFixed(1)} min`);
say(`trailing mean  : ${mean.toFixed(1)} min over ${gaps.length} gap(s)`);
say(`trailing worst : ${worst.toFixed(1)} min`);
say(`delivery       : ${((NOMINAL_MINUTES / Math.max(mean, 0.001)) * 100).toFixed(1)}% of the configured rate`);
say(`threshold      : ${THRESHOLD_MINUTES} min`);
say("------------------------------------------------------------------------");

if (gapMin > THRESHOLD_MINUTES) {
  say(`SCHEDULE UNDER-DELIVERING: ${gapMin.toFixed(1)} min since the previous scheduled run, threshold ${THRESHOLD_MINUTES}.`);
  say("The doors were unwatched for that whole gap. Green monitor runs do not cover it.");
  process.exit(BROKEN);
}

say(`OK: ${gapMin.toFixed(1)} min gap is within the ${THRESHOLD_MINUTES} min threshold.`);
process.exit(OK);
