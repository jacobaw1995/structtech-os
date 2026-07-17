import type { Json } from "@/lib/supabase/database.types";

// Client-safe: no server-only imports. Mirrors the shape written by
// supabase/migrations/20260712130000_crm_stage_config_and_rpcs.sql into
// tenant_modules.config->stages for module_key='crm'.
export type CrmStage = {
  key: string;
  label: string;
  cancel_pending_follow_ups: boolean;
  outcome: "won" | "lost" | null;
  // Per-stage suggested next action — a display hint the DB config carries
  // alongside label/outcome (see Stage 2 migration), NOT a per-deal field.
  // Absent until that config is populated; the UI omits the chip if unset.
  next_action: string | null;
};

function parseOutcome(value: Json | undefined): "won" | "lost" | null {
  if (value === "won") return "won";
  if (value === "lost") return "lost";
  return null;
}

/**
 * Parses tenant_modules.config->stages defensively — it's user-editable
 * jsonb, not a typed column, so a missing/malformed config renders an empty
 * board (caller's problem to surface) rather than throwing mid-render.
 */
export function parseCrmStages(config: Json | null | undefined): CrmStage[] {
  if (!config || typeof config !== "object" || Array.isArray(config)) return [];
  const stages = (config as Record<string, Json>).stages;
  if (!Array.isArray(stages)) return [];

  return stages
    .filter(
      (s): s is Record<string, Json> =>
        typeof s === "object" && s !== null && !Array.isArray(s)
    )
    .map(
      (s): CrmStage => ({
        key: typeof s.key === "string" ? s.key : "",
        label: typeof s.label === "string" ? s.label : String(s.key ?? ""),
        cancel_pending_follow_ups: s.cancel_pending_follow_ups === true,
        outcome: parseOutcome(s.outcome),
        next_action: typeof s.next_action === "string" ? s.next_action : null,
      })
    )
    .filter((s) => s.key.length > 0);
}

export function formatMoney(value: number | null): string {
  if (value == null) return "—";
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 0,
  }).format(value);
}

export function formatDate(iso: string | null): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
  });
}

export function daysBetween(fromIso: string, toIso: string): number {
  const from = new Date(fromIso).getTime();
  const to = new Date(toIso).getTime();
  return Math.round((to - from) / 86_400_000);
}

// Shared between the left panel's Revision History and the mobile merged
// Log Activity feed (relocated from the old DealPanel.tsx).
export function activityLabel(entry: { action: string; from_value: string | null; to_value: string | null }): string {
  switch (entry.action) {
    case "stage_changed":
      return `Stage: ${entry.from_value ?? "—"} → ${entry.to_value ?? "—"}`;
    case "created":
      return `Created (${entry.to_value ?? "—"})`;
    case "note_added":
      return `Note added`;
    case "followup_scheduled":
      return `Follow-up scheduled (${entry.to_value ?? "—"})`;
    case "details_updated":
      return `Details updated`;
    case "archived":
      return `Archived`;
    case "restored":
      return `Restored`;
    case "engagement_materialize_failed":
      return `Engagement creation failed`;
    default:
      return entry.action;
  }
}
