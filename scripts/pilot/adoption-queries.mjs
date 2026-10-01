// The counting, in one place.  Track X, X-W1.21, 2026-09-23. A4.8.
//
// THE QUESTION THIS ANSWERS, on the evening of 2026-10-07: did the crew open the
// work order, did they record anything, and where did they stop. Not "how much
// traffic was there".
//
// EVERY COUNT CARRIES ITS DENOMINATOR AND ITS CONTAINER. A count returned from
// here is always {n, of, container} — "3 of 4 crew in ZZ SYNTHETIC", never "3".
// A bare number is not a fact about a pilot; it is a number.
//
// WHAT A ZERO MEANS HERE. An event row records a thing that HAPPENED. No row
// records a thing that did not: a person who never opened the app and a person
// whose phone failed to record are the same zero to this file. So every counter
// also reports whether its event kind has EVER been seen in this database
// (`everSeen`), and the report prints UNEXERCISED against any counter that has
// never fired. A zero under an unexercised counter measures nothing at all.
//
// Both modes — live production and the local calibration — call these same
// functions, so what is calibrated is what reads production.

/** A count that knows what it is out of, and where it was counted. */
export const count = (n, of, container) => ({ n, of, container });
export const fmt = (c) => `${c.n} of ${c.of} ${c.container}`;

const one = (q, sql) => q(sql).trim();
const num = (q, sql) => Number.parseInt(one(q, sql) || "0", 10);
const list = (q, sql) => one(q, sql).split("\n").map((r) => r.trim()).filter(Boolean);

/** The New York day as a half-open window, converted by Postgres, not by node. */
export const dayWindow = (day, col) =>
  `${col} >= ('${day}'::date)::timestamp at time zone 'America/New_York' and ${col} < ('${day}'::date + 1)::timestamp at time zone 'America/New_York'`;

export const EVENT_KINDS = [
  "signed_in",
  "work_order_opened",
  "packet_opened",
  "page_ready",
  "check_in_saved",
  "check_in_failed",
  "file_opened",
  "file_removed",
];

/**
 * Has this kind EVER been recorded? The guard against reading a zero as a fact.
 *
 * SCOPED, SINCE 2026-09-28, AND THE UNSCOPED VERSION WAS ACTIVELY MISLEADING.
 * Until today this asked one question — "anywhere in this database" — and the
 * marker it printed said "recorded HERE". Those are different questions, and on
 * 2026-09-27 they gave different answers for the first time: golden-path run 1
 * recorded work_order_opened, packet_opened and page_ready in the SYNTHETIC
 * tenant, which silently removed the UNEXERCISED marker from **Brothers Metal
 * Roofing's** report — a tenant where those kinds have still never fired. BMR's
 * zeros began reading as measurements on the strength of activity in a disposable
 * test tenant. Measured, not reasoned: BMR's 2026-10-26 report printed "0 of 0
 * crew opened a work order" with no marker at all.
 *
 * A counter is now graded in three states, because two could not express it:
 *   fired here      — the zero is a real measurement of this tenant
 *   fired elsewhere — the path works, but nothing in THIS tenant has used it
 *   fired nowhere   — the zero measures nothing at all
 */
function kindCounts(q, where) {
  const rows = list(q, `select event || '=' || count(*) from public.field_events ${where} group by event`);
  const seen = Object.fromEntries(rows.map((r) => r.split("=")).map(([k, v]) => [k, Number(v)]));
  return Object.fromEntries(EVENT_KINDS.map((k) => [k, seen[k] ?? 0]));
}

/** Anywhere in this database. */
export function everSeen(q) {
  return kindCounts(q, "");
}

/** In THIS tenant only — what the printed marker actually claims. */
export function everSeenInOrg(q, org) {
  return kindCounts(q, `where org_id = '${org}'`);
}

