#!/usr/bin/env node
// Is the dead-man's switch ARMED?  Track X, X-W1.12, 2026-09-13.
//
// "The secret exists" and "the switch fires" are different claims. A secret can be
// present and empty, mistyped, pointing at a deleted check, or never exercised
// because no scheduled run has happened since it was set. None of those shows up
// by looking at the secret. This script looks at the only evidence that the switch
// works end to end from our side: a SCHEDULED run of frontdoor-monitor.yml in which
// the ping step EXECUTED, SUCCEEDED, and printed its delivery line — which the step
// only reaches after `curl --fail` got a 2xx from the URL.
//
// THE TRAP THIS IS BUILT AROUND, found in production data before it was written.
// GitHub echoes every step's script into the job log. The log of scheduled run
// 34738966801 (2026-09-13, secret NOT set) contains the line
//     ESC[36;1m echo "dead-man's ping delivered." ESC[0m
// i.e. the script, not its output. A grep for "ping delivered" would have reported
// ARMED on a switch that has never fired. So the step's conclusion comes from the
// jobs API, and a log line counts only if it is OUTPUT — lines carrying the
// script-echo colour prefix (ESC[36;1m) are discarded before anything is matched.
//
// WHAT THIS CANNOT PROVE, stated so nobody reads ARMED as more than it is: that the
// receiving service will ALERT when pings stop. That needs the service's own
// account. The proof — after a real ping has landed — is to set Period and Grace to
// the smallest values the form allows, wait for the alert email, then restore
// Period 1 hour / Grace 7 hours (README-deadman.md). NOT Pause: Healthchecks
// documents pausing as the way to AVOID alerts. (Corrected 2026-09-16; this line
// still said "pause" after the README was fixed on 2026-09-14, and the instruction
// resurfaced in a report.)
//
// exit 0  ARMED        — a scheduled run delivered a ping and the URL answered 2xx
// exit 1  NOT ARMED    — the step ran and reported the secret absent, or curl was refused
// exit 2  UNDETERMINED — no scheduled run has exercised the step (since DEADMAN_ARMED_SINCE),
//                        or the GitHub API / logs could not be read
//
// Usage:  GITHUB_TOKEN=... node scripts/monitor/verify-deadman.mjs
//         DEADMAN_ARMED_SINCE=2026-09-13T15:00:00Z   only accept runs created at/after this
//         VERIFY_DEADMAN_FIXTURE=<dir>                grade recorded fixtures instead of the API

import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const REPO = process.env.GITHUB_REPOSITORY || 'jacobaw1995/structtech-os';
const WORKFLOW = 'frontdoor-monitor.yml';
const JOB = 'check the front doors';
const STEP_PREFIX = "dead-man's ping";
const SINCE = process.env.DEADMAN_ARMED_SINCE ? Date.parse(process.env.DEADMAN_ARMED_SINCE) : null;
const FIXTURE = process.env.VERIFY_DEADMAN_FIXTURE;
const LOOKBACK = 20;

const DELIVERED = "dead-man's ping delivered.";
const ABSENT = '##[notice]DEADMAN_PING_URL is not set';
const SCRIPT_ECHO = String.fromCharCode(27) + '[36;1m';

function done(code, verdict, detail) {
  console.log('------------------------------------------------------------------------');
  console.log(`${verdict}: ${detail}`);
  process.exit(code);
}

async function gh(path, raw = false) {
  const token = process.env.GITHUB_TOKEN;
  if (!token) done(2, 'UNDETERMINED', 'GITHUB_TOKEN is not set, so run history cannot be read. This says nothing about the switch.');
  let res;
  try {
    res = await fetch(`https://api.github.com/repos/${REPO}${path}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' },
      redirect: 'follow',
      signal: AbortSignal.timeout(30_000),
    });
  } catch (e) {
    done(2, 'UNDETERMINED', `GitHub API unreachable (${e.name}). This says nothing about the switch.`);
  }
  if (!res.ok) done(2, 'UNDETERMINED', `GitHub API ${path} returned HTTP ${res.status}. This says nothing about the switch.`);
  return raw ? res.text() : res.json();
}

const source = FIXTURE
  ? {
      runs: async () => JSON.parse(readFileSync(join(FIXTURE, 'runs.json'), 'utf8')),
      jobs: async (id) => JSON.parse(readFileSync(join(FIXTURE, `jobs-${id}.json`), 'utf8')).jobs,
      log: async (id) => readFileSync(join(FIXTURE, `log-${id}.txt`), 'utf8'),
    }
  : {
      runs: async () => (await gh(`/actions/workflows/${WORKFLOW}/runs?event=schedule&per_page=${LOOKBACK}`)).workflow_runs,
      jobs: async (id) => (await gh(`/actions/runs/${id}/jobs`)).jobs,
      log: async (id) => gh(`/actions/jobs/${id}/logs`, true),
    };

/** Output lines only: drop script echo, then strip the timestamp column. */
function outputLines(text) {
  return text
    .split('\n')
    .filter((l) => !l.includes(SCRIPT_ECHO))
    .map((l) => l.replace(/^\d{4}-\d{2}-\d{2}T[\d:.]+Z\s?/, '').trimEnd());
}

const runs = (await source.runs())
  .filter((r) => SINCE === null || Date.parse(r.created_at) >= SINCE)
  .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at));

console.log(`repo ${REPO} · scheduled runs considered: ${runs.length}${SINCE ? ` (created since ${new Date(SINCE).toISOString()})` : ''}`);

for (const run of runs) {
  const job = (await source.jobs(run.id)).find((j) => j.name === JOB);
  const step = job?.steps?.find((s) => s.name.startsWith(STEP_PREFIX));
  if (!step) { console.log(`  run ${run.id} ${run.created_at}: no ping step in this run — not an exercise`); continue; }
  if (step.conclusion === 'skipped') { console.log(`  run ${run.id} ${run.created_at}: ping step SKIPPED (the run was not green) — not an exercise`); continue; }

  const lines = outputLines(await source.log(job.id));
  const delivered = lines.includes(DELIVERED);
  const absent = lines.some((l) => l.startsWith(ABSENT));
  console.log(`  run ${run.id} ${run.created_at} sha=${String(run.head_sha).slice(0, 7)}: step=${step.conclusion} delivered=${delivered} secretAbsent=${absent}`);

  if (step.conclusion === 'failure') {
    done(1, 'NOT ARMED', `run ${run.id}: the ping step ran and FAILED — curl --fail was refused. The URL is wrong, or the check it names no longer exists.`);
  }
  if (step.conclusion === 'success' && absent) {
    done(1, 'NOT ARMED', `run ${run.id}: the ping step ran and reported DEADMAN_PING_URL is not set.`);
  }
  if (step.conclusion === 'success' && delivered) {
    done(0, 'ARMED', `run ${run.id} (${run.created_at}) delivered a ping and the receiving URL answered 2xx. This proves DELIVERY, not ALERTING. To prove alerting: set Period and Grace to the smallest values the form allows, wait for the alert email, then restore Period 1 hour / Grace 7 hours. Do not use Pause — it suppresses alerts.`);
  }
  done(2, 'UNDETERMINED', `run ${run.id}: the ping step reported ${step.conclusion} with neither a delivery line nor the not-set notice in its output. The step or its log has changed shape; do not trust either verdict until this script is updated.`);
}
done(2, 'UNDETERMINED', `no scheduled run${SINCE ? ' since the stated time' : ''} has exercised the ping step. Scheduled runs are ~3.7 h apart on average; wait for one. A manual "Run workflow" does not count — the step only fires on schedule.`);
