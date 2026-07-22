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

export function coordinationStages(input: {
  signOffAt: string | null;
  materialCount: number;
  scheduleCount: number;
}): CoordinationStage[] {
  return [
    { key: "signed", label: "Signed job", complete: true },
    {
      key: "sign_off",
      label: "Sign-off: colors & finishes",
      complete: input.signOffAt != null,
    },
    { key: "work_order", label: "Work order", complete: true },
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
