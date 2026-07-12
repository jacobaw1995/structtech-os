import type { Json } from "@/lib/supabase/database.types";

// Client-safe: no server-only imports. Mirrors parseCrmStages
// (src/lib/crm/stages.ts) — reads tenant_modules.config for
// module_key='estimating' defensively, since it's user-editable jsonb, not
// a typed column.
//
// This is the first document-template config (SCOPE.md §12E /
// docs/SCOPE.md "Tenant-customizable document templates"): PDF generation
// pulls branding from here instead of hardcoding BMR, so the future
// editable-template system has a config shape to extend rather than a
// rewrite.
export type EstimateBranding = {
  companyName: string;
  address: string | null;
  phone: string | null;
  email: string | null;
  terms: string | null;
};

function str(value: Json | undefined): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

export function parseEstimateBranding(
  config: Json | null | undefined,
  fallbackOrgName: string
): EstimateBranding {
  const branding =
    config && typeof config === "object" && !Array.isArray(config)
      ? (config as Record<string, Json>).branding
      : null;

  const b =
    branding && typeof branding === "object" && !Array.isArray(branding)
      ? (branding as Record<string, Json>)
      : null;

  return {
    companyName: (b && str(b.company_name)) ?? fallbackOrgName,
    address: b ? str(b.address) : null,
    phone: b ? str(b.phone) : null,
    email: b ? str(b.email) : null,
    terms: b ? str(b.terms) : null,
  };
}