/** Containers: the denominators every count below is read against. */
export function containers(q, org, day) {
  const tenantsTotal = num(q, `select count(*) from public.organizations`);
  const tenantsField = num(q, `select count(*) from public.tenant_modules where module_key = 'field' and enabled`);
  const crew = list(q, `select user_id from public.org_members where org_id = '${org}' and role = 'field'`);
  const liveTrade = num(q, `select count(*) from public.work_orders where org_id = '${org}' and kind = 'trade' and voided_at is null`);
  const scheduled = list(
    q,
    `select distinct w.id from public.work_orders w join public.schedule_blocks b on b.work_order_id = w.id
      where w.org_id = '${org}' and w.kind = 'trade' and w.voided_at is null
        and '${day}'::date between b.start_date and b.end_date`
  );
  return {
    tenants: count(tenantsField, tenantsTotal, "tenants have the field module enabled"),
    crew,
    crewCount: count(crew.length, crew.length, `crew (role=field) in this tenant`),
    scheduled,
    scheduledCount: count(scheduled.length, liveTrade, "live trade work orders in this tenant are scheduled for this day"),
  };
}

const inSet = (ids) => (ids.length ? ids.map((i) => `'${i}'`).join(",") : `'00000000-0000-0000-0000-000000000000'`);

/**
 * The funnel, per person, against the crew roster as denominator.
 * Stages are ordered: each is a strictly later thing to have happened.
 */
export function funnel(q, org, day, crew) {
  const w = dayWindow(day, "occurred_at");
  const people = (sql) => list(q, sql).length;
  const ev = (cond) => `select distinct actor_id from public.field_events where org_id = '${org}' and ${w} and ${cond}`;
  const roster = inSet(crew);
  const crewOnly = (cond) => `${ev(cond)} and actor_id in (${roster})`;
  return {
    signedIn: count(people(crewOnly(`event = 'signed_in'`)), crew.length, "crew signed in"),
    opened: count(people(crewOnly(`event in ('work_order_opened','packet_opened')`)), crew.length, "crew opened a work order"),
    usable: count(people(crewOnly(`event = 'page_ready'`)), crew.length, "crew had the page become usable on their phone"),
    // A check-in is the ordinary record; a QC attestation counts too. The UNION
    // is the point: two people recording two different things are two people.
    recorded: count(
      people(
        `select distinct actor_id from (
           select actor_id from public.field_events
            where org_id = '${org}' and ${w} and event = 'check_in_saved' and actor_id in (${roster})
           union
           select actor_id from public.qc_items
            where org_id = '${org}' and ${dayWindow(day, "occurred_at")} and cleared_at is null and actor_id in (${roster})
         ) both_kinds`
      ),
      crew.length,
      "crew recorded something"
    ),
    // Anyone NOT on the crew roster who produced events: office, agency, me.
    offRoster: count(
      people(`${ev(`true`)} and actor_id not in (${roster})`),
      people(ev(`true`)),
      "people producing events are not on this tenant's crew roster"
    ),
  };
}

/** Furthest stage each person reached, so "where they stopped" is answerable. */
export function whereTheyStopped(q, org, day) {
  const w = dayWindow(day, "occurred_at");
  return list(
    q,
    `select left(actor_id::text, 8) || ' ' ||
       case
         when bool_or(event = 'check_in_saved') then 'recorded a check-in'
         when bool_or(event = 'page_ready') then 'page became usable, recorded nothing'
         when bool_or(event in ('work_order_opened','packet_opened')) then 'opened a work order, page never reported usable'
         when bool_or(event = 'signed_in') then 'signed in, never opened a work order'
         else 'produced only other events'
       end || ' (' || count(*) || ' events)'
     from public.field_events where org_id = '${org}' and ${w} group by actor_id order by 1`
  );
}

/** Per scheduled work order: was it opened, and was anything recorded on it? */
export function perWorkOrder(q, org, day, scheduled) {
  const w = dayWindow(day, "occurred_at");
  return scheduled.map((wo) => ({
    wo: wo.slice(0, 8),
    opens: num(q, `select count(*) from public.field_events where org_id = '${org}' and work_order_id = '${wo}' and event in ('work_order_opened','packet_opened') and ${w}`),
    checkIns: num(q, `select count(*) from public.check_ins where org_id = '${org}' and work_order_id = '${wo}' and ${dayWindow(day, "created_at")}`),
    qcLive: num(q, `select count(*) from public.qc_items where org_id = '${org}' and work_order_id = '${wo}' and cleared_at is null`),
  }));
}

