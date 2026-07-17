import type { Database, Json } from "@/lib/supabase/database.types";

// Client-safe: no server-only imports. This is the core Lead Control
// Center engine — grounded in docs/reference/LEAD_CONTROL_CENTER_SPEC.md.
//
// SCOPE §12F: stage/field/checklist DEFINITIONS are per-tenant config
// (tenant_modules.config->lead_control_center), not hardcoded here — same
// pattern as stages.ts's parseCrmStages() for the kanban pipeline. This
// module PARSES that config defensively and computes completion,
// derivation, and gating generically off whatever it finds. A tenant with
// no lead_control_center config (e.g. StructTech's internal org, which
// doesn't run a roofing lead-intake flow) parses to an empty, safe config
// — see parseLeadControlCenterConfig — never throws.
//
// What's still code, and why: a field's *definition* (label/hint/type/
// source/whether it's required) is 100% config. A small amount of
// *behavior wiring* stays as internal lookup tables keyed by string ids
// that config points at, because it's tied to fixed schema (specific
// milestone timestamp columns on `deals`) rather than arbitrary tenant
// data — same idea as "computed" field sources already needing a
// resolver, just extended to two more spots:
//   - COMPUTED_FIELD_RESOLVERS: a computed field's `source.id` -> fn.
//   - STAGE_ADVANCE_RESOLVERS: a command-stage's `key` -> "has this
//     milestone been reached" fn, used to derive the active stage.
//   - STAGE_GATING_CHECKLIST_KEY: a command-stage's `key` -> which
//     checklist (by config key) must hit 100% before advancing past it.
// If a tenant's config introduces a stage key with no matching resolver,
// it simply never auto-activates via milestone (falls through) and isn't
// gated — safe, not a crash, just inert until code adds a resolver for it.
//
// intake-checklist.ts / scope-fields.ts are now thin accessors: they pull
// the "intake_call" / "site_visit_scope" checklists out of a parsed
// LeadControlCenterConfig via resolveChecklistFields. No import cycle with
// this file (neither direction) since neither holds field data anymore.

export type DealRow = Database["public"]["Tables"]["deals"]["Row"];

// ============================================================================
// Field registry primitives — same vocabulary as before, now data shapes
// (parsed from JSON) instead of a TS union with an embedded function.
// ============================================================================

export type FieldSourceConfig =
  | { kind: "column"; column: string }
  // Composite (currently only the structured service address). "Filled"
  // means the first column in the list (the anchor — street) is present;
  // city/state/zip can lag behind without blocking checklist completion.
  | { kind: "columns"; columns: string[] }
  // A path into deals.intake_checklist (jsonb). Depth 1 for top-level keys
  // (main_issue), depth 2 for the two nested groups (site_visit_scope.*,
  // estimate_inputs.*) — matches update_intake_checklist_field's p_field_path.
  | { kind: "json"; path: string[] }
  // Derived display value, not itself stored — resolved against
  // COMPUTED_FIELD_RESOLVERS by id (JSON can't carry a function).
  | { kind: "computed"; id: string }
  // Can't be derived from the deals row alone (needs a join elsewhere —
  // e.g. "last note" needs deal_notes, "outcome" needs the org's stage
  // config). Stage 4 supplies these separately; never counts toward
  // completion since this module has no way to check it.
  | { kind: "external" };

// "roof_types"/"address" match the spec's field-type vocabulary exactly;
// "number"/"date" are additions this module needs for the site-visit
// scope checklist's measurement fields (sq ft, linear feet, scheduled-at)
// that the original vital-field type list didn't anticipate.
export type FieldType =
  | "text"
  | "phone"
  | "email"
  | "textarea"
  | "select"
  | "roof_types"
  | "address"
  | "readonly"
  | "number"
  | "date";

export type FieldConfig = {
  key: string;
  label: string;
  emptyHint: string;
  type: FieldType;
  source: FieldSourceConfig;
  // false for readonly/computed/external display fields (source, pipeline
  // stage, visit/scope status, last note, outcome) and for general_notes/
  // scope_notes style free text explicitly excluded from completion math.
  countsTowardCompletion: boolean;
};

export type CommandStageDef = {
  key: string;
  label: string;
  vitalFieldKeys: string[];
};

