import type { FieldConfig, LeadControlCenterConfig } from "@/lib/crm/command-center";
import { resolveChecklistFields } from "@/lib/crm/command-center";

// Client-safe: no server-only imports. Thin accessor for the Site
// Visit/Scope on-site survey checklist (docs/reference/
// LEAD_CONTROL_CENTER_SPEC.md's "Site-visit scope checklist") — feeds the
// estimate/quote once complete (CLAUDE.md Stage 7, not built yet). Holds
// no field data itself — SCOPE §12F moved the field/checklist DEFINITIONS
// into tenant_modules.config, seeded by 20260714200000. This just names
// the config's checklist key and resolves it through command-center.ts's
// generic config->fields lookup.
//
// Every scope field lives under deals.intake_checklist.site_visit_scope.
// <key> (see each field's source.path in the seed), written incrementally
// via update_intake_checklist_field(deal_id, ['site_visit_scope', key],
// value) — the bare field key (e.g. "gutters_lf") is the stable,
// pricing-matrix-referenceable id; where it's stored is a separate,
// config-carried concern.

export const SITE_VISIT_SCOPE_CHECKLIST_KEY = "site_visit_scope";

export function siteVisitScopeChecklistFields(config: LeadControlCenterConfig): FieldConfig[] {
  return resolveChecklistFields(config, SITE_VISIT_SCOPE_CHECKLIST_KEY);
}
