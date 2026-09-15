import type { Database } from "@/lib/supabase/database.types";

// THE TAKE-OFF REVIEW — U-W1.14, 2026-09-14. PURE: rows in, a review out.
//
// Read against Track S's spine (20260914230647_material_take_off_spine), not
// against either materialise path. `take_off_lines` says, per estimate line on a
// job, what was decided, by what, and what became of it; `set_take_off_decision`
// is the one write. Whichever of generate_take_off / materialize_take_off
// survives, both read and write these same facts, so nothing here moves.
//
// THREE UNDECIDED QUESTIONS, NEVER ONE. They have different answers and
// different people answer them:
//   is_material  — nobody has said whether the line is material at all
//   which_trade  — it is material, and no trade is chosen
//   trade_voided — a trade was chosen and that trade has since been voided
// Collapsing them into "needs attention" hides which question is being asked.

export type TakeOffLineRow = Database["public"]["Views"]["take_off_lines"]["Row"];
export type DecisionRow = Pick<
  Database["public"]["Tables"]["take_off_decisions"]["Row"],
  "estimate_line_item_id" | "source" | "decided_by" | "decided_at" | "item_removed_at" | "item_removed_by"
>;
export type TradeRef = { id: string; trade: string | null; voided_at: string | null };

export type ReviewLine = {
  lineId: string;
  description: string;
  quantity: number | null;
  unit: string | null;
  sortOrder: number;
  disposition: "material" | "not_material" | "undecided";
  source: string | null;
  scopeKey: string | null;
  tradeWorkOrderId: string | null;
  tradeState: string | null;
  itemState: string | null;
  materialItemId: string | null;
  materialWorkOrderId: string | null;
  decision: DecisionRow | null;
};

export type Leftover = {
  materialItemId: string;
  materialWorkOrderId: string | null;
  description: string | null;
  quantity: number | null;
  unit: string | null;
  itemState: "estimate_line_deleted" | "line_not_on_job_estimate";
};

export type TakeOffReview = {
  /** Lines on this job's estimate — the denominator for everything below. */
  lines: ReviewLine[];
  estimateStatus: string | null;
  cameAcross: ReviewLine[];
  isMaterial: ReviewLine[];
  whichTrade: ReviewLine[];
  tradeVoided: ReviewLine[];
  decidedNotTakenOff: ReviewLine[];
  removedByHuman: ReviewLine[];
  notMaterial: ReviewLine[];
  leftovers: Leftover[];
  /** Lines whose item_state this file does not know. Shown raw. */
  unrecognised: ReviewLine[];
  liveTrades: TradeRef[];
};

const KNOWN_ITEM_STATES = new Set([
  "matches", "edited_by_human", "estimate_changed", "both_changed", "no_snapshot",
  "item_on_other_trade", "item_without_material_decision", "not_taken_off",
  "removed_by_human", "none",
]);

// An item exists for the line and sits on a trade: every such state the view
// defined on 2026-09-14. A state added later lands in `unrecognised` below and
// is shown with its raw name — never silently dropped.
const ITEM_EXISTS = new Set([
  "matches",
  "edited_by_human",
  "estimate_changed",
  "both_changed",
  "no_snapshot",
  "item_on_other_trade",
  "item_without_material_decision",
]);

