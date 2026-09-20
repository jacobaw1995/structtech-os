#!/usr/bin/env node
// Is field ready for a crew on a roof?  Track X, X-W1.18, 2026-09-16. Pilot: 2026-10-07.
//
//   node scripts/pilot/pilot-readiness.mjs            (reads scripts/pilot/pilot.config.json)
//
// Read-only. Writes nothing anywhere: every database statement runs in BEGIN READ ONLY
// and is rolled back; the production calls are GETs.
//
// THE PASS CONDITION MAY NOT DEPEND ON ANYTHING ANOTHER TRACK CAN LEGITIMATELY CHANGE.
// So nothing here names a role, a policy, a helper function or a column another track
// owns as the thing that must be true. The crew are named by Jacob as user ids in the
// config. Every crew check is asked AS THAT USER, through whatever RLS is live that
// day, and asserts what the person can reach — "sees a trade work order", "sees no
// estimate", "can open a file from the office". If Track S re-implements the crew gate
// tomorrow, these checks still ask the same question and still mean the same thing.
//
// Each check reports PASS, FAIL or UNDETERMINED, with the fact it rests on. A check
// that cannot run is UNDETERMINED, never PASS: a readiness report that reads green
// because it could not look is the empty-instrument problem again.
//
// exit 0 READY (every check PASS) · 1 NOT READY (any FAIL) · 2 UNDETERMINED (no FAIL,
// but at least one check could not be answered)

import { readFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { q, dbAvailable } from './db.mjs';

const CFG_PATH = process.env.PILOT_CONFIG || new URL('./pilot.config.json', import.meta.url); // PILOT_CONFIG: controls only
const cfg = existsSync(CFG_PATH)
  ? JSON.parse(readFileSync(CFG_PATH, 'utf8'))
  : { ...JSON.parse(readFileSync(new URL('./pilot.config.example.json', import.meta.url), 'utf8')), _fromExample: true };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ORG = cfg.pilotOrgId;
if (!UUID.test(ORG)) { console.log('pilotOrgId is not a uuid'); process.exit(2); }

const results = [];
const record = (id, verdict, what, fact) => results.push({ id, verdict, what, fact });
const n = (s) => Number.parseInt(s, 10);

// ── R1 production answers, and says what it is running ──────────────────────
try {
  const res = await fetch(`${cfg.productionUrl}/api/health`, { signal: AbortSignal.timeout(15000) });
  const body = await res.json().catch(() => ({}));
  if (res.ok && body.ok === true && typeof body.sha === 'string') record('R1', 'PASS', 'production answers', `sha ${body.sha.slice(0, 7)}`);
  else record('R1', 'FAIL', 'production answers', `HTTP ${res.status}`);
} catch (e) { record('R1', 'UNDETERMINED', 'production answers', `unreachable (${e.name})`); }

// ── R2 production configuration present, by NAME ────────────────────────────
// ORG_FILES_ENABLED is what turns the office roof-data section on (A4.7).
const REQUIRED_ENV = ['ORG_FILES_ENABLED', 'AUTH_EMAIL_ENABLED', 'RESEND_API_KEY', 'EMAIL_FROM'];
try {
  const out = execFileSync('vercel', ['env', 'ls', 'production', '--scope', cfg.vercelScope], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 60000 });
  const names = new Set(out.split('\n').map((l) => l.trim().split(/\s+/)[0]).filter((w) => /^[A-Z][A-Z0-9_]+$/.test(w)));
  if (names.size === 0) record('R2', 'UNDETERMINED', 'production env names', 'vercel env ls returned no names (is the CLI linked?)');
  else {
    const missing = REQUIRED_ENV.filter((k) => !names.has(k));
    record('R2', missing.length ? 'FAIL' : 'PASS', 'production env names', missing.length ? `missing: ${missing.join(', ')}` : `present: ${REQUIRED_ENV.join(', ')}`);
  }
} catch (e) { record('R2', 'UNDETERMINED', 'production env names', `vercel CLI unavailable (${e.code || e.name})`); }

