import type { FieldConfig, LeadControlCenterConfig } from "@/lib/crm/command-center";
import { resolveChecklistFields } from "@/lib/crm/command-center";

// Client-safe: no server-only imports. Thin accessor for the New-Lead
// intake-call checklist (docs/reference/LEAD_CONTROL_CENTER_SPEC.md's
// "Intake-call checklist"). Holds no field data itself — SCOPE §12F moved
// the field/checklist DEFINITIONS into tenant_modules.config, seeded by
// 20260714200000. This just names the config's checklist key and resolves
// it through command-center.ts's generic config->fields lookup.

export const INTAKE_CALL_CHECKLIST_KEY = "intake_call";

export function intakeCallChecklistFields(config: LeadControlCenterConfig): FieldConfig[] {
  return resolveChecklistFields(config, INTAKE_CALL_CHECKLIST_KEY);
}

// general_notes is in the intake_checklist JSON shape but NOT in the
// spec's checklist item list — free-form, never counted toward
// completion. Looked up directly (not part of the checklist's field_keys)
// so Stage 4 can still render/edit it outside the checklist loop.
export function generalNotesField(config: LeadControlCenterConfig): FieldConfig | undefined {
  return config.fields["general_notes"];
}
