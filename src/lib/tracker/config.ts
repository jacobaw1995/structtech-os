import type { Json } from "@/lib/supabase/database.types";

// Client-safe: no server-only imports. Mirrors the shape written by
// supabase/migrations/20260722120000_tracker_module.sql into
// tenant_modules.config->statuses / ->types for module_key='tracker' — same
// pattern as lib/crm/stages.ts's parseCrmStages.

export type TrackerStatus = {
  key: string;
  label: string;
  // Config-driven completion flag (mirrors CRM's per-stage `outcome`) — the
  // status the RPC layer treats as "resolved" for resolved_at, not a
  // hardcoded 'done' string.
  terminal: boolean;
};

export type TrackerType = {
  key: string;
  label: string;
};

export function parseTrackerStatuses(config: Json | null | undefined): TrackerStatus[] {
  if (!config || typeof config !== "object" || Array.isArray(config)) return [];
  const statuses = (config as Record<string, Json>).statuses;
  if (!Array.isArray(statuses)) return [];

  return statuses
    .filter(
      (s): s is Record<string, Json> =>
        typeof s === "object" && s !== null && !Array.isArray(s)
    )
    .map(
      (s): TrackerStatus => ({
        key: typeof s.key === "string" ? s.key : "",
        label: typeof s.label === "string" ? s.label : String(s.key ?? ""),
        terminal: s.terminal === true,
      })
    )
    .filter((s) => s.key.length > 0);
}

export function parseTrackerTypes(config: Json | null | undefined): TrackerType[] {
  if (!config || typeof config !== "object" || Array.isArray(config)) return [];
  const types = (config as Record<string, Json>).types;
  if (!Array.isArray(types)) return [];

  return types
    .filter(
      (t): t is Record<string, Json> =>
        typeof t === "object" && t !== null && !Array.isArray(t)
    )
    .map(
      (t): TrackerType => ({
        key: typeof t.key === "string" ? t.key : "",
        label: typeof t.label === "string" ? t.label : String(t.key ?? ""),
      })
    )
    .filter((t) => t.key.length > 0);
}

export const PRIORITY_OPTIONS: { key: "low" | "normal" | "high" | "urgent"; label: string }[] = [
  { key: "low", label: "Low" },
  { key: "normal", label: "Normal" },
  { key: "high", label: "High" },
  { key: "urgent", label: "Urgent" },
];

export function priorityLabel(priority: string): string {
  return PRIORITY_OPTIONS.find((p) => p.key === priority)?.label ?? priority;
}

export function formatDate(iso: string | null): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
  });
}