export type ChecklistDef = {
  key: string;
  title: string;
  fieldKeys: string[];
};

export type LeadTypeOption = { value: string; label: string };

export type LeadControlCenterConfig = {
  leadTypeOptions: LeadTypeOption[];
  commandStages: CommandStageDef[];
  checklists: Record<string, ChecklistDef>;
  fields: Record<string, FieldConfig>;
};

const EMPTY_CONFIG: LeadControlCenterConfig = {
  leadTypeOptions: [],
  commandStages: [],
  checklists: {},
  fields: {},
};

// ============================================================================
// Defensive parsing — tenant_modules.config is user/tenant-editable jsonb,
// not a typed column. A missing or malformed lead_control_center key
// renders an empty, inert config (caller's problem to surface — e.g. "not
// set up for this workspace") rather than throwing mid-render. Mirrors
// stages.ts's parseCrmStages() philosophy exactly.
// ============================================================================

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function asString(v: unknown, fallback: string): string {
  return typeof v === "string" ? v : fallback;
}

function asStringArray(v: unknown): string[] {
  return Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : [];
}

function asBoolean(v: unknown, fallback: boolean): boolean {
  return typeof v === "boolean" ? v : fallback;
}

const FIELD_TYPES: ReadonlySet<string> = new Set([
  "text", "phone", "email", "textarea", "select", "roof_types", "address", "readonly", "number", "date",
]);

function asFieldType(v: unknown): FieldType {
  return typeof v === "string" && FIELD_TYPES.has(v) ? (v as FieldType) : "text";
}

function parseFieldSource(raw: unknown): FieldSourceConfig {
  if (!isRecord(raw)) return { kind: "external" };
  switch (raw.kind) {
    case "column":
      return typeof raw.column === "string" ? { kind: "column", column: raw.column } : { kind: "external" };
    case "columns":
      return { kind: "columns", columns: asStringArray(raw.columns) };
    case "json":
      return { kind: "json", path: asStringArray(raw.path) };
    case "computed":
      return typeof raw.id === "string" ? { kind: "computed", id: raw.id } : { kind: "external" };
    default:
      return { kind: "external" };
  }
}

function parseField(key: string, raw: unknown): FieldConfig | null {
  if (!isRecord(raw)) return null;
  return {
    key,
    label: asString(raw.label, key),
    emptyHint: asString(raw.empty_hint, ""),
    type: asFieldType(raw.type),
    countsTowardCompletion: asBoolean(raw.counts_toward_completion, true),
    source: parseFieldSource(raw.source),
  };
}

function parseFields(raw: unknown): Record<string, FieldConfig> {
  if (!isRecord(raw)) return {};
  const out: Record<string, FieldConfig> = {};
  for (const [key, value] of Object.entries(raw)) {
    const field = parseField(key, value);
    if (field) out[key] = field;
  }
  return out;
}

function parseCommandStages(raw: unknown): CommandStageDef[] {
  if (!Array.isArray(raw)) return [];
  const out: CommandStageDef[] = [];
  for (const item of raw) {
    if (!isRecord(item) || typeof item.key !== "string" || item.key.length === 0) continue;
    out.push({
      key: item.key,
      label: asString(item.label, item.key),
      vitalFieldKeys: asStringArray(item.vital_field_keys),
    });
  }
  return out;
}

function parseChecklists(raw: unknown): Record<string, ChecklistDef> {
  if (!isRecord(raw)) return {};
  const out: Record<string, ChecklistDef> = {};
  for (const [key, value] of Object.entries(raw)) {
    if (!isRecord(value)) continue;
    out[key] = { key, title: asString(value.title, key), fieldKeys: asStringArray(value.field_keys) };
  }
  return out;
}

function parseLeadTypeOptions(raw: unknown): LeadTypeOption[] {
  if (!Array.isArray(raw)) return [];
  const out: LeadTypeOption[] = [];
  for (const item of raw) {
    if (isRecord(item) && typeof item.value === "string" && typeof item.label === "string") {
      out.push({ value: item.value, label: item.label });
    }
  }
  return out;
}

/**
 * Parses tenant_modules.config->lead_control_center defensively. Takes the
 * WHOLE config object (matching parseCrmStages' calling convention) and
 * drills into the lead_control_center key itself. Missing/malformed input
 * (including a tenant with no lead_control_center key at all) returns the
 * empty, safe config — every downstream function in this file treats that
 * as "0 stages, 0 checklists, 0 fields" rather than throwing.
 */
