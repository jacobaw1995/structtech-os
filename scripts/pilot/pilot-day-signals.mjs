#!/usr/bin/env node
// What happened in the field on a given day, from durable records only.
// Track X, X-W1.18, 2026-09-16.
//
//   node scripts/pilot/pilot-day-signals.mjs 2026-10-07     (a New York calendar date)
//
// Read-only. Reads the database only — not runtime logs, which on this Vercel plan
// last one hour and so cannot answer a question asked the next morning.
//
// It prints what CAN be counted, and then, just as prominently, what CANNOT — so a
// quiet day with no records is never read as "the crew did not use it" when the
// truth is "nothing records that kind of use".

import { readFileSync, existsSync } from 'node:fs';
import { q, dbAvailable } from './db.mjs';

const day = process.argv[2];
if (!/^\d{4}-\d{2}-\d{2}$/.test(day ?? '')) { console.log('usage: pilot-day-signals.mjs YYYY-MM-DD (New York date)'); process.exit(2); }
const CFG_PATH = process.env.PILOT_CONFIG || new URL('./pilot.config.json', import.meta.url);
const cfg = JSON.parse(readFileSync(existsSync(CFG_PATH) ? CFG_PATH : new URL('./pilot.config.example.json', import.meta.url), 'utf8'));
const ORG = cfg.pilotOrgId;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
if (!UUID.test(ORG)) { console.log('pilotOrgId is not a uuid'); process.exit(2); }
if (!dbAvailable()) { console.log('UNDETERMINED: SUPABASE_DB_URL not available'); process.exit(2); }
const crew = (cfg.crewUserIds ?? []).filter((id) => UUID.test(id));
const crewList = crew.length ? crew.map((id) => `'${id}'`).join(',') : `'00000000-0000-0000-0000-000000000000'`;

// The day as an America/New_York window, converted by Postgres, not by this process.
const W = `created_at >= ('${day}'::date)::timestamp at time zone 'America/New_York' and created_at < ('${day}'::date + 1)::timestamp at time zone 'America/New_York'`;
const row = (label, sql) => { try { console.log(`  ${label.padEnd(58)} ${q(sql)}`); } catch (e) { console.log(`  ${label.padEnd(58)} UNDETERMINED (${String(e.stderr || e.message).split('\n')[0].slice(0, 80)})`); } };

console.log(`FIELD SIGNALS · ${day} (America/New_York) · pilot org ${ORG.slice(0, 8)} · named crew ${crew.length}`);
console.log('COUNTED from durable records:');
row('check-ins recorded (all authors)', `select count(*) from public.check_ins where org_id = '${ORG}' and ${W}`);
row('check-ins recorded by named crew', `select count(*) from public.check_ins where org_id = '${ORG}' and created_by in (${crewList}) and ${W}`);
row('distinct work orders checked in on', `select count(distinct work_order_id) from public.check_ins where org_id = '${ORG}' and ${W}`);
row('check-ins with at least one photo', `select count(*) from public.check_ins where org_id = '${ORG}' and coalesce(array_length(photos, 1), 0) > 0 and ${W}`);
row('check-ins reporting a blocker', `select count(*) from public.check_ins where org_id = '${ORG}' and nullif(trim(coalesce(blockers, '')), '') is not null and ${W}`);
row('office files added (roof data / photos)', `select count(*) from storage.objects where bucket_id = 'org-files' and name like '${ORG}/%' and ${W}`);
row('work order activity rows written', `select count(*) from public.work_order_activity where org_id = '${ORG}' and ${W}`);
row('named crew whose LAST sign-in fell on this day', `select count(*) from auth.users where id in (${crewList}) and last_sign_in_at >= ('${day}'::date)::timestamp at time zone 'America/New_York' and last_sign_in_at < ('${day}'::date + 1)::timestamp at time zone 'America/New_York'`);

console.log('NOT RECORDED ANYWHERE — these read as unknown, never as zero:');
for (const line of [
  'whether a crew member OPENED a work order or its packet (A4.5 acknowledgment; nothing writes an open)',
  "whether they saw TODAY'S objective (A4.1 not built)",
  'special trips / exceptions (A4.2 not built)',
  'QC photos required vs taken (A4.3 not built)',
  'completion rate and time-to-complete (A4.8: no expected-work denominator, no start event)',
  'page loads that failed, timed out, or were abandoned on a weak signal (runtime logs: 1 hour on Hobby)',
  'every sign-in of the day — only the LAST sign-in per person survives (auth.audit_log_entries holds 0 rows; auth events go to a log stream with short retention)',
  'which files a crew member actually opened (signed-url reads leave no durable record)',
]) console.log(`  · ${line}`);
