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
// Log Activity feed (relocated from the old DealPanel.tsx). Lowercase verb
// phrases — composed with an actor name ("Isaac changed stage...") by
// formatActivityLine below, or capitalized standalone when there's no actor
// (legacy pre-Stage-5-Track-C2 rows, or a system-triggered write).
export function activityLabel(entry: { action: string; from_value: string | null; to_value: string | null }): string {
  switch (entry.action) {
    case "stage_changed":
      return `changed stage: ${entry.from_value ?? "—"} → ${entry.to_value ?? "—"}`;
    case "created":
      return `created this deal (${entry.to_value ?? "—"})`;
    case "note_added":
      return `added a note`;
    case "followup_scheduled":
      return `scheduled follow-ups (${entry.to_value ?? "—"})`;
    case "details_updated":
      return `updated the details`;
    case "archived":
      return `archived this deal`;
    case "restored":
      return `restored this deal`;
    case "engagement_materialize_failed":
      return `hit an error creating the engagement`;
    case "site_survey_completed":
      return `completed the site visit`;
    case "scope_ordered":
      return `ordered the roof scope`;
    case "quote_presented":
      return `presented the quote`;
    case "owner_assigned":
      return `reassigned owner: ${entry.from_value ?? "Unassigned"} → ${entry.to_value ?? "Unassigned"}`;
    default:
      return entry.action;
  }
}

function capitalize(text: string): string {
  return text.charAt(0).toUpperCase() + text.slice(1);
}

// Composes activityLabel with a resolved actor name: "Isaac changed stage:
// New Lead → Site Visit" when the actor is known, or just the capitalized
// event ("Changed stage: ...") when actor_id is null/unresolved — legacy
// rows written before actor_id existed, or a name that isn't in the
// caller's member list, fall back gracefully instead of showing "Unknown".
export function formatActivityLine(
  entry: { action: string; from_value: string | null; to_value: string | null },
  actorName: string | null
): string {
  const label = activityLabel(entry);
  return actorName ? `${actorName} ${label}` : capitalize(label);
}
