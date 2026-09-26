// Client-safe: no server-only imports. work_orders has no status column
// (migration header note) — progress-chip stage is derived here from data
// presence so it can never drift from the rows it summarizes.

export type CoordinationStage = {
  key: "signed" | "sign_off" | "work_order" | "materials" | "schedule";
  label: string;
  complete: boolean;
};

// crm/stages.ts's formatDate does `new Date(iso)`, which is correct for
// timestamptz strings (they carry an offset) but wrong for plain `date`
// columns (schedule_blocks.start_date/end_date) — a bare "YYYY-MM-DD" gets
// parsed as UTC midnight, then shifts a day back once rendered in any
// negative-UTC-offset timezone. Parsing the parts and building a local Date
// avoids that shift.
export function formatDateOnly(value: string | null): string {
  if (!value) return "—";
  const [year, month, day] = value.split("-").map(Number);
  return new Date(year, month - 1, day).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
  });
}

// Task B (7/24 walkthrough) — labels for work_order_activity rows, same
// shape as crm/stages.ts's activityLabel for deal_activity.
export function workOrderActivityLabel(entry: { action: string; from_value: string | null; to_value: string | null }): string {
  switch (entry.action) {
    case "material_added_after_signoff":
      return `added a material after sign-off: ${entry.to_value ?? "—"}`;
    case "material_updated_after_signoff":
      return `changed a material after sign-off: ${entry.from_value ?? "—"} → ${entry.to_value ?? "—"}`;
    case "material_deleted_after_signoff":
      return `removed a material after sign-off: ${entry.from_value ?? "—"}`;
    case "signoff_notes_updated_after_signoff":
      return `changed colors/finishes after sign-off: ${entry.from_value ?? "—"} → ${entry.to_value ?? "—"}`;
    default:
      return entry.action;
  }
}

// Same actor-composition shape as crm/stages.ts's formatActivityLine, but
// against workOrderActivityLabel — kept separate rather than making that
// function accept an injected label fn, since it's the only other caller.
export function formatWorkOrderActivityLine(
  entry: { action: string; from_value: string | null; to_value: string | null },
  actorName: string | null
): string {
  const label = workOrderActivityLabel(entry);
  return actorName ? `${actorName} ${label}` : label.charAt(0).toUpperCase() + label.slice(1);
}

/**
 * THE RAIL REPORTS FACTS, ALL FIVE OF THEM. U-W1.34, 2026-09-25.
 *
 * `signed` and `work_order` were `complete: true` — constants. Two of the five
 * chips carried a checkmark that reported nothing, sitting beside three that
 * were earned, and no reader could tell which was which. Reported 2026-09-22
 * as a product question rather than a rendering one; Track S answered it with
 * migration 20260923204850, which puts both facts on fetch_work_order_tree:
 * `job_signed` (a SIGNATURE ROW exists for the job's estimate — not
 * `estimates.status`, which a person can set) and `job_live_trade_count`.
 *
 * S measured that `work_order` is FALSE on a real BMR job today — Devin
 * Carter's has no trade work order — so this chip stops lying on a live record
 * the moment it ships, rather than being a correctness argument with no case.
 */
export function coordinationStages(input: {
  signOffAt: string | null;
  materialCount: number;
  scheduleCount: number;
  /** A signature row exists for the job's estimate. */
  signed: boolean;
  /** The job has at least one live trade work order. */
  workOrder: boolean;
}): CoordinationStage[] {
  return [
    { key: "signed", label: "Signed job", complete: input.signed },
    {
      key: "sign_off",
      label: "Sign-off: colors & finishes",
      complete: input.signOffAt != null,
    },
    { key: "work_order", label: "Work order", complete: input.workOrder },
    {
      key: "materials",
      label: "Materials",
      complete: input.materialCount > 0,
    },
    {
      key: "schedule",
      label: "Schedule",
      complete: input.scheduleCount > 0,
    },
  ];
}
