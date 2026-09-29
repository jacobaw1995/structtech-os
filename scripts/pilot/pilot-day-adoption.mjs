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
import { containers, funnel, perWorkOrder, whereTheyStopped, everSeen, everSeenInOrg, fmt, EVENT_KINDS,
         opens, completionRate, timeToComplete, fmtRate, fmtDuration, isUndefined } from "./adoption-queries.mjs";

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const args = process.argv.slice(2);
const CALIBRATE = args.includes("--calibrate");
const day = args.find((a) => /^\d{4}-\d{2}-\d{2}$/.test(a));
// indexOf returns -1 when the flag is absent, and args[0] is then the DATE — which
// was read as an org id until this line was fixed (2026-09-23).
const orgArg = args.includes("--org") ? args[args.indexOf("--org") + 1] : undefined;

function report(q, org, orgName, day, { calibrating = false } = {}) {
  const seen = everSeen(q);
  const seenHere = everSeenInOrg(q, org);
  const c = containers(q, org, day);
  const f = funnel(q, org, day, c.crew);
  const lines = [];
  lines.push(`FIELD ADOPTION · ${day} (America/New_York) · tenant ${org.slice(0, 8)}${orgName ? ` ${orgName}` : ""}`);
  lines.push(`CONTAINERS`);
  lines.push(`  ${fmt(c.tenants)}`);
  lines.push(`  ${fmt(c.crewCount)}`);
  lines.push(`  ${fmt(c.scheduledCount)}`);
  lines.push(`FUNNEL — one line per stage, each against the crew roster`);
  // THREE GRADES, because two let another tenant's activity vouch for this one
  // (2026-09-28 — see everSeenInOrg). The marker's words and the marker's query
  // now ask the same question.
  const stage = (label, cnt, kinds) => {
    const firedAnywhere = kinds.some((k) => seen[k] > 0);
    const firedHere = kinds.some((k) => seenHere[k] > 0);
    const mark = !firedAnywhere
      ? "   [UNEXERCISED ANYWHERE: no row of this kind exists in this database — this zero measures nothing]"
      : !firedHere
        ? "   [UNEXERCISED HERE: recorded in another tenant, never in this one — the path works; nothing here has used it]"
        : "";
    lines.push(`  ${label.padEnd(44)} ${fmt(cnt)}${mark}`);
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

  // A4.8's three named measures. Each prints its denominator, and a rate whose
  // denominator is 0 prints UNDEFINED rather than 0% — see adoption-queries.mjs.
  const op = opens(q, org, day, c.scheduled);
  const comp = completionRate(q, org, day, c.scheduled);
  const ttc = timeToComplete(q, org, day);
  lines.push(`A4.8 — OPENS · COMPLETION RATE · TIME-TO-COMPLETE`);
  lines.push(`  opens, of the work assigned    ${fmtRate(op.scheduledOpened)}`);
  lines.push(`  opens recorded, any work order ${fmt(op.totalOpens)}`);
  lines.push(`  completion rate                ${fmtRate(comp)}`);
  lines.push(`  time-to-complete               ${fmtDuration(ttc)}`);

  lines.push(`PER SCHEDULED WORK ORDER (${c.scheduled.length})`);
  const per = perWorkOrder(q, org, day, c.scheduled);
  if (per.length === 0) lines.push(`  no trade work order was scheduled for this day`);
  else per.forEach((r) => lines.push(`  ${r.wo}  opens=${r.opens}  check-ins=${r.checkIns}  live QC attestations=${r.qcLive}`));

  const totalRows = Object.values(seen).reduce((a, b) => a + b, 0);
  const kindsSeen = EVENT_KINDS.filter((k) => seen[k] > 0);
  const kindsHere = EVENT_KINDS.filter((k) => seenHere[k] > 0);
  lines.push(`INSTRUMENT STATE`);
  lines.push(`  field_events rows in this database (all time, all tenants): ${totalRows}`);
  lines.push(`  event kinds ever recorded ANYWHERE:      ${kindsSeen.length} of ${EVENT_KINDS.length}${kindsSeen.length ? ` (${kindsSeen.join(", ")})` : ""}`);
  lines.push(`  event kinds ever recorded IN THIS TENANT: ${kindsHere.length} of ${EVENT_KINDS.length}${kindsHere.length ? ` (${kindsHere.join(", ")})` : ""}`);
  // Naming which database this block describes, because the same function prints
  // production and the calibration fixture and they are easy to confuse: on
  // 2026-09-28 I briefly read the fixture's "8 of 8" as production's.
  if (calibrating) lines.push(`  (this block describes the CALIBRATION FIXTURE, not production)`);
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
  const ORG_QUIET = "aaaaaaaa-0000-0000-0000-000000000002";
  const CREW_QUIET = "c0000000-0000-0000-0000-00000000c3c3";
  psql("cal", `
    insert into public.organizations values ('${ORG}', 'CALIBRATION TENANT');
    insert into public.tenant_modules values ('${ORG}', 'field', true, '{}');
    insert into public.org_members values ('${ORG}','${CREW_USED}','field','{}'), ('${ORG}','${CREW_STOPPED}','field','{}'), ('${ORG}','${OFFICE}','office','{}');
    insert into public.work_orders (id, org_id, kind) values ('${WO}','${ORG}','trade');
    insert into public.schedule_blocks (org_id, work_order_id, start_date, end_date) values ('${ORG}','${WO}','${DAY}','${DAY}');
    -- A second scheduled day with NO check-in, so the calibration has a case where
    -- the denominator is real and the numerator is zero. That is 0% and must NOT
    -- render as UNDEFINED — the converse of the quiet tenant, and the reason
    -- "always print UNDEFINED" cannot pass the suite either.
    insert into public.schedule_blocks (org_id, work_order_id, start_date, end_date) values ('${ORG}','${WO}','2026-10-09','2026-10-09');
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
      ('${ORG}','${CREW_USED}','work_order_opened','${WO}',null,null,'2026-10-08 13:00-04');
    -- A SECOND TENANT, seeded with signed_in AND NOTHING ELSE. It exists so the
    -- per-tenant marker has a defect to catch: before 2026-09-28 the marker keyed
    -- on the whole database, so ORG_QUIET's zeros printed unmarked because ORG was
    -- busy. That is exactly what happened to Brothers Metal Roofing when golden-path
    -- run 1 wrote rows in the synthetic tenant. Without this second tenant the
    -- calibration cannot tell the two implementations apart.
    insert into public.organizations values ('${ORG_QUIET}', 'CALIBRATION QUIET TENANT');
    insert into public.tenant_modules values ('${ORG_QUIET}', 'field', true, '{}');
    insert into public.org_members values ('${ORG_QUIET}','${CREW_QUIET}','field','{}');
    insert into public.field_events (org_id, actor_id, event, work_order_id, outcome, duration_ms, occurred_at) values
      ('${ORG_QUIET}','${CREW_QUIET}','signed_in',null,null,null,'${DAY} 13:00-04');`);
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
    // THE MARKER'S WORDS AND THE MARKER'S QUERY MUST ASK THE SAME QUESTION.
    // These four are the regression test for the 2026-09-28 defect. The first two
    // test the data; the last two test THE PRINTED TEXT, because the text is what
    // misled — a correct count under a wrong sentence is still a wrong report.
    ["a kind fired in another tenant is NOT counted as fired here", everSeenInOrg(calQ, ORG_QUIET).work_order_opened === 0 && everSeen(calQ).work_order_opened > 0],
    ["a kind fired nowhere reads zero in both scopes", everSeen(calQ).file_opened > 0 && everSeenInOrg(calQ, ORG_QUIET).file_opened === 0],
    ["the quiet tenant's report says UNEXERCISED HERE, not nothing", report(calQ, ORG_QUIET, "QUIET", DAY, { calibrating: true }).includes("UNEXERCISED HERE")],
    ["the busy tenant's exercised stage carries no marker at all", (() => { const r = report(calQ, ORG, "BUSY", DAY, { calibrating: true }).split("\n").find((l) => l.includes("opened a work order")); return Boolean(r) && !r.includes("UNEXERCISED"); })()],
    // A4.8's three measures, and the distinction the whole thing turns on:
    // a rate with a denominator is a number; a rate without one is UNDEFINED.
    ["opens are counted against the work actually scheduled", opens(calQ, ORG, DAY, c.scheduled).scheduledOpened.pct === 100],
    ["completion rate is a real rate when work was scheduled", completionRate(calQ, ORG, DAY, c.scheduled).pct === 100],
    // 660 = 03:00 -> 14:00. My first expectation here said 55 (13:05 -> 14:00) and
    // was WRONG: the measure takes the FIRST open of the day, and the seed contains
    // a deliberate 03:00 open. The counter was right and the prediction was wrong
    // (rule 21). The mechanism matters beyond this fixture — a crew member who opens
    // a job at dawn and checks in after lunch scores the whole morning, which is the
    // intended reading of "time to complete" and not of "time spent in the app".
    ["time-to-complete measures first open to first check-in", timeToComplete(calQ, ORG, DAY).median === 660],
    // THE ZERO-DENOMINATOR CASES. The quiet tenant has no schedule block, so its
    // rate has nothing to be a rate OF. 0% would be a lie: it says work was given
    // and none was done. These are the checks that must fail if anyone "simplifies"
    // undefined back to zero.
    ["a rate with no denominator is UNDEFINED, not 0%", isUndefined(completionRate(calQ, ORG_QUIET, DAY, containers(calQ, ORG_QUIET, DAY).scheduled))],
    // The rendered line must not be a PERCENTAGE. Testing !includes("0%") was my
    // own bug: the undefined text deliberately ends "Not 0%.", so the substring is
    // present on purpose. Match the shape fmtRate emits when it HAS a denominator
    // ("12.5%  (1 of 8 ...)") instead of a substring that appears in both.
    ["and it RENDERS as undefined, not as a percentage", (() => { const l = report(calQ, ORG_QUIET, "QUIET", DAY, { calibrating: true }).split("\n").find((x) => x.includes("completion rate")); return Boolean(l) && l.includes("UNDEFINED") && !/\d+(\.\d+)?%\s+\(/.test(l); })()],
    ["time-to-complete with no pairs is UNDEFINED, not 0 minutes", isUndefined(timeToComplete(calQ, ORG_QUIET, DAY))],
    // ...and the converse, so "always print UNDEFINED" cannot pass either:
    ["a real denominator with a zero numerator IS 0%, not undefined", (() => { const r = completionRate(calQ, ORG, "2026-10-09", containers(calQ, ORG, "2026-10-09").scheduled); return isUndefined(r) === false ? r.pct === 0 : false; })()],
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