export function buildReview(
  rows: TakeOffLineRow[],
  decisions: DecisionRow[],
  trades: TradeRef[]
): TakeOffReview {
  const byLine = new Map(decisions.map((d) => [d.estimate_line_item_id, d] as const));

  // The view is a UNION: rows with an estimate_status are lines on the job's
  // estimate; rows without one are materials whose line is no longer there.
  const lines: ReviewLine[] = rows
    .filter((r) => r.estimate_status !== null && r.estimate_line_item_id !== null)
    .map((r): ReviewLine => ({
      lineId: r.estimate_line_item_id as string,
      description: r.description ?? "",
      quantity: r.quantity,
      unit: r.unit,
      sortOrder: r.sort_order ?? 0,
      disposition:
        r.disposition === "material" || r.disposition === "not_material" ? r.disposition : "undecided",
      source: r.disposition_source,
      scopeKey: r.scope_key,
      tradeWorkOrderId: r.trade_work_order_id,
      tradeState: r.trade_state,
      itemState: r.item_state,
      materialItemId: r.material_item_id,
      materialWorkOrderId: r.material_work_order_id,
      decision: byLine.get(r.estimate_line_item_id as string) ?? null,
    }))
    .sort((a, b) => a.sortOrder - b.sortOrder || a.lineId.localeCompare(b.lineId));

  const leftovers: Leftover[] = rows
    .filter(
      (r) =>
        r.estimate_status === null &&
        r.material_item_id !== null &&
        (r.item_state === "estimate_line_deleted" || r.item_state === "line_not_on_job_estimate")
    )
    .map((r) => ({
      materialItemId: r.material_item_id as string,
      materialWorkOrderId: r.material_work_order_id,
      description: r.description,
      quantity: r.quantity,
      unit: r.unit,
      itemState: r.item_state as Leftover["itemState"],
    }));

  const statuses = Array.from(new Set(rows.map((r) => r.estimate_status).filter(Boolean)));

  return {
    lines,
    estimateStatus: statuses.length === 1 ? (statuses[0] as string) : null,
    cameAcross: lines.filter((l) => l.itemState !== null && ITEM_EXISTS.has(l.itemState)),
    isMaterial: lines.filter((l) => l.disposition === "undecided"),
    whichTrade: lines.filter((l) => l.disposition === "material" && l.tradeState === "undecided"),
    tradeVoided: lines.filter((l) => l.tradeState === "trade_voided"),
    // not_taken_off is also reported for a line whose chosen trade was voided;
    // that line belongs to the voided-trade question, not to "ready".
    decidedNotTakenOff: lines.filter((l) => l.itemState === "not_taken_off" && l.tradeState === "decided"),
    removedByHuman: lines.filter((l) => l.itemState === "removed_by_human"),
    notMaterial: lines.filter((l) => l.disposition === "not_material"),
    leftovers,
    unrecognised: lines.filter((l) => l.itemState === null || !KNOWN_ITEM_STATES.has(l.itemState)),
    liveTrades: trades.filter((t) => t.voided_at === null),
  };
}

/** What each item state IS, in words. One sentence per state, never merged. */
export function itemStateText(line: ReviewLine, tradeName: (id: string | null) => string): string {
  switch (line.itemState) {
    case "matches":
      return "Matches the estimate line it came from.";
    case "edited_by_human":
      return "Changed on the trade since it was taken off. The estimate line has not changed.";
    case "estimate_changed":
      return "The estimate line has changed since it was taken off. The material has not.";
    case "both_changed":
      return "Both the material and the estimate line have changed since it was taken off.";
    case "no_snapshot":
      return "Taken off before this system kept a copy of the line, so whether either side has changed cannot be told.";
    case "item_on_other_trade":
      return `The material is on ${tradeName(line.materialWorkOrderId)}, but the decision puts this line on ${tradeName(line.tradeWorkOrderId)}.`;
    case "item_without_material_decision":
      return "A material exists for this line, but the line is not decided material.";
    case "not_taken_off":
      return "Decided material on a trade. No material has been created from it yet.";
    case "removed_by_human":
      return "Its material was deleted by a person. It will not be re-created on its own.";
    default:
      return "";
  }
}

/**
 * Where a decision came from. `backfill` gets its own sentence on the
 * controller's instruction: it is INFERRED from a take-off tick made before
 * decisions were recorded, and must not read as a choice someone made.
 */
export function sourceText(line: ReviewLine, memberName: (id: string | null) => string | null): string | null {
  const when = line.decision?.decided_at ? nyDate(line.decision.decided_at) : null;
  const who = memberName(line.decision?.decided_by ?? null);
  switch (line.source) {
    case "human":
      return `Decided by ${who ?? "a person whose name is not recorded"}${when ? ` on ${when}` : ""}.`;
    case "generate_take_off":
      return `Recorded when ${who ?? "a person whose name is not recorded"} ticked this line in a take-off${when ? ` on ${when}` : ""}.`;
    case "backfill":
      return `Inferred, not chosen. This line was carried onto a trade by a take-off${when ? ` on ${when}` : ""}, before decisions were recorded, so the system filled in "material". Nobody decided it.`;
    case "tenant_config":
      return `Set by this workspace's take-off rule${line.scopeKey ? ` for "${line.scopeKey}"` : ""}. Nobody decided it on this job.`;
    default:
      return null;
  }
}

export function nyDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-CA", { timeZone: "America/New_York" });
}
