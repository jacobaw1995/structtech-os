// WHY A CREW WRITE DID NOT LAND, AND WHAT A CREW'S STATE IS. Track U, U-W1.23,
// 2026-09-19. Client-safe: no server imports.
//
// TWO RULES MEET HERE.
//
// 1. CONTROLLER RULING 2026-09-15 — a URL parameter is a CODE that gets looked
//    up; no URL parameter is ever rendered as text. So the redirect carries a
//    hint code and the sentence comes from this map.
// 2. TODAY'S DIRECTIVE — "every refusal shown is S's words, via its hint code.
//    Do not write a second copy." So the sentences below are Track S's own,
//    copied from the function bodies (read from pg_proc 2026-09-19), not
//    reworded.
//
// WHAT IS LOST BETWEEN THE TWO, SAID RATHER THAN HIDDEN. Four of S's raises
// interpolate a value:
//     crew "%" is archived — restore it first
//     % is archived — restore them first
//     this crew is assigned to % work order(s) — …
//     field not writable: %
// A code cannot carry the value and rule 1 forbids passing the text, so the
// sentences below drop the interpolation. The screen already shows which crew
// or person the control belonged to, so the name is on screen either way.
//
// ONE CODE, FOUR SENTENCES — a real collision, reported to S. `not_found` is
// raised by crew_assert_can_manage ("not found or not accessible"),
// add_crew_member ("that person is not in this workspace"),
// assign_crew_to_work_order ("work order not found or not accessible") and
// crew_name_from_crew ("that crew is not in this workspace"). The code cannot
// tell them apart, so the most general of the four is used — and it is S's,
// not a paraphrase. crew_assert_can_manage runs first in every one of these
// RPCs, so it is also the likeliest source.

export type CrewHint =
  // Track S's hint codes, exhaustive as of 2026-09-19.
  | "not_found"
  | "no_schedule_capability"
  | "name_required"
  | "crew_name_taken"
  | "person_archived"
  | "crew_archived"
  | "dates_invalid"
  | "language_invalid"
  | "patch_invalid"
  | "crew_in_use"
  | "login_not_member"
  | "login_already_a_person"
  // OURS, and deliberately not refusals: these two describe THIS surface's own
  // failure to get an answer, which S has no sentence for because S never saw
  // the request.
  | "save_failed"
  | "save_unconfirmed";

export const CREW_HINT_COPY: Record<CrewHint, string> = {
  not_found: "Not found or not accessible.",
  no_schedule_capability: "Your role cannot manage crews in this workspace.",
  name_required: "A name is required.",
  crew_name_taken: "A crew with that name already exists in this workspace.",
  person_archived: "That person is archived — restore them first.",
  crew_archived: "That crew is archived — restore it first.",
  dates_invalid: "Choose a first and last day, with the last on or after the first.",
  language_invalid: 'Language must be a code like "en" or "es-MX".',
  patch_invalid: "That change could not be applied.",
  crew_in_use: "This crew is assigned to work orders — unassign it, or archive the crew instead.",
  login_not_member: "That login is not a member of this workspace.",
  login_already_a_person: "That login already belongs to another person in this workspace.",
  save_failed: "That wasn't saved. Nothing was changed — please try again.",
  save_unconfirmed: "We couldn't confirm that was saved. Check the roster below before trying again.",
};

export function isCrewHint(v: unknown): v is CrewHint {
  return typeof v === "string" && Object.prototype.hasOwnProperty.call(CREW_HINT_COPY, v);
}

/**
 * PostgREST surfaces a raise's HINT as `error.hint`, so no message-matching is
 * needed here — unlike classifyFieldError, which had to pattern-match because
 * the field functions carry no hints.
 *
 * THE GAP, REPORTED NOT PAPERED OVER: work_order_crew_assignments_validate's
 * three raises carry NO hint —
 *     'a crew can only be assigned to a work order in its own workspace'
 *     'crews are assigned to trade work orders, not to the master — …'
 *     'that work order is voided — a crew cannot be assigned to it'
 * They land here as `save_failed`, which says nothing was saved and is true,
 * but does not say why. The assign picker only offers live TRADE work orders
 * in this org, so all three are unreachable from this screen — a mitigation,
 * not a fix. S owns the hints.
 */
export function classifyCrewError(error: { code?: string; hint?: string | null }): CrewHint {
  if (!error.code) return "save_unconfirmed"; // no answer from the database at all
  return isCrewHint(error.hint) ? error.hint : "save_failed";
}

// ── STATES, NOT BLOCKS ────────────────────────────────────────────────────────
// SCOPE §2.8 and today's condition: availability is a VISIBLE STATE, never a
// block. assign_crew_to_work_order returns vehicle_state and availability_state
// and refuses on NEITHER; nothing on this surface refuses on them either. The
// two vocabularies are Track S's, read from crew_assignment_states'
// definition — this file adds no fifth word to either.

export type VehicleState = "crew_has_no_members" | "has_vehicle" | "vehicle_not_recorded" | "no_vehicle";
export type AvailabilityState = "crew_has_no_members" | "not_scheduled" | "some_unavailable" | "all_available";

export const VEHICLE_STATE_COPY: Record<VehicleState, string> = {
  crew_has_no_members: "No members yet, so no vehicle either.",
  has_vehicle: "Someone on this crew has a vehicle.",
  vehicle_not_recorded: "Nobody on this crew has a vehicle recorded — it may or may not be a problem.",
  no_vehicle: "Nobody on this crew has a vehicle.",
};

export const AVAILABILITY_STATE_COPY: Record<AvailabilityState, string> = {
  crew_has_no_members: "This crew has no members.",
  not_scheduled: "Not scheduled yet, so nobody's time off can clash with it.",
  some_unavailable: "Somebody on this crew is away during the scheduled days.",
  all_available: "Everyone on this crew is available for the scheduled days.",
};

/** Whether a state is worth drawing attention to. NOT whether it stops anything. */
export function needsAttention(v: VehicleState | AvailabilityState): boolean {
  return v === "crew_has_no_members" || v === "some_unavailable" || v === "no_vehicle";
}