// ── R3.. crew — named, and checked AS each person ───────────────────────────
const crew = Array.isArray(cfg.crewUserIds) ? cfg.crewUserIds.filter((id) => UUID.test(id)) : [];
if (!dbAvailable()) {
  record('R3', 'UNDETERMINED', 'pilot crew', 'SUPABASE_DB_URL not available');
} else if (crew.length === 0) {
  record('R3', 'FAIL', 'pilot crew named', cfg._fromExample
    ? 'no scripts/pilot/pilot.config.json — nobody is named as pilot crew'
    : 'crewUserIds is empty — nobody is named as pilot crew');
} else {
  record('R3', 'PASS', 'pilot crew named', `${crew.length} user id(s)`);
  for (const [i, id] of crew.entries()) {
    const who = `crew #${i + 1}`;
    try {
      const signedIn = q(`select coalesce((select case when last_sign_in_at is null then 'never' else 'yes' end from auth.users where id = '${id}'), 'no_account')`);
      record(`R4.${i + 1}`, signedIn === 'yes' ? 'PASS' : 'FAIL', `${who} has an account and has signed in`, signedIn === 'yes' ? 'signed in at least once' : signedIn === 'never' ? 'account exists, never signed in' : 'no auth account with this id');

      const trade = n(q(`select count(*) from public.work_orders where org_id = '${ORG}' and kind = 'trade' and voided_at is null`, { asUser: id }));
      record(`R5.${i + 1}`, trade > 0 ? 'PASS' : 'FAIL', `${who} sees a job to work on`, `${trade} live trade work order(s) visible to them`);

      const master = n(q(`select count(*) from public.work_orders where org_id = '${ORG}' and kind = 'master'`, { asUser: id }));
      record(`R6.${i + 1}`, master === 0 ? 'PASS' : 'FAIL', `${who} cannot reach a master work order`, `${master} visible`);

      const priced = n(q(`select count(*) from public.estimates where org_id = '${ORG}'`, { asUser: id }));
      record(`R7.${i + 1}`, priced === 0 ? 'PASS' : 'FAIL', `${who} sees no estimate (no $ in the field)`, `${priced} visible`);

      const files = n(q(`select count(*) from storage.objects where bucket_id = 'org-files' and name like '${ORG}/%'`, { asUser: id }));
      record(`R8.${i + 1}`, files > 0 ? 'PASS' : 'FAIL', `${who} can open roof data / photos from the office`, `${files} file(s) visible to them`);
    } catch (e) {
      record(`R4-8.${i + 1}`, 'UNDETERMINED', `${who} checks`, `query failed (${String(e.stderr || e.message).split('\n')[0].slice(0, 120)})`);
    }
  }
}

// ── R9 anything uploaded at all (tells "crew cannot see" from "nothing there") ─
if (dbAvailable()) {
  try {
    const uploaded = n(q(`select count(*) from storage.objects where bucket_id = 'org-files' and name like '${ORG}/%'`));
    record('R9', uploaded > 0 ? 'PASS' : 'FAIL', 'office has uploaded roof data / photos for the pilot org', `${uploaded} object(s) in org-files`);
  } catch (e) { record('R9', 'UNDETERMINED', 'office uploads', `query failed (${e.name})`); }
}

// ── R11 field events are being recorded (X-W1.19) ──────────────────────────────
// Without field_events, the day's opens, load failures and file opens exist only in
// a runtime log that lasts one hour. The app side is built and records nothing until
// the table and its RPC exist (supabase/proposals/20260917_x_w1_19_field_events.sql).
if (dbAvailable()) {
  try {
    const present = q(`select (to_regclass('public.field_events') is not null) and (to_regprocedure('public.record_field_event(uuid,text,uuid,text,text,integer,timestamp with time zone)') is not null)`);
    record('R11', present === 't' ? 'PASS' : 'FAIL', 'field events are durably recorded',
      present === 't' ? 'field_events and record_field_event() exist' : 'field_events / record_field_event() not applied — opens, load failures and file opens are not recorded');
  } catch (e) { record('R11', 'UNDETERMINED', 'field events are durably recorded', `query failed (${e.name})`); }
}

// ── R10 can we still see what happened after the day ends ───────────────────
// Runtime logs are the only place a page open or a failed load appears today.
// Vercel docs (read 2026-09-16): Hobby keeps 1 hour, Pro 1 day; drains Pro only.
// Asked THROUGH the CLI (2026-09-18): the raw token in the CLI's auth file went stale
// and the API answered "forbidden" while the CLI itself was signed in — a check
// reading that file reported "cannot tell" on a question the CLI could answer.
try {
  const out = execFileSync('vercel', ['api', `/v2/teams/${cfg.vercelScope}`], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 60000 });
  const plan = JSON.parse(out)?.billing?.plan;
  if (!plan) record('R10', 'UNDETERMINED', 'runtime logs outlive the pilot day', 'plan not in the API answer');
  else if (plan === 'hobby') record('R10', 'FAIL', 'runtime logs outlive the pilot day', 'Vercel plan hobby: 1 hour of runtime logs, no log drains');
  else record('R10', 'PASS', 'runtime logs outlive the pilot day', `Vercel plan ${plan}: at least 1 day of runtime logs`);
} catch (e) { record('R10', 'UNDETERMINED', 'runtime logs outlive the pilot day', `could not ask the Vercel CLI (${e.code || e.name})`); }

// ── report ──────────────────────────────────────────────────────────────────
for (const r of results) console.log(`${r.verdict.padEnd(12)} ${r.id.padEnd(7)} ${r.what} — ${r.fact}`);
const fails = results.filter((r) => r.verdict === 'FAIL').length;
const unknown = results.filter((r) => r.verdict === 'UNDETERMINED').length;
console.log('------------------------------------------------------------------------');
if (fails) { console.log(`NOT READY: ${fails} FAIL, ${unknown} UNDETERMINED, ${results.length - fails - unknown} PASS`); process.exit(1); }
if (unknown) { console.log(`UNDETERMINED: ${unknown} check(s) could not be answered`); process.exit(2); }
console.log(`READY: ${results.length} of ${results.length} PASS`); process.exit(0);
