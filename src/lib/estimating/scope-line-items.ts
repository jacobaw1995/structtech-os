import {
  getFieldValue,
  isFieldFilled,
  resolveChecklistFields,
  type DealRow,
  type LeadControlCenterConfig,
} from "@/lib/crm/command-center";
import type { Json } from "@/lib/supabase/database.types";

// Chunk 4 of the estimate builder rebuild — Guided mode reads the
// site-visit scope checklist (deals.intake_checklist.site_visit_scope.*,
// owned by module_key='crm' config, command-center.ts) through this
// module's OWN config (tenant_modules.config where module_key='estimating',
// key "scope_line_items"). Client-safe: no server-only imports, mirrors
// command-center.ts's defensive-parsing style exactly.
//
// Cross-module coupling, noted not solved (flagged in the Chunk 4
// migration review): scope_line_items keys reference scope-checklist field
// keys owned by the OTHER module's config. Renaming/removing a checklist
// field silently orphans its scope_line_items entry — that direction just
// goes inert, harmless. The dangerous direction (a filled checklist field
// with NO scope_line_items entry — real scope data quietly not becoming a
// line item) is what `unmapped` below exists to catch, every time this
// runs.

export type ScopeLineItemConfig = {
  generates: boolean;
  description?: string;
  unit?: string;
  // quantity = raw checklist value * factor. Default 1 (no conversion).
  // Needed when the checklist's raw unit differs from the billing unit —
  // e.g. roof_area_sqft is stored in square FEET but "sq" as a roofing
  // billing unit means squares (100 sq ft), so that entry needs factor 0.01.
  // Getting this wrong is a 100x quantity error on the single biggest line
  // of the quote, not a cosmetic rounding issue — see the Chunk 4 migration
  // header for the full incident this fixes.
  factor: number;
};

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function asNumber(v: unknown, fallback: number): number {
  return typeof v === "number" && Number.isFinite(v) ? v : fallback;
}

/** Parses tenant_modules.config (module_key='estimating') -> scope_line_items defensively, same philosophy as parseLeadControlCenterConfig: malformed/missing input returns {}, never throws. */
export function parseScopeLineItemsConfig(config: Json | null | undefined): Record<string, ScopeLineItemConfig> {
  if (!isRecord(config)) return {};
  const raw = (config as Record<string, unknown>).scope_line_items;
  if (!isRecord(raw)) return {};
  const out: Record<string, ScopeLineItemConfig> = {};
  for (const [key, value] of Object.entries(raw)) {
    if (!isRecord(value)) continue;
    out[key] = {
      generates: value.generates === true,
      description: typeof value.description === "string" ? value.description : undefined,
      unit: typeof value.unit === "string" ? value.unit : undefined,
      factor: asNumber(value.factor, 1),
    };
  }
  return out;
}

export type GeneratedScopeLineItem = {
  scopeKey: string;
  description: string;
  quantity: number;
  unit: string | null;
};

export type ScopeGenerationResult = {
  items: GeneratedScopeLineItem[];
  // A filled site_visit_scope checklist field with NO scope_line_items
  // entry at all (not even {generates: false}) — never invented a line
  // item for it, but the operator needs to know it exists so a real scope
  // value doesn't silently vanish from the quote. Config entries with
  // generates:false are a deliberate, config-authored exclusion — those
  // are NOT reported here.
  unmapped: string[];
  // A generates:true entry whose live checklist value doesn't parse as a
  // number — skipped, never guessed at (no fallback to quantity 1).
  unparseable: string[];
};

/**
 * Reads the deal's site-visit scope checklist (via the crm module's parsed
 * LeadControlCenterConfig) through this module's scope_line_items config,
 * and produces the line items Guided mode would upsert — plus what it
 * deliberately left out and why, for the caller to surface to the operator.
 * Pure function, no RPC calls — the caller (a server action) does the
 * actual upsert_estimate_scope_line_items() call with the `items` result.
 */
export function generateScopeLineItems(
  deal: DealRow,
  lccConfig: LeadControlCenterConfig,
  scopeConfig: Record<string, ScopeLineItemConfig>
): ScopeGenerationResult {
  const scopeFields = resolveChecklistFields(lccConfig, "site_visit_scope");
  const items: GeneratedScopeLineItem[] = [];
  const unmapped: string[] = [];
  const unparseable: string[] = [];

  for (const field of scopeFields) {
    if (!isFieldFilled(deal, field)) continue; // nothing to generate from — not an error

    const entry = scopeConfig[field.key];
    if (!entry) {
      unmapped.push(field.key);
      continue;
    }
    if (!entry.generates) continue; // deliberate config exclusion, not reported

    const rawValue = getFieldValue(deal, field);
    const numeric = typeof rawValue === "number" ? rawValue : Number(rawValue);
    if (!Number.isFinite(numeric)) {
      unparseable.push(field.key);
      continue;
    }

    items.push({
      scopeKey: field.key,
      description: entry.description || field.label,
      quantity: numeric * entry.factor,
      unit: entry.unit ?? null,
    });
  }

  return { items, unmapped, unparseable };
}