export function parseLeadControlCenterConfig(config: Json | null | undefined): LeadControlCenterConfig {
  if (!isRecord(config)) return EMPTY_CONFIG;
  const lcc = (config as Record<string, unknown>).lead_control_center;
  if (!isRecord(lcc)) return EMPTY_CONFIG;
  return {
    leadTypeOptions: parseLeadTypeOptions(lcc.lead_type_options),
    commandStages: parseCommandStages(lcc.command_stages),
    checklists: parseChecklists(lcc.checklists),
    fields: parseFields(lcc.fields),
  };
}

// ============================================================================
// Generic field value resolution — operates on a FieldConfig from a parsed
// LeadControlCenterConfig, same logic as before, source is now data.
// ============================================================================

export function getJsonPath(value: Json, path: string[]): Json | undefined {
  let current: Json | undefined = value;
  for (const key of path) {
    if (current == null || typeof current !== "object" || Array.isArray(current)) {
      return undefined;
    }
    current = (current as Record<string, Json>)[key];
  }
  return current;
}

// Computed-field resolvers, looked up by the `id` a "computed" field
// source carries in config. Small and fixed because these read specific
// milestone columns on `deals` — see file header.
const COMPUTED_FIELD_RESOLVERS: Record<string, (deal: DealRow) => string | null> = {
  visit_status: (deal) => {
    if (deal.site_survey_complete_at) return "Complete";
    const scheduledAt = getJsonPath(deal.intake_checklist, ["site_visit_scheduled_at"]);
    return typeof scheduledAt === "string" && scheduledAt ? "Scheduled" : "Not yet scheduled";
  },
  scope_status: (deal) => {
    if (deal.roof_scope_ordered_at) return "Ordered";
    if (deal.site_survey_complete_at) return "Site visit complete";
    return "Pending site visit";
  },
};

export function getFieldValue(deal: DealRow, field: FieldConfig): unknown {
  switch (field.source.kind) {
    case "column":
      // Reading a possibly-unknown key off an already-fetched plain object
      // is safe (returns undefined, no crash) — no allowlist needed; this
      // config is DB-seeded by us today, not yet tenant-authored.
      return (deal as unknown as Record<string, unknown>)[field.source.column];
    case "columns":
      return field.source.columns
        .map((c) => (deal as unknown as Record<string, unknown>)[c])
        .filter((v): v is string => typeof v === "string" && v.length > 0);
    case "json":
      return getJsonPath(deal.intake_checklist, field.source.path);
    case "computed":
      return COMPUTED_FIELD_RESOLVERS[field.source.id]?.(deal) ?? null;
    case "external":
      return undefined;
  }
}

export function isFieldFilled(deal: DealRow, field: FieldConfig): boolean {
  // Composite address: filled means the anchor (street) is present, not
  // "at least one of the four parts" — see FieldSourceConfig's "columns" note.
  if (field.source.kind === "columns") {
    const anchor = (deal as unknown as Record<string, unknown>)[field.source.columns[0]];
    return typeof anchor === "string" && anchor.trim().length > 0;
  }
  const value = getFieldValue(deal, field);
  if (value == null) return false;
  if (Array.isArray(value)) return value.length > 0;
  if (typeof value === "string") return value.trim().length > 0;
  return true;
}

export type ChecklistCompletion = {
  filled: number;
  total: number;
  percent: number;
  items: { field: FieldConfig; filled: boolean; value: unknown }[];
};

export function computeCompletion(deal: DealRow, fields: FieldConfig[]): ChecklistCompletion {
  const items = fields.map((field) => ({
    field,
    filled: isFieldFilled(deal, field),
    value: getFieldValue(deal, field),
  }));
  const counted = items.filter((i) => i.field.countsTowardCompletion);
  const filled = counted.filter((i) => i.filled).length;
  return {
    filled,
    total: counted.length,
    percent: counted.length === 0 ? 0 : Math.round((filled / counted.length) * 100),
    items,
  };
}

