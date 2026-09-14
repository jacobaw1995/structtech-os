/**
 * THE HOME SCREEN'S MODEL — U-W1.13, 2026-09-14.
 *
 * Property (from the controller, not a layout): A PERSON WHO SIGNS IN SHOULD SEE
 * WHAT NEEDS THEM TODAY, WITHOUT NAVIGATING TO FIND IT.
 *
 * Two hard constraints shape everything in this file:
 *
 *  A. HONEST WHEN EMPTY. Every section reports one of FOUR states, and the
 *     states are never merged:
 *       unavailable  — the read failed. Not the same as nothing.
 *       none_entered — the table holds nothing for this tenant yet.
 *       clear        — there is data, and none of it needs attention.
 *       attention    — there are items.
 *     "Nothing needs you" is only ever said when there is something on record
 *     that could have needed you. A zero over an empty table is not a clean bill.
 *
 *  B. CAPABILITY FROM THE SERVER. What a section SHOWS is decided by
 *     has_capability() reads, and what it COUNTS is whatever the caller's own
 *     RLS returns — never a local role list. Sections gated by a capability the
 *     caller lacks are not rendered at all (a rendered zero would say "none
 *     exist" when the truth is "not yours to see").
 *
 *     AND NO MONEY, STRUCTURALLY. The home queries do not SELECT a single money
 *     column — not deals.value, not estimates.subtotal or presented_total. A
 *     rule that says "don't render the amount" can be broken by the next edit;
 *     a column that was never fetched cannot be leaked from this page.
 *
 * "NEEDS YOU" vs "FOR YOUR INFORMATION" is also a server read. An item is put
 * in front of someone as needing THEM only if they hold the capability to act on
 * it. A crew member can read that a purchase order is still a draft; only a
 * holder of manage_purchasing is told it needs them.
 */

export type SectionState = "unavailable" | "none_entered" | "clear" | "attention";

export type Caps = {
  view_financials: boolean;
  view_estimates: boolean;
  schedule: boolean;
  manage_purchasing: boolean;
  edit_leads: boolean;
};

export type AttentionItem = {
  key: string;
  /** Plain statement of the fact. No inferred cause. */
  text: string;
  /** Where it is resolved, when the caller can open that place. */
  href: string | null;
  /** True only when the caller holds the capability to act on it. */
  needsYou: boolean;
};

export type Section = {
  id: "schedule" | "materials" | "jobs" | "estimates" | "pipeline";
  title: string;
  state: SectionState;
  /** The count the section is ABOUT — its denominator. Null when unavailable. */
  onRecord: number | null;
  onRecordLabel: string;
  items: AttentionItem[];
  /** Context that is true but is not a task (e.g. stage spread). */
  notes: string[];
};

export function stateOf(onRecord: number | null, attention: number): SectionState {
  if (onRecord === null) return "unavailable";
  if (onRecord === 0) return "none_entered";
  return attention > 0 ? "attention" : "clear";
}

/** Today's calendar date in the project's timezone (CLAUDE.md: never UTC). */
export function todayInNewYork(now = new Date()): string {
  // en-CA formats as YYYY-MM-DD.
  return now.toLocaleDateString("en-CA", { timeZone: "America/New_York" });
}

export function plural(n: number, one: string, many = `${one}s`): string {
  return `${n} ${n === 1 ? one : many}`;
}
