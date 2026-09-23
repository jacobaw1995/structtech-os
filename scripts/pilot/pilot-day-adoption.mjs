#!/usr/bin/env node
// A4.8 — did the crew use it?  Track X, X-W1.21, 2026-09-23. Pilot 2026-10-07.
//
//   node scripts/pilot/pilot-day-adoption.mjs 2026-10-07 [--org <uuid>]
//   node scripts/pilot/pilot-day-adoption.mjs --calibrate      (no production access)
//
// Read-only against production: every statement runs inside BEGIN READ ONLY and is
// rolled back (scripts/pilot/db.mjs).
//
// WHAT IT ANSWERS, from data rather than memory: whether the crew opened the work
// order, whether they recorded anything, and where they stopped.
//
// WHAT IT REFUSES TO DO: report a zero as a finding. Production adoption is zero
// today and stays zero until crews use it, so every reading before 2026-10-07 is a
// zero taken against a zero. The report says that in its own output — per counter,
// using whether that event kind has EVER been recorded in this database — because
// a future reader seeing "0 of 1 crew opened a work order" would otherwise read a
// measurement where there was only silence.
//
// CALIBRATE FIRST (rule 20: show the instrument the defect before trusting its
// zero). `--calibrate` builds a throwaway PostgreSQL cluster, loads the APPLIED
// migrations for field_events and qc_items, seeds one day of known behaviour, and
// runs THESE SAME query functions over it. If a counter cannot report the
// behaviour that is definitely there, its zero on production means nothing.

import { readFileSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { q as liveQ, dbAvailable } from "./db.mjs";
import { containers, funnel, perWorkOrder, whereTheyStopped, everSeen, fmt, EVENT_KINDS } from "./adoption-queries.mjs";

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const args = process.argv.slice(2);
const CALIBRATE = args.includes("--calibrate");
const day = args.find((a) => /^\d{4}-\d{2}-\d{2}$/.test(a));
// indexOf returns -1 when the flag is absent, and args[0] is then the DATE — which
// was read as an org id until this line was fixed (2026-09-23).
const orgArg = args.includes("--org") ? args[args.indexOf("--org") + 1] : undefined;

function report(q, org, orgName, day, { calibrating = false } = {}) {
  const seen = everSeen(q);
  const c = containers(q, org, day);
  const f = funnel(q, org, day, c.crew);
  const lines = [];
  lines.push(`FIELD ADOPTION · ${day} (America/New_York) · tenant ${org.slice(0, 8)}${orgName ? ` ${orgName}` : ""}`);
  lines.push(`CONTAINERS`);
  lines.push(`  ${fmt(c.tenants)}`);
  lines.push(`  ${fmt(c.crewCount)}`);
  lines.push(`  ${fmt(c.scheduledCount)}`);
  lines.push(`FUNNEL — one line per stage, each against the crew roster`);
  const stage = (label, cnt, kinds) => {
    const dead = kinds.every((k) => seen[k] === 0);
    lines.push(`  ${label.padEnd(44)} ${fmt(cnt)}${dead ? "   [UNEXERCISED: no row of this kind has ever been recorded here — this zero measures nothing]" : ""}`);
  };
  stage("signed in", f.signedIn, ["signed_in"]);
  stage("opened a work order", f.opened, ["work_order_opened", "packet_opened"]);
  stage("page became usable on their phone", f.usable, ["page_ready"]);
  stage("recorded something (check-in or QC)", f.recorded, ["check_in_saved"]);
  lines.push(`  ${"produced events but not on the crew roster".padEnd(44)} ${fmt(f.offRoster)}`);

  lines.push(`WHERE THEY STOPPED`);
  const stopped = whereTheyStopped(q, org, day);
  if (stopped.length === 0) lines.push(`  nobody produced an event in this tenant on this day`);
  else stopped.forEach((s) => lines.push(`  ${s}`));

  lines.push(`PER SCHEDULED WORK ORDER (${c.scheduled.length})`);
  const per = perWorkOrder(q, org, day, c.scheduled);
  if (per.length === 0) lines.push(`  no trade work order was scheduled for this day`);
  else per.forEach((r) => lines.push(`  ${r.wo}  opens=${r.opens}  check-ins=${r.checkIns}  live QC attestations=${r.qcLive}`));

  const totalRows = Object.values(seen).reduce((a, b) => a + b, 0);
  const kindsSeen = EVENT_KINDS.filter((k) => seen[k] > 0);
  lines.push(`INSTRUMENT STATE`);
  lines.push(`  field_events rows in this database (all time, all tenants): ${totalRows}`);
  lines.push(`  event kinds ever recorded: ${kindsSeen.length} of ${EVENT_KINDS.length}${kindsSeen.length ? ` (${kindsSeen.join(", ")})` : ""}`);
  if (!calibrating) {
    lines.push(
      kindsSeen.length === EVENT_KINDS.length
        ? `  every counter above has fired at least once in this database.`
        : `  counters for ${EVENT_KINDS.filter((k) => seen[k] === 0).join(", ")} have NEVER fired here. Run --calibrate: it proves they can, on seeded data.`
    );
  }
  return lines.join("\n");
}

// ── live ──────────────────────────────────────────────────────────────────────
if (!CALIBRATE) {
  if (!day) {
    console.log("usage: pilot-day-adoption.mjs YYYY-MM-DD [--org <uuid>] | --calibrate");
    process.exit(2);
  }
  if (!dbAvailable()) {
    console.log("UNDETERMINED: SUPABASE_DB_URL not available — nothing was read, and that is not a zero.");
    process.exit(2);
  }
  const orgs = orgArg
    ? [orgArg]
    : liveQ(`select o.id from public.organizations o join public.tenant_modules t on t.org_id = o.id and t.module_key = 'field' and t.enabled order by o.name`)
        .split("\n")
        .map((s) => s.trim())
        .filter(Boolean);
  for (const org of orgs) {
    const name = liveQ(`select name from public.organizations where id = '${org}'`).trim();
    console.log(report(liveQ, org, name, day));
    console.log("");
  }
  process.exit(0);
}

// ── calibration: the same functions, over behaviour that is definitely there ───
const PG_BIN = path.dirname(execFileSync("bash", ["-lc", "command -v initdb"], { encoding: "utf8" }).trim());
const WORK = mkdtempSync(path.join(tmpdir(), "adoption-calibrate-"));
const PORT = process.env.FIXTURE_PORT ?? "5495";
const psql = (db, sqlOrFile, isFile = false) =>
  execFileSync(path.join(PG_BIN, "psql"), ["-h", WORK, "-p", PORT, "-U", "fixture", "-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1", "-d", db, isFile ? "-f" : "-c", sqlOrFile], { encoding: "utf8", env: { ...process.env, LC_ALL: "C" } });
try {
  execFileSync(path.join(PG_BIN, "initdb"), ["-D", `${WORK}/data`, "-U", "fixture", "--auth=trust"], { stdio: "ignore", env: { ...process.env, LC_ALL: "C" } });
  execFileSync(path.join(PG_BIN, "pg_ctl"), ["-D", `${WORK}/data`, "-o", `-p ${PORT} -k ${WORK} -c listen_addresses=''`, "-l", `${WORK}/log`, "start", "-w"], { stdio: "ignore", env: { ...process.env, LC_ALL: "C" } });
  psql("postgres", "create database cal");
  // The live-helper mirror (auth.uid, my_org_ids, org_members, work_orders, …).
  psql("cal", path.join(ROOT, "scripts/storage/org-files-fixture/schema.sql"), true);
  psql("cal", `
    create table if not exists public.organizations (id uuid primary key, name text);
    create table if not exists public.tenant_modules (org_id uuid, module_key text, enabled boolean, config jsonb default '{}');
    create table if not exists public.schedule_blocks (id uuid default gen_random_uuid(), org_id uuid, work_order_id uuid, start_date date, end_date date);
    create table if not exists public.check_ins (id uuid default gen_random_uuid(), org_id uuid, work_order_id uuid, created_by uuid, created_at timestamptz default now());
    alter table public.work_orders add column if not exists voided_at timestamptz;
    alter table public.check_ins add column if not exists created_by uuid;
    alter table public.check_ins add column if not exists created_at timestamptz default now();`);
  // THE APPLIED migrations, so what is calibrated is what runs in production.
  for (const m of ["20260918020231_x_w1_19_field_events.sql", "20260922004806_x_w1_20_qc_items.sql", "20260922221943_qc_items_three_rulings.sql"]) {
    const file = path.join(ROOT, "supabase/migrations", m);
    if (existsSync(file)) psql("cal", file, true);
  }
  const ORG = "aaaaaaaa-0000-0000-0000-000000000001";
  const CREW_USED = "c0000000-0000-0000-0000-00000000c1c1";
  const CREW_STOPPED = "c0000000-0000-0000-0000-00000000c2c2";
  const OFFICE = "0ff1ce00-0000-0000-0000-0000000000ff";
  const WO = "aaaa0000-0000-0000-0000-0000000000a1";
  const DAY = "2026-10-07";
  psql("cal", `
    insert into public.organizations values ('${ORG}', 'CALIBRATION TENANT');
    insert into public.tenant_modules values ('${ORG}', 'field', true, '{}');
    insert into public.org_members values ('${ORG}','${CREW_USED}','field','{}'), ('${ORG}','${CREW_STOPPED}','field','{}'), ('${ORG}','${OFFICE}','office','{}');
    insert into public.work_orders (id, org_id, kind) values ('${WO}','${ORG}','trade');
    insert into public.schedule_blocks (org_id, work_order_id, start_date, end_date) values ('${ORG}','${WO}','${DAY}','${DAY}');
    insert into public.check_ins (org_id, work_order_id, created_by, created_at) values ('${ORG}','${WO}','${CREW_USED}','${DAY} 14:00-04');
    insert into public.qc_items (org_id, work_order_id, requirement_key, kind, photo_ref, actor_id, occurred_at)
      values ('${ORG}','${WO}','magnet_sweep','confirm',null,'${CREW_USED}','${DAY} 15:00-04');
    insert into public.field_events (org_id, actor_id, event, work_order_id, outcome, duration_ms, occurred_at) values
      ('${ORG}','${CREW_USED}','signed_in',null,null,null,'${DAY} 13:00-04'),
      ('${ORG}','${CREW_USED}','work_order_opened','${WO}',null,null,'${DAY} 13:05-04'),
      ('${ORG}','${CREW_USED}','page_ready','${WO}','ok',1800,'${DAY} 13:05-04'),
      ('${ORG}','${CREW_USED}','check_in_saved','${WO}','ok',null,'${DAY} 14:00-04'),
      ('${ORG}','${CREW_STOPPED}','signed_in',null,null,null,'${DAY} 13:10-04'),
      ('${ORG}','${OFFICE}','work_order_opened','${WO}',null,null,'${DAY} 16:00-04'),
      ('${ORG}','${CREW_USED}','packet_opened','${WO}',null,null,'${DAY} 18:00-04'),
      ('${ORG}','${CREW_USED}','file_opened','${WO}','ok',null,'${DAY} 18:01-04'),
      ('${ORG}','${CREW_USED}','file_removed','${WO}','ok',null,'${DAY} 18:02-04'),
      ('${ORG}','${CREW_USED}','check_in_failed','${WO}','crew_required',null,'${DAY} 18:03-04'),
      ('${ORG}','${CREW_USED}','work_order_opened','${WO}',null,null,'${DAY} 03:00-04'),
      ('${ORG}','${CREW_USED}','work_order_opened','${WO}',null,null,'2026-10-08 13:00-04');`);
  const calQ = (sql) => psql("cal", `begin read only; ${sql}; rollback;`).replace(/\n?(BEGIN|ROLLBACK)\n?/g, "");
  console.log(report(calQ, ORG, "CALIBRATION TENANT", DAY, { calibrating: true }));
  // Each expectation is a behaviour that is definitely in the seed above.
  const c = containers(calQ, ORG, DAY);
  const f = funnel(calQ, ORG, DAY, c.crew);
  const per = perWorkOrder(calQ, ORG, DAY, c.scheduled);
  const checks = [
    ["crew roster is the denominator, office excluded", c.crewCount.of === 2],
    ["scheduled work orders counted in their container", c.scheduledCount.n === 1 && c.scheduledCount.of === 1],
    ["signed in counts both crew", f.signedIn.n === 2],
    ["opened counts only the one who opened", f.opened.n === 1],
    ["page_ready counts only the one whose page reported", f.usable.n === 1],
    ["recorded counts the one who checked in", f.recorded.n === 1],
    ["office is reported as off-roster, not as crew", f.offRoster.n === 1],
    // 4 = three crew opens plus the office member's open, all on 2026-10-07; the
    // 2026-10-08 open is excluded and shows up as 1 when the next day is counted.
    // (My first expectation here said 3 — it forgot the office open. The counter
    // was right and the prediction was wrong; rule 21.)
    ["per-work-order opens count everyone who opened it that day", per[0].opens === 4],
    ["the New York day boundary excludes the next day's open", perWorkOrder(calQ, ORG, "2026-10-08", c.scheduled)[0].opens === 1],
    ["check-ins counted on the work order", per[0].checkIns === 1],
    ["live QC attestations counted", per[0].qcLive === 1],
  ];
  console.log("\nCALIBRATION — can each counter report behaviour that is definitely there?");
  checks.forEach(([label, ok]) => console.log(`  ${ok ? "FIRED " : "FAILED"} ${label}`));
  const failed = checks.filter(([, ok]) => !ok).length;
  console.log("------------------------------------------------------------------------");
  console.log(failed === 0 ? "CALIBRATED: every counter fired on seeded behaviour." : `NOT CALIBRATED: ${failed} counter(s) could not see what was there.`);
  process.exit(failed === 0 ? 0 : 1);
} finally {
  try {
    execFileSync(path.join(PG_BIN, "pg_ctl"), ["-D", `${WORK}/data`, "-m", "immediate", "stop"], { stdio: "ignore" });
  } catch {}
  rmSync(WORK, { recursive: true, force: true });
}
