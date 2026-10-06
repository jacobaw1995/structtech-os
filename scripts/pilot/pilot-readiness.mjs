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

import { readFileSync, existsSync, writeFileSync, unlinkSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
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
// 2026-10-06: the two NEXT_PUBLIC_SUPABASE_* keys were named by NO readiness item
// at all, while production provably cannot build a Supabase client without them —
// so deleting either would have taken the whole app down with every check green.
const REQUIRED_ENV = ['ORG_FILES_ENABLED', 'AUTH_EMAIL_ENABLED', 'RESEND_API_KEY', 'EMAIL_FROM',
  'NEXT_PUBLIC_SUPABASE_URL', 'NEXT_PUBLIC_SUPABASE_ANON_KEY'];
try {
  const out = execFileSync('vercel', ['env', 'ls', 'production', '--scope', cfg.vercelScope], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 60000 });
  const names = new Set(out.split('\n').map((l) => l.trim().split(/\s+/)[0]).filter((w) => /^[A-Z][A-Z0-9_]+$/.test(w)));
  if (names.size === 0) record('R2', 'UNDETERMINED', 'production env names', 'vercel env ls returned no names (is the CLI linked?)');
  else {
    const missing = REQUIRED_ENV.filter((k) => !names.has(k));
    record('R2', missing.length ? 'FAIL' : 'PASS', 'production env names', missing.length ? `missing: ${missing.join(', ')}` : `present: ${REQUIRED_ENV.join(', ')}`);
  }
} catch (e) { record('R2', 'UNDETERMINED', 'production env names', `vercel CLI unavailable (${e.code || e.name})`); }