// ── A4.8's three named measures: opens · completion rate · time-to-complete ───
//
// A RATE WITH A ZERO DENOMINATOR IS UNDEFINED, NOT 0%. Those are different claims
// about a roof: 0% says the crew was given work and finished none of it; undefined
// says nobody was given any. Rendering the second as the first is how a pilot gets
// reported as a failure when it was never run — and on 2026-09-29 every one of
// these is at or near that boundary, so the distinction is not hypothetical.
//
// WHICH DENOMINATOR, STATED RATHER THAN ASSUMED. Completion is measured against
// TRADE WORK ORDERS SCHEDULED FOR THE DAY, because that is the work the office
// actually assigned and it is recorded. It is NOT measured against A4.1's daily
// objective, which is not built — if it were, the denominator would not exist at
// all rather than being zero. Both cases render undefined here; they are different
// reasons and the report says which.
export const UNDEFINED = Object.freeze({ undefined: true });
export const isUndefined = (r) => r === UNDEFINED || (r && r.undefined === true);

/** A rate that refuses to invent a denominator. */
export const rate = (numerator, denominator, container, why) =>
  denominator > 0
    ? { pct: Math.round((numerator / denominator) * 1000) / 10, n: numerator, of: denominator, container }
    : { undefined: true, n: numerator, of: 0, container, why };

export const fmtRate = (r) =>
  isUndefined(r)
    ? `UNDEFINED — ${r.why} (no denominator: 0 ${r.container}). Not 0%.`
    : `${r.pct}%  (${r.n} of ${r.of} ${r.container})`;

/** Opens on the day, with the work that was actually assigned as the container. */
export function opens(q, org, day, scheduled) {
  const w = dayWindow(day, "occurred_at");
  const opened = scheduled.length
    ? num(q, `select count(distinct work_order_id) from public.field_events
              where org_id = '${org}' and ${w} and event in ('work_order_opened','packet_opened')
                and work_order_id in (${inSet(scheduled)})`)
    : 0;
  const total = num(q, `select count(*) from public.field_events where org_id = '${org}' and ${w} and event in ('work_order_opened','packet_opened')`);
  return {
    scheduledOpened: rate(opened, scheduled.length, "trade work orders scheduled for this day", "no trade work order was scheduled"),
    totalOpens: count(total, total, "opens recorded in this tenant on this day (any work order)"),
  };
}

/** Completion: a scheduled work order counts as completed when it has a check-in that day. */
export function completionRate(q, org, day, scheduled) {
  const done = scheduled.length
    ? num(q, `select count(distinct work_order_id) from public.check_ins
              where org_id = '${org}' and ${dayWindow(day, "created_at")} and work_order_id in (${inSet(scheduled)})`)
    : 0;
  return rate(done, scheduled.length, "trade work orders scheduled for this day", "no trade work order was scheduled");
}

/**
 * Time-to-complete: first open → first check-in, per (actor, work order), in minutes.
 * UNDEFINED with no pairs — a median of nothing is not zero.
 */
export function timeToComplete(q, org, day) {
  const w = dayWindow(day, "occurred_at");
  const rows = list(
    q,
    `select round(extract(epoch from (c.first_check_in - o.first_open)) / 60.0)::text
     from (select actor_id, work_order_id, min(occurred_at) as first_open from public.field_events
            where org_id = '${org}' and ${w} and event in ('work_order_opened','packet_opened')
            group by actor_id, work_order_id) o
     join (select actor_id, work_order_id, min(occurred_at) as first_check_in from public.field_events
            where org_id = '${org}' and ${w} and event = 'check_in_saved'
            group by actor_id, work_order_id) c
       on c.actor_id = o.actor_id and c.work_order_id = o.work_order_id
     where c.first_check_in >= o.first_open`
  ).map(Number).filter((n) => Number.isFinite(n)).sort((a, b) => a - b);
  if (rows.length === 0) {
    return { undefined: true, n: 0, of: 0, container: "open→check-in pairs on this day", why: "no work order was both opened and checked in by the same person" };
  }
  const mid = Math.floor(rows.length / 2);
  const median = rows.length % 2 ? rows[mid] : (rows[mid - 1] + rows[mid]) / 2;
  return { median, n: rows.length, of: rows.length, container: "open→check-in pairs on this day", min: rows[0], max: rows[rows.length - 1] };
}

export const fmtDuration = (t) =>
  isUndefined(t)
    ? `UNDEFINED — ${t.why} (0 ${t.container}). Not zero minutes.`
    : `median ${t.median} min  (${t.n} ${t.container}; range ${t.min}–${t.max} min)`;
