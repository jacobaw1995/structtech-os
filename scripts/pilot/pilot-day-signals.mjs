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

// Completion against SCHEDULED work (X-W1.19): the denominator is trade work orders
// with a schedule block covering the day — the schedule is what the office planned.
// This is not A4.1's daily objective (not built); it is the closest durable stand-in.
const D = `'${day}'::date`;
row('trade work orders scheduled for this day', `select count(distinct w.id) from public.work_orders w join public.schedule_blocks b on b.work_order_id = w.id where w.org_id = '${ORG}' and w.kind = 'trade' and ${D} between b.start_date and b.end_date`);
row('…of which checked in on that day (completion)', `select count(distinct w.id) from public.work_orders w join public.schedule_blocks b on b.work_order_id = w.id where w.org_id = '${ORG}' and w.kind = 'trade' and ${D} between b.start_date and b.end_date and exists (select 1 from public.check_ins c where c.work_order_id = w.id and ${W.replaceAll('created_at', 'c.created_at')})`);

const EV = `org_id = '${ORG}' and ${W.replaceAll('created_at', 'occurred_at')}`;
// true = present, false = not applied, null = could not tell (never read as "absent").
let events = null;
try { events = q("select to_regclass('public.field_events') is not null") === 't'; } catch { events = null; }
if (events === null) console.log('field_events: UNDETERMINED — the check itself failed, so presence is unknown');
if (events) {
  console.log('COUNTED from field_events:');
  row('sign-ins (every one, not just the last)', `select count(*) from public.field_events where event = 'signed_in' and ${EV}`);
  row('named crew who opened at least one work order', `select count(distinct actor_id) from public.field_events where event in ('work_order_opened','packet_opened') and actor_id in (${crewList}) and ${EV}`);
  row('work order / packet opens (server-rendered)', `select count(*) from public.field_events where event in ('work_order_opened','packet_opened') and ${EV}`);
  row('pages that became usable on the phone (page_ready)', `select count(*) from public.field_events where event = 'page_ready' and ${EV}`);
  row('…median ms to usable', `select coalesce(percentile_cont(0.5) within group (order by duration_ms)::int::text, '-') from public.field_events where event = 'page_ready' and ${EV}`);
  row('…sent late (phone was offline)', `select count(*) from public.field_events where event = 'page_ready' and outcome = 'sent_late' and ${EV}`);
  row('opens with NO page_ready from that person (failed or abandoned)', `select count(*) from public.field_events o where o.event in ('work_order_opened','packet_opened') and ${EV.replaceAll('org_id', 'o.org_id').replaceAll('occurred_at', 'o.occurred_at')} and not exists (select 1 from public.field_events r where r.event = 'page_ready' and r.actor_id = o.actor_id and r.work_order_id = o.work_order_id and r.occurred_at between o.occurred_at and o.occurred_at + interval '2 minutes')`);
  row('files opened (distinct files)', `select count(distinct subject_ref) from public.field_events where event = 'file_opened' and ${EV}`);
  row('check-ins that failed to save', `select count(*) from public.field_events where event = 'check_in_failed' and ${EV}`);
  row('minutes from first open to first check-in, median per crew member', `with f as (select actor_id, min(occurred_at) filter (where event in ('work_order_opened','packet_opened')) o, min(occurred_at) filter (where event = 'check_in_saved') c from public.field_events where ${EV} group by actor_id) select coalesce(round(percentile_cont(0.5) within group (order by extract(epoch from (c - o)) / 60))::text, '-') from f where o is not null and c is not null and c > o`);
}

console.log('NOT RECORDED ANYWHERE — these read as unknown, never as zero:');
for (const line of [
  ...(events !== false ? [] : [
    'opens of a work order or packet, pages that never became usable, every sign-in, and file opens — field_events is not applied (supabase/proposals/20260917_x_w1_19_field_events.sql); the app side is built and records the moment it exists',
  ]),
  "whether they saw TODAY'S objective (A4.1 not built; completion above is against the SCHEDULE instead)",
  'special trips / exceptions (A4.2 not built)',
  'QC photos required vs taken (A4.3 not built)',
  'whether a locked-out crew member can reset their password: reset mail goes through the Supabase built-in mailer, which refuses addresses outside the Supabase team (measured 2026-09-16) — fixed by custom SMTP, not by instrumentation',
]) console.log(`  · ${line}`);
