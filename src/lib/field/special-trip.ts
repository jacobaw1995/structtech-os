// SPECIAL TRIPS — the reason vocabulary. Track U, U-W1.31, 2026-09-23.
// Client-safe: no server imports.
//
// A REASON IS A CODE, NEVER FREE TEXT (SCOPE §2.4, and the Build module's
// "Special-trip / exception log with reason codes"). The point of the log is to
// be COUNTED — "we made nine trips back for missing material last month" is a
// number somebody can act on; nine paragraphs in nine check-ins is not. So there
// is no "other, please describe" here: a free-text escape hatch is where a code
// list goes to die, because the hatch is always the fastest button to press.
//
// UNWIRED, DELIBERATELY, AND NOT MOUNTED ANYWHERE.
// Measured 2026-09-23 against the live database: NO trip table, NO trip column,
// NO trip function; the Build Tracker item "Special-trip / exception log with
// reason codes" is `planned`. Track S owns the log. So this file and its panel
// are the SHAPE, ready to mount in one line when the table exists — and the
// panel is deliberately NOT rendered on the crew screen, because a control that
// looks like it records something and does not is the defect we removed from
// the header yesterday (the "Search…" box that announced "Not built yet").
//
// THE TAP BUDGET, measured before building (SCOPE §2.4: two taps, gloves, sun).
// TODAY, from the field Today screen, a crew member records a special trip by
// typing it into the check-in's "Anything blocking?" box:
//     tap 1  the job card          tap 2  the Blockers box
//     + typing                     tap 3  Save check-in
// — 3 taps and free prose, or 4 when the Crew box is not prefilled. AFTER, from
// the job screen: tap 1 opens the reason list, tap 2 is the reason. Two taps,
// and the second tap is the record. From Today it is three, because opening the
// job is itself a tap and a trip belongs to a job.
//
// WHY THE LIST OPENS RATHER THAN SITTING OPEN (which would be ONE tap): a row of
// live buttons on the check-in screen is a row a gloved thumb can fire by
// accident, and an accidental trip in the log is worse than no log — it is a
// number somebody will later defend in a meeting. Two taps is the budget; one
// tap is not a prize worth an unreliable count.

export type SpecialTripReason = {
  code: string;
  label: string;
  /** What it covers, in the crew's words — read once, when choosing. */
  help: string;
};

export const SPECIAL_TRIP_REASONS: SpecialTripReason[] = [
  { code: "material_missing", label: "Material missing or short", help: "What was needed was not on site, or there was not enough of it." },
  { code: "material_wrong", label: "Wrong material", help: "What arrived was not what the job needed." },
  { code: "access", label: "Couldn't get access", help: "Gate locked, nobody home, driveway blocked." },
  { code: "weather", label: "Weather stopped work", help: "Rain, wind or heat sent the crew home." },
  { code: "customer_change", label: "Customer changed something", help: "The homeowner asked for something different once work started." },
  { code: "rework", label: "Going back to fix something", help: "Work already done that has to be redone." },
  { code: "equipment", label: "Equipment or tool problem", help: "A tool, lift or truck stopped the day." },
];

export function isSpecialTripReason(v: unknown): v is string {
  return typeof v === "string" && SPECIAL_TRIP_REASONS.some((r) => r.code === v);
}

export function specialTripReason(code: string): SpecialTripReason | undefined {
  return SPECIAL_TRIP_REASONS.find((r) => r.code === code);
}
