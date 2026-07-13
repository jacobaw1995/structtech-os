import type { Json } from "@/lib/supabase/database.types";

// Client-safe: no server-only imports. Mirrors parseCrmStages
// (src/lib/crm/stages.ts) — production_packets.callouts is jsonb, not a
// typed column, so a malformed/empty value renders an empty list rather
// than throwing mid-render.

export type Callout = {
  id: string;
  label: string;
  detail: string | null;
};

export function parseCallouts(value: Json | null | undefined): Callout[] {
  if (!Array.isArray(value)) return [];

  return value
    .filter(
      (c): c is Record<string, Json> =>
        typeof c === "object" && c !== null && !Array.isArray(c)
    )
    .map(
      (c): Callout => ({
        id: typeof c.id === "string" ? c.id : "",
        label: typeof c.label === "string" ? c.label : "",
        detail: typeof c.detail === "string" ? c.detail : null,
      })
    )
    .filter((c) => c.id.length > 0);
}
