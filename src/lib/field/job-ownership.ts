// WHOSE JOB IS THIS? Track U, U-W1.41, 2026-09-28. Client-safe: no server imports.
//
// THE PROPERTY: a crew member opening the app sees their work first and can
// tell, without being told a rule, which work is theirs.
//
// THREE STATES, NOT TWO, and the third is the one that matters today:
//   mine        this crew is assigned to it
//   other_crew  somebody else is assigned to it — NOT "does not exist"
//   unknown     nobody has recorded who is on it, or we cannot tell
//
// A JOB THAT BELONGS TO ANOTHER CREW IS NOT A JOB THAT DOES NOT EXIST. Hiding
// it would be the ownership version of the defect this build keeps closing:
// "cannot see" rendered as "is not there". A roofer who drives past a job their
// own company is on and cannot find it in the app stops trusting the app.
//
// AND `unknown` IS NOT `other_crew`. MEASURED 2026-09-28, both orgs with the
// field module: work_order_crew_assignments holds ZERO rows, crew_people ZERO,
// crew_memberships ZERO. So TODAY every job is `unknown`, and a screen that
// grouped on that would tell every crew member that none of the work is theirs
// — which is false, and worse than saying nothing. When nothing is known, this
// module returns ONE ungrouped list and the screen makes no claim at all.
//
// Track S owns the scoping and starts today. `ownershipOf` is the seam: when
// the assignment read lands, it is one function, and everything below already
// renders the answer.

export type JobOwnership = "mine" | "other_crew" | "unknown";

/**
 * U-W1.43 (2026-09-29) — THE THIRD STATE, and it is the one that can do harm.
 *
 * S is building crew scoping BEHIND A SWITCH THAT DEFAULTS OFF, and its refusal
 * path returns a NAMED REFUSAL rather than an empty list when a member has no
 * assignments. So there are three situations, not two:
 *
 *   scoping_off   nobody is scoping anything. No claim is possible and none is
 *                 made: one flat list, as today.
 *   scoped        we know who is on what. Lead with the reader's own work.
 *   none_assigned SCOPING IS ON AND NOTHING IS ASSIGNED TO THIS PERSON.
 *
 * THE THIRD MUST NOT RENDER AS "NO WORK TODAY", and that is the whole reason it
 * exists as its own state. The jobs are there. The org is working. What is
 * absent is an ASSIGNMENT, which is a fact about the schedule and not about the
 * roofs — and a crew member told "nothing scheduled" when five jobs are running
 * will either sit at home or stop believing the screen. Both are worse than the
 * truth, which is short: nothing is assigned to you yet, here is what the
 * company has on.
 */
export type OwnershipRead<T> =
  | { state: "scoping_off" }
  | { state: "scoped"; ownershipOf: (job: T) => JobOwnership }
  | { state: "none_assigned" };

export type OwnershipGrouping<T> =
  /** Something is known: the screen can lead with the reader's own work. */
  | { kind: "grouped"; mine: T[]; others: T[]; unknown: T[] }
  /** Nothing is known about any of them. No groups, no claim, no headings. */
  | { kind: "flat"; all: T[] }
  /** Scoping is on and this person has none. The jobs still render. */
  | { kind: "none_assigned"; all: T[] };

/** The read, resolved to what the screen renders. */
export function resolveOwnership<T>(jobs: T[], read: OwnershipRead<T>): OwnershipGrouping<T> {
  if (read.state === "scoping_off") return { kind: "flat", all: jobs };
  if (read.state === "none_assigned") return { kind: "none_assigned", all: jobs };
  return groupByOwnership(jobs, read.ownershipOf);
}

/**
 * What the screen SAYS when scoping is on and this person has nothing. Said in
 * one sentence, above jobs that are still listed — never instead of them.
 */
export const NONE_ASSIGNED_HEADING = "Nothing assigned to you yet";
export const NONE_ASSIGNED_DETAIL =
  "These are the jobs your company has on. Ask the office which one is yours.";

export function groupByOwnership<T>(jobs: T[], ownershipOf: (job: T) => JobOwnership): OwnershipGrouping<T> {
  const mine = jobs.filter((j) => ownershipOf(j) === "mine");
  const others = jobs.filter((j) => ownershipOf(j) === "other_crew");
  const unknown = jobs.filter((j) => ownershipOf(j) === "unknown");
  // Nothing known about ANY of them -> one list. The screen says nothing it
  // cannot back, which today is everything about ownership.
  if (mine.length === 0 && others.length === 0) return { kind: "flat", all: jobs };
  return { kind: "grouped", mine, others, unknown };
}

/**
 * The headings. "Yours" leads because the property is that a person sees their
 * work FIRST; the others are present and quieter, never absent.
 *
 * `unknown` inside a grouped list gets its own heading rather than being swept
 * in with somebody else's — a job nobody has crewed yet is work that may still
 * become theirs, and a crew member who can see that can ask for it.
 */
export const OWNERSHIP_HEADING: Record<"mine" | "others" | "unknown", string> = {
  mine: "Yours",
  others: "Other crews",
  unknown: "No crew recorded yet",
};
