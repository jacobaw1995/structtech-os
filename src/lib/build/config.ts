// Client-safe: pure vocabulary, no server imports. Matches the DB check
// constraints in supabase/migrations/20260726120000_build_tracker_module.sql
// exactly — the RPCs re-validate these server-side too.

export const ROADMAP_PHASES = [
  { key: "now", label: "Now" },
  { key: "A", label: "A" },
  { key: "B", label: "B" },
  { key: "C", label: "C" },
  { key: "D", label: "D" },
  { key: "later", label: "Later" },
] as const;

export const ROADMAP_STATUSES = [
  { key: "planned", label: "Planned" },
  { key: "in_progress", label: "In progress" },
  { key: "shipped", label: "Shipped" },
] as const;

export function phaseLabel(phase: string): string {
  return ROADMAP_PHASES.find((p) => p.key === phase)?.label ?? phase;
}

export function statusLabel(status: string): string {
  return ROADMAP_STATUSES.find((s) => s.key === status)?.label ?? status;
}