/** Resolves a checklist's field_keys (e.g. "intake_call") through config.fields. Unknown keys are dropped, not thrown. */
export function resolveChecklistFields(config: LeadControlCenterConfig, checklistKey: string): FieldConfig[] {
  const checklist = config.checklists[checklistKey];
  if (!checklist) return [];
  return checklist.fieldKeys.map((k) => config.fields[k]).filter((f): f is FieldConfig => f != null);
}

/** Resolves a command stage's vital_field_keys through config.fields. */
export function resolveStageVitalFields(config: LeadControlCenterConfig, stage: CommandStageDef): FieldConfig[] {
  return stage.vitalFieldKeys.map((k) => config.fields[k]).filter((f): f is FieldConfig => f != null);
}

// ============================================================================
// Customer type (lead_type) — config-sourced now (config.leadTypeOptions).
// Falls back to the DB CHECK constraint's 4 values for callers that don't
// have an org config in hand (AddDealForm; EditLeadDetailsForm's own
// "Lead type" select).
// ============================================================================

export const LEAD_TYPE_OPTIONS: LeadTypeOption[] = [
  { value: "homeowner", label: "Homeowner" },
  { value: "contractor", label: "Contractor (GC)" },
  { value: "property_management", label: "Property Management" },
  { value: "commercial", label: "Commercial-Other" },
];

export function leadTypeLabel(value: string | null, options: LeadTypeOption[] = LEAD_TYPE_OPTIONS): string {
  return options.find((o) => o.value === value)?.label ?? "—";
}

// remodel_or_new_construction is DB CHECK-constrained (Stage 2 migration:
// 'remodel' | 'new_construction') — unlike the other "select" fields, free
// text here would risk an RPC error, so this gets a small hardcoded
// fallback list too, same reasoning as LEAD_TYPE_OPTIONS. Not config-
// sourced because there's no per-tenant options config yet (Stage 3
// deliberately deferred that) and this one specific field can't safely
// degrade to free text like the others can.
export const REMODEL_OPTIONS: LeadTypeOption[] = [
  { value: "remodel", label: "Remodel" },
  { value: "new_construction", label: "New Construction" },
];

// ============================================================================
// Derivation — purely off existing columns/milestones + the tenant's
// configured command-stage order. No stored "command stage" column;
// isClosed is supplied by the caller (Stage 4), which owns parsing the
// org's crm_stage_config to know whether the deal's kanban stage has a
// won/lost outcome — this module doesn't fetch org config itself.
// ============================================================================

// Stage-key -> "has this milestone been reached" resolver, walked in
// config.commandStages order; the last stage (by config order) whose
// resolver returns true wins. See file header for why this is a small
// fixed table rather than config: it's tied to fixed milestone columns.
const STAGE_ADVANCE_RESOLVERS: Record<string, (deal: DealRow) => boolean> = {
  scope: (deal) => Boolean(deal.site_survey_complete_at),
  quote: (deal) => Boolean(deal.roof_scope_ordered_at),
  negotiating: (deal) => Boolean(deal.quote_presented_at),
};

// Stage-key -> which configured checklist must hit 100% before a deal can
// be considered past that stage. "new_lead" gates on the intake-call
// checklist entered during that stage; "scope" gates on the site-visit
// scope checklist filled out during that stage.
const STAGE_GATING_CHECKLIST_KEY: Record<string, string> = {
  new_lead: "intake_call",
  scope: "site_visit_scope",
};

export function deriveCommandStage(
  deal: DealRow,
  config: LeadControlCenterConfig,
  isClosed: boolean
): string | null {
  if (config.commandStages.length === 0) return null;
  if (isClosed && config.commandStages.some((s) => s.key === "closed")) return "closed";

  let active: string = config.commandStages[0].key;
  for (const stage of config.commandStages) {
    const resolver = STAGE_ADVANCE_RESOLVERS[stage.key];
    if (resolver?.(deal)) active = stage.key;
  }
  return active;
}

// ============================================================================
// Guidance — recommended next action + stage-advance gating. Computed
// only; nothing here calls an RPC or enforces anything server-side.
// ============================================================================

export type AdvanceGate = { allowed: boolean; reason: string | null };

/** Which configured checklist (if any) a command stage primarily displays/gates on — the UI uses this to decide whether a stage's card renders a named checklist or a plain vital-fields list. Same fixed table as gating (see file header). */
export function primaryChecklistKeyForStage(stageKey: string): string | null {
  return STAGE_GATING_CHECKLIST_KEY[stageKey] ?? null;
}

