// IS THE STORED MATERIALS WARNING STILL TRUE? Track U, U-W1.51, 2026-10-04.
// Client-safe: no server imports.
//
// WHAT HAPPENED. At 00:32:49 EDT on 2026-10-04 a roofer's phone said materials
// were not ready until 2026-10-20, on a job whose material ready_by had been
// set to 2026-10-04 four minutes earlier.
//
// THE MECHANISM, verified against the applied database rather than from that
// one block: `schedule_blocks.ready_by_conflict` and `ready_by_conflict_reason`
// are COMPUTED AND STORED by `schedule_blocks_ready_by_gate`, a BEFORE trigger
// on `schedule_blocks`. The three triggers on `material_items` are
// take_off_guard, take_off_removed and trim_text — NONE of them touches
// ready_by_conflict. So changing a material never recomputes the blocks that
// gate on it, and the stored sentence keeps whatever it said when the block was
// last written.
//
// THE DURABLE FIX IS A TRIGGER ON material_items AND IT IS NOT OURS. That is a
// migration, it is Track S's, and under rule 15 it means naming every function
// that reads those two columns. Two days before a pilot is not when the surface
// applies schema changes.
//
// WHAT THE SURFACE CAN DO HONESTLY: notice that the stored answer is older than
// the facts it was computed from, and stop presenting it as current. A stale
// warning renders as "can't tell", NEVER as a date — the same call this build
// has made for an unreadable QC list, an unreadable materials list, an
// unreadable roster and an unreadable trip log.
//
// MEASURED as the real crew account: both tables and both `updated_at` columns
// are readable, so the comparison is available to the screen that needs it.

export type ReadyByFreshness =
  /** The stored warning was computed after the last material change. */
  | { state: "current" }
  /** A material changed after this block was last written. The stored answer may be wrong. */
  | { state: "stale" }
  /** We have no timestamp to compare. Says nothing either way. */
  | { state: "unknown" };

export function readyByFreshness(
  blockUpdatedAt: string | null | undefined,
  latestMaterialUpdatedAt: string | null | undefined
): ReadyByFreshness {
  if (!blockUpdatedAt || !latestMaterialUpdatedAt) return { state: "unknown" };
  const block = Date.parse(blockUpdatedAt);
  const material = Date.parse(latestMaterialUpdatedAt);
  if (Number.isNaN(block) || Number.isNaN(material)) return { state: "unknown" };
  // STRICTLY LATER. A material written in the same instant as the block was
  // part of that recompute, not a change after it.
  return material > block ? { state: "stale" } : { state: "current" };
}

/**
 * What the crew is told when the stored warning cannot be trusted.
 *
 * NO DATE, DELIBERATELY. The stored reason carries one, and repeating it with a
 * hedge in front would be the same wrong date in a softer voice — a roofer
 * reads the date, not the hedge. The sentence says what is known (something
 * changed), what is not (whether it is ready), and what to do.
 */
export const READY_BY_STALE_TEXT =
  "The materials for this job changed after this warning was worked out, so it may be out of date. Check the Materials tab before you count on it.";
