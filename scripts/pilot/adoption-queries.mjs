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

/** Has this kind EVER been recorded here? The guard against reading a zero as a fact. */
export function everSeen(q) {
  const rows = list(q, `select event || '=' || count(*) from public.field_events group by event`);
  const seen = Object.fromEntries(rows.map((r) => r.split("=")).map(([k, v]) => [k, Number(v)]));
  return Object.fromEntries(EVENT_KINDS.map((k) => [k, seen[k] ?? 0]));
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
