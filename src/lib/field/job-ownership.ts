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

export type OwnershipGrouping<T> =
  /** Something is known: the screen can lead with the reader's own work. */
  | { kind: "grouped"; mine: T[]; others: T[]; unknown: T[] }
  /** Nothing is known about any of them. No groups, no claim, no headings. */
  | { kind: "flat"; all: T[] };

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
