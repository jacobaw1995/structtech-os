// READY-BY, ONE VOCABULARY FOR BOTH AUDIENCES. Track U, U-W1.22, 2026-09-19.
// Client-safe: no server imports.
//
// The four SOURCES are Track S's (`material_items.ready_by_source`): a date set by
// hand, a date derived from live purchase-order promises, an ORPHANED date whose
// order is gone, and "not readable". Their office wording was written for the PO
// line (U-W1.12) and is moved here unchanged so the crew screen reuses the same
// vocabulary instead of a second one — the crew sentences below say the same four
// things in the words a roof needs.
//
// A DATE IS NOT A STATE. "2026-10-20" answers nothing on its own: a crew needs to
// know whether the material is ready, not yet, undated, or standing on a date
// nothing backs. So the date is folded with today's New York date into a state,
// and the state carries the sentence.

export type ReadyByState =
  | { kind: "ready"; on: string }
  | { kind: "not_yet"; on: string; days: number }
  | { kind: "no_date" }
  | { kind: "orphaned"; on: string | null }
  | { kind: "source_unreadable"; on: string | null };

export type ReadyByInput = { ready_by: string | null; ready_by_source: string | null };

/** Date-only arithmetic in UTC so day-diffing two "YYYY-MM-DD" strings cannot shift. */
function toDays(dateStr: string): number {
  const [y, m, d] = dateStr.split("-").map(Number);
  return Date.UTC(y, m - 1, d) / 86_400_000;
}

/**
 * `todayIso` is the NEW YORK calendar date (see todayInNewYork) — never the
 * server's UTC date, which rolls over at 8 PM EDT and would tell a crew that
 * tomorrow's delivery is already late.
 */
export function readyByState(item: ReadyByInput, todayIso: string): ReadyByState {
  // ORPHANED FIRST, even when a date is present: the date is the last thing an
  // order promised before that order was cancelled or removed. Reading it as
  // "ready" would be reading a number nothing stands behind.
  if (item.ready_by_source === "orphaned") return { kind: "orphaned", on: item.ready_by };
  if (item.ready_by === null) return { kind: "no_date" };
  if (item.ready_by_source !== "manual" && item.ready_by_source !== "purchase_order") {
    return { kind: "source_unreadable", on: item.ready_by };
  }
  const days = toDays(item.ready_by) - toDays(todayIso);
  return days <= 0 ? { kind: "ready", on: item.ready_by } : { kind: "not_yet", on: item.ready_by, days };
}

/** What a crew is told. Short, because it is read one-handed in daylight. */
export function crewReadyByText(state: ReadyByState): { label: string; detail: string } {
  switch (state.kind) {
    case "ready":
      return { label: "Ready", detail: `Ready since ${state.on}.` };
    case "not_yet":
      return {
        label: "Not yet ready",
        detail: `Ready ${state.on} — ${state.days === 1 ? "tomorrow" : `in ${state.days} days`}.`,
      };
    case "no_date":
      return { label: "No date recorded", detail: "Nobody has recorded when this will be ready." };
    case "orphaned":
      return {
        label: "Date has no order",
        detail: state.on
          ? `${state.on} was the last date an order promised, but that order is gone. Treat it as unconfirmed and ask the office.`
          : "The order this date came from is gone. Ask the office when it will be ready.",
      };
    case "source_unreadable":
      return {
        label: "Date not understood",
        detail: state.on
          ? `${state.on} is recorded, but where it came from is not something this screen understands. Ask the office.`
          : "Where this date came from is not something this screen understands. Ask the office.",
      };
  }
}

/**
 * What the OFFICE is told about where a date came from — moved verbatim from
 * PoLineRow (U-W1.12), which now imports it from here. Two audiences, one
 * vocabulary, one place to change it.
 */
export function officeReadyBySourceText(source: string | null): string {
  switch (source) {
    case "purchase_order":
      return " — from the promised dates on this and any other live order";
    case "orphaned":
      return (
        " — the last date an order promised, but that order has since been cancelled or removed." +
        " Nobody set this date and nothing currently backs it, yet the schedule still uses it." +
        " Record a new promise on a live order, or set the date on the material item."
      );
    case "manual":
      return " — set by hand on the material item; no live order promise governs it";
    case null:
      return " — where this date came from could not be read";
    default:
      return ` — source not recognised by this page ("${source}")`;
  }
}