export function canAdvanceStage(
  activeStage: string | null,
  config: LeadControlCenterConfig,
  checklistCompletions: Record<string, ChecklistCompletion>
): AdvanceGate {
  if (activeStage == null) return { allowed: false, reason: "Lead Control Center is not configured for this workspace." };
  const gatingChecklistKey = STAGE_GATING_CHECKLIST_KEY[activeStage];
  if (!gatingChecklistKey) return { allowed: true, reason: null };
  const completion = checklistCompletions[gatingChecklistKey];
  const title = config.checklists[gatingChecklistKey]?.title ?? gatingChecklistKey;
  if (!completion || completion.percent === 100) return { allowed: true, reason: null };
  return { allowed: false, reason: `${title} incomplete (${completion.filled}/${completion.total})` };
}

function recommendedNextAction(
  deal: DealRow,
  activeStage: string | null,
  config: LeadControlCenterConfig,
  checklistCompletions: Record<string, ChecklistCompletion>
): string {
  if (activeStage == null) return "Lead Control Center is not configured for this workspace.";
  const intake = checklistCompletions["intake_call"];
  const scope = checklistCompletions["site_visit_scope"];

  switch (activeStage) {
    case "new_lead":
      if (!intake) return "Continue the intake checklist.";
      return intake.filled === 0
        ? "Claim this lead, then call to start the intake checklist."
        : `Continue the intake checklist (${intake.filled}/${intake.total} gathered).`;
    case "site_visit":
      return "Intake complete — schedule the site visit and generate a preliminary estimate.";
    case "scope":
      if (!scope) return "Complete the on-site scope checklist.";
      return scope.percent === 100
        ? "Scope complete — order materials and build the quote."
        : `Complete the on-site scope checklist (${scope.filled}/${scope.total}).`;
    case "quote":
      return deal.value != null ? "Present the quote to the customer." : "Scope ordered — set a quote amount, then present it.";
    case "negotiating":
      return "Follow up — quote presented, waiting on a decision.";
    case "closed":
      return deal.lost_reason ? "Lost — logged for reference." : "Won — hand off to coordination.";
    default:
      return `Continue working the ${config.checklists[activeStage]?.title ?? activeStage} stage.`;
  }
}

// ============================================================================
// Top-level orchestrator — the one function Stage 4 actually calls.
// ============================================================================

export type CommandCenterStage = CommandStageDef & { vitalFields: FieldConfig[]; reached: boolean; current: boolean };

export type CommandCenterState = {
  activeStage: string | null;
  stages: CommandCenterStage[];
  checklistCompletions: Record<string, ChecklistCompletion>;
  intakeCompletion: ChecklistCompletion;
  scopeCompletion: ChecklistCompletion;
  nextAction: string;
  advanceGate: AdvanceGate;
};

export function commandCenterState(
  deal: DealRow,
  config: LeadControlCenterConfig,
  opts: { isClosed: boolean }
): CommandCenterState {
  const checklistCompletions: Record<string, ChecklistCompletion> = {};
  for (const key of Object.keys(config.checklists)) {
    checklistCompletions[key] = computeCompletion(deal, resolveChecklistFields(config, key));
  }
  const emptyCompletion: ChecklistCompletion = { filled: 0, total: 0, percent: 0, items: [] };

  const activeStage = deriveCommandStage(deal, config, opts.isClosed);
  const activeIndex = config.commandStages.findIndex((s) => s.key === activeStage);

  return {
    activeStage,
    stages: config.commandStages.map((stage, i) => ({
      ...stage,
      vitalFields: resolveStageVitalFields(config, stage),
      reached: activeIndex >= 0 && i <= activeIndex,
      current: stage.key === activeStage,
    })),
    checklistCompletions,
    intakeCompletion: checklistCompletions["intake_call"] ?? emptyCompletion,
    scopeCompletion: checklistCompletions["site_visit_scope"] ?? emptyCompletion,
    nextAction: recommendedNextAction(deal, activeStage, config, checklistCompletions),
    advanceGate: canAdvanceStage(activeStage, config, checklistCompletions),
  };
}