// ── R2b A FLAG'S VALUE, NOT ONLY ITS NAME ───────────────────────────────────
// 2026-10-05: ORG_FILES_ENABLED was set in production for the first time in 19
// days, and R2 went green — while the feature stayed DARK, because the app tests
// `process.env.X === "true"` and the stored value is not that string in any
// casing. A name-only check cannot see this, so for eleven days R2 measured the
// one thing that had moved and would have reported READY on a feature nobody
// could use.
//
// A FALSE GREEN IS WORSE THAN A RED. A red is a task; a green is a decision to
// stop looking. So every flag whose app semantics are `=== "true"` now has its
// VALUE verified here.
//
// AND A FALSE RED SENDS A HUMAN TO FIX SOMETHING THAT IS NOT BROKEN. It did,
// twice, on 2026-10-05 — and the first of those two reports was mine.
//
// A Vercel variable typed SENSITIVE cannot be read back: `vercel env pull`
// writes the literal string `[SENSITIVE]` in place of the value. That string is
// 11 characters, has no lowercase letter and contains no "true" in any casing —
// so the first version of this check reported it as `SET BUT NOT "true" (11
// chars)`, which is indistinguishable from a genuinely wrong value. ORG_FILES_
// ENABLED had been set correctly; the report said it was wrong and sent someone
// to a settings page.
//
// THE THIRD VERDICT IS KEYED ON THE LITERAL, NOT ON ITS SHAPE. Matching on
// length 11, or on "no lowercase", would be matching coincidences of this one
// placeholder: a genuinely wrong value of `DEVELOPMENT` is also 11 uppercase
// characters, and Vercel is free to change the placeholder's wording without
// changing that it is a placeholder. `value === '[SENSITIVE]'` says what is
// actually meant — this is the string the tool writes when it will not tell us —
// and it fails closed if the wording ever changes, into the FAIL branch, which
// is the safe direction.
//
// ITS MESSAGE NAMES THE FIX, AND THE FIX IS NOT "EDIT THE VALUE". A sensitive
// variable's value cannot be edited back into readability; it has to be removed
// and recreated as a normal variable. A message that says "wrong value" invites
// exactly the action that will not work.
//
// THE VALUE IS NEVER PRINTED AND NEVER KEPT. It is pulled to a temp file, read,
// asserted, and the file is overwritten and deleted in a finally — including on
// the error path, because a secrets file left behind by a crashed check is a
// worse bug than the one this check exists to find. Only the verdict is reported.
const BOOLEAN_FLAGS = ['ORG_FILES_ENABLED', 'AUTH_EMAIL_ENABLED'];
// R2 CHECKS NAMES. THAT IS WHY R2b EXISTS, AND WHY THESE TWO BELONG HERE TOO.
// R2 reported PASS on 2026-10-05 for a flag whose value the app rejected — a
// present name says nothing about a usable value. These two are not booleans, so
// they cannot join BOOLEAN_FLAGS, but they have the weaker requirement that still
// matters: the value must be READABLE. Both are typed Sensitive in Vercel today,
// so this check reports them UNREADABLE — which is the truth, and is the point:
// no check could previously say anything about them at all.
const READABLE_REQUIRED = ['NEXT_PUBLIC_SUPABASE_URL', 'NEXT_PUBLIC_SUPABASE_ANON_KEY'];
// Exactly what `vercel env pull` writes for a variable typed Sensitive. Compared
// as a literal, never pattern-matched: see the note above.
const SENSITIVE_PLACEHOLDER = '[SENSITIVE]';
const tmpEnv = path.join(tmpdir(), `readiness-env-${process.pid}-${Date.now()}`);
try {
  execFileSync('vercel', ['env', 'pull', tmpEnv, '--environment=production', '--yes', '--scope', cfg.vercelScope],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 60000 });
  const lines = readFileSync(tmpEnv, 'utf8').split('\n');
  const wrong = [];
  const absent = [];
  const unreadable = [];
  for (const key of BOOLEAN_FLAGS) {
    const line = lines.find((l) => l.startsWith(`${key}=`));
    if (!line) { absent.push(key); continue; }
    // Strip surrounding quotes the dotenv writer may add; compare what the app compares.
    const value = line.slice(key.length + 1).trim().replace(/^["']+|["']+$/g, '');
    if (value === SENSITIVE_PLACEHOLDER) unreadable.push(key);
    else if (value !== 'true') wrong.push(`${key} (${value.length} chars, not the string "true")`);
  }
  for (const key of READABLE_REQUIRED) {
    const line = lines.find((l) => l.startsWith(`${key}=`));
    if (!line) { absent.push(key); continue; }
    const value = line.slice(key.length + 1).trim().replace(/^["']+|["']+$/g, '');
    if (value === SENSITIVE_PLACEHOLDER) unreadable.push(key);
    else if (value.length === 0) wrong.push(`${key} (empty)`);
  }
  // Order matters: a genuinely wrong value is a defect and outranks an unreadable
  // one, which is a gap in what this check can see rather than a fault in the app.
  if (wrong.length) record('R2b', 'FAIL', 'required env VALUES are usable',
    `SET BUT UNUSABLE, so the feature is OFF while R2 reads green: ${wrong.join('; ')}`);
  else if (absent.length) record('R2b', 'FAIL', 'required env VALUES are usable', `not set: ${absent.join(', ')}`);
  else if (unreadable.length) record('R2b', 'UNREADABLE', 'required env VALUES are usable',
    `${unreadable.join(', ')} ${unreadable.length === 1 ? 'is' : 'are'} typed SENSITIVE in Vercel, so the value cannot be read back and this check CANNOT say whether ${unreadable.length === 1 ? 'it is' : 'they are'} usable. `
    + `THE FIX IS NOT TO EDIT THE VALUE — a sensitive variable's value cannot be read or corrected in place. Remove it and recreate it as a normal (non-sensitive) variable, then redeploy.`);
  else record('R2b', 'PASS', 'required env VALUES are usable', `${BOOLEAN_FLAGS.join(', ')} === "true"; ${READABLE_REQUIRED.join(', ')} readable and non-empty`);
} catch (e) {
  record('R2b', 'UNDETERMINED', 'required env VALUES are usable', `could not pull production env (${e.code || e.name})`);
} finally {
  try { writeFileSync(tmpEnv, '\0'.repeat(statSync(tmpEnv).size)); } catch { /* never existed */ }
  try { unlinkSync(tmpEnv); } catch { /* already gone */ }
}

// ── R3.. crew — named, and checked AS each person ───────────────────────────
const crew = Array.isArray(cfg.crewUserIds) ? cfg.crewUserIds.filter((id) => UUID.test(id)) : [];
if (!dbAvailable()) {
  record('R3', 'UNDETERMINED', 'pilot crew', 'SUPABASE_DB_URL not available');
} else if (crew.length === 0) {
  record('R3', 'FAIL', 'pilot crew named', cfg._fromExample
    ? 'no scripts/pilot/pilot.config.json — nobody is named as pilot crew'
    : 'crewUserIds is empty — nobody is named as pilot crew');
  // A CHECK THAT DID NOT RUN IS NOT A CHECK THAT PASSED, AND IT MUST NOT BE INVISIBLE.
  // Until 2026-09-27, R4-R8 did not exist at all when R3 failed: the loop below never
  // ran, nothing was recorded, and the summary read "4 FAIL, 0 UNDETERMINED, 2 PASS"
  // — six items out of eleven, with nothing in the output saying five were missing.
  // Eleven days of NOT READY were reported that way, and the missing five are the
  // only ones that ask what a crew member can actually reach. They are asked AS a
  // named person, so with nobody named they genuinely cannot be answered — which is
  // what UNDETERMINED is for, per this file's own header rule: a check that cannot
  // run is UNDETERMINED, never PASS. Recorded now, so the denominator is whole.
  for (const [id, what] of [
    ['R4', 'crew have accounts and have signed in'],
    ['R5', 'crew see a job to work on'],
    ['R6', 'crew cannot reach a master work order'],
    ['R7', 'crew see no estimate (no $ in the field)'],
    ['R8', 'crew can open roof data / photos from the office'],
  ]) record(id, 'UNDETERMINED', what, 'NOT RUN — asked as a named crew member, and R3 names nobody');
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
// UNREADABLE JOINS UNDETERMINED AS "NOT ANSWERED", AND THAT IS THE WHOLE POINT
// OF IT. Adding a verdict without telling the summary about it would have made
// an unreadable check count as ANSWERED — the same defect as the one fixed on
// 2026-09-27, where R4-R8 did not run and the last line could not say so. A new
// verdict is not finished until the line that counts verdicts knows it exists.
const UNANSWERED = new Set(['UNDETERMINED', 'UNREADABLE']);
const unansweredRows = results.filter((r) => UNANSWERED.has(r.verdict));
const unknown = unansweredRows.length;
console.log('------------------------------------------------------------------------');
// THE SUMMARY STATES ITS DENOMINATOR AND WHAT IT COULD NOT LOOK AT. A line reading
// "4 FAIL, 2 PASS" is a verdict on six things; said without the six, it reads as a
// verdict on readiness. Every count below is "of N", and the unanswered are named,
// because the ones that cannot be answered are not the unimportant ones — on
// 2026-09-27 they were the five that ask what a crew member can actually reach.
const answered = results.length - unknown;
console.log(`ANSWERED ${answered} of ${results.length} checks` + (unknown ? `; ${unknown} UNANSWERED: ${unansweredRows.map((r) => `${r.id}(${r.verdict === 'UNREADABLE' ? 'unreadable' : 'not run'})`).join(', ')}` : ''));
if (fails) { console.log(`NOT READY: ${fails} FAIL, ${unknown} UNANSWERED, ${results.length - fails - unknown} PASS — of ${results.length}`); process.exit(1); }
if (unknown) { console.log(`UNANSWERED: ${unknown} of ${results.length} check(s) could not be answered`); process.exit(2); }
console.log(`READY: ${results.length} of ${results.length} PASS`); process.exit(0);
