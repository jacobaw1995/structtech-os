// THE ROSTER, AS fetch_crew_roster RETURNS IT. Track U, U-W1.23, 2026-09-19.
// Client-safe: no server imports.
//
// ONE READ FOR THE WHOLE SCREEN. fetch_crew_roster(p_org_id) returns a single
// jsonb document — people (with their crew ids and their live time off) and
// crews (with their members and their assignments). There is no per-person or
// per-crew follow-up query on this page, by construction: everything the roster
// renders comes out of this one document, plus ONE list read of
// crew_assignment_states for the states that depend on the schedule.
//
// A jsonb return has no generated row type, so these types are hand-written —
// the one case where that is not a fifth mirror, because there is no generated
// type to mirror. They were written against the function body read from
// pg_proc on 2026-09-19, and `parseRoster` below refuses rather than guesses
// when what comes back does not match them.

import type { VehicleState, AvailabilityState } from "@/lib/crews/crew-states";

export type RosterUnavailability = {
  id: string;
  starts_on: string;
  ends_on: string;
  reason: string | null;
};

export type RosterPerson = {
  id: string;
  full_name: string;
  phone: string | null;
  preferred_language: string | null;
  skills: string[] | null;
  /** Three-valued ON PURPOSE: null is "not recorded", which is not "no". */
  has_vehicle: boolean | null;
  vehicle_note: string | null;
  has_login: boolean;
  archived: boolean;
  crew_ids: string[];
  /** Only time off that has not already ended — the function filters on ends_on >= today NY. */
  unavailable: RosterUnavailability[];
};

export type RosterCrew = {
  id: string;
  name: string;
  archived: boolean;
  members: { person_id: string; is_lead: boolean }[];
  assignments: { assignment_id: string; work_order_id: string; task: string | null }[];
};

export type Roster = { people: RosterPerson[]; crews: RosterCrew[] };

/** The schedule-dependent half, read from crew_assignment_states (S's view). */
export type AssignmentState = {
  assignment_id: string;
  work_order_id: string;
  crew_id: string;
  trade: string | null;
  task: string | null;
  start_date: string | null;
  end_date: string | null;
  members: number | null;
  vehicle_state: VehicleState | null;
  availability_state: AvailabilityState | null;
  unavailable_members: number | null;
};

/**
 * A ROSTER THAT COULD NOT BE READ IS NOT AN EMPTY ROSTER. fetch_crew_roster
 * returns SQL NULL — not an empty document — when the caller is not a member of
 * the org, because its body is a bare `case when p_org_id in (my_org_ids())`
 * with no else. Rendering that as "no crews yet" would tell an office user
 * their roster is empty when what actually happened is that the read was
 * refused. Null in, null out, and the page says which.
 */
export function parseRoster(data: unknown): Roster | null {
  if (!data || typeof data !== "object") return null;
  const d = data as { people?: unknown; crews?: unknown };
  if (!Array.isArray(d.people) || !Array.isArray(d.crews)) return null;
  return { people: d.people as RosterPerson[], crews: d.crews as RosterCrew[] };
}

/**
 * WHERE A PERSON IS, TODAY. Derived from S's data (crew_person_unavailability),
 * not a second copy of S's crew-level vocabulary — S has no per-person state,
 * because the states view answers per ASSIGNMENT. `todayIso` is the New York
 * date; string comparison is safe on ISO dates and cannot drift a timezone.
 */
export type PersonAvailability =
  | { kind: "available" }
  | { kind: "away_today"; until: string; reason: string | null }
  | { kind: "away_later"; from: string; until: string; reason: string | null };

export function personAvailability(person: RosterPerson, todayIso: string): PersonAvailability {
  const now = person.unavailable.find((u) => u.starts_on <= todayIso && u.ends_on >= todayIso);
  if (now) return { kind: "away_today", until: now.ends_on, reason: now.reason };
  // The function returns these ordered by starts_on, so the first future entry
  // is the next one.
  const next = person.unavailable.find((u) => u.starts_on > todayIso);
  if (next) return { kind: "away_later", from: next.starts_on, until: next.ends_on, reason: next.reason };
  return { kind: "available" };
}

export function personAvailabilityText(a: PersonAvailability): string {
  switch (a.kind) {
    case "available":
      return "No time off recorded.";
    case "away_today":
      return `Away today, through ${a.until}${a.reason ? ` — ${a.reason}` : ""}.`;
    case "away_later":
      return `Away ${a.from} to ${a.until}${a.reason ? ` — ${a.reason}` : ""}.`;
  }
}

/** "Yes" / "No" / "Not recorded" — the third is not the second. */
export function vehicleText(person: RosterPerson): string {
  if (person.has_vehicle === true) return person.vehicle_note ? `Vehicle — ${person.vehicle_note}` : "Vehicle";
  if (person.has_vehicle === false) return "No vehicle";
  return "Vehicle not recorded";
}
