"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

// Server actions redirect(), never return data (CLAUDE.md rule 6) — every
// action below mutates via a security-definer RPC, then redirects back into
// the crm board/panel so the next server render picks up fresh data. None
// of these return a value the client reads directly.

function requireString(formData: FormData, key: string): string {
  const value = formData.get(key);
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`missing required field: ${key}`);
  }
  return value;
}

function optionalString(formData: FormData, key: string): string | undefined {
  const value = formData.get(key);
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

// Comma-separated tag/roof-type inputs -> text[]. Empty input intentionally
// resolves to [] (clears the array), not undefined — matches Jacob's
// array-UI decision (always send a real array, never JSON null, since a
// multi-select can't express "unknown" vs "none" so the two must never
// diverge in the data) and, before that decision existed, was already what
// kept arrays clearable even under the old coalesce-based update_deal_details
// (coalesce only defers on true SQL NULL, and [] isn't one).
// A multi-select (roof-type dropdowns with seeded options) submits several
// form entries under the same name; a free-text fallback (no options
// configured for that field) submits one comma-separated string. Handle
// both: >1 entry means real selections, don't comma-split them.
function tagList(formData: FormData, key: string): string[] {
  const all = formData.getAll(key).filter((v): v is string => typeof v === "string");
  if (all.length > 1) {
    return all.map((s) => s.trim()).filter((s) => s.length > 0);
  }
  const raw = all[0];
  if (typeof raw !== "string") return [];
  return raw
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

// update_deal_fields(jsonb) replaces update_deal_details' coalesce-based
// design (BACKLOG.md P0.5 — clearing a field silently kept the old value).
// Key ABSENT from the patch = untouched; PRESENT (including empty) = write
// it, empty string becoming JSON null so the RPC actually clears the
// column. These three builders are the fix: optionalString()/
// optionalNumber() collapsed '' to undefined (=absent) BEFORE the RPC ever
// saw it, which is exactly what made clearing impossible under the old
// design — these check FormData presence directly instead.
function patchScalar(
  formData: FormData,
  key: string,
  patch: Record<string, string | number | string[] | null>,
  patchKey: string = key
) {
  const value = formData.get(key);
  if (typeof value !== "string") return; // key not part of THIS submission
  patch[patchKey] = value.length > 0 ? value : null;
}

function patchNumber(
  formData: FormData,
  key: string,
  patch: Record<string, string | number | string[] | null>,
  patchKey: string = key
) {
  const value = formData.get(key);
  if (typeof value !== "string") return;
  patch[patchKey] = value.length > 0 ? Number(value) : null;
}

// Arrays already had correct clear semantics (tagList() never returns
// undefined, only a real array) — this just moves them onto the patch
// object. Per Jacob's array-UI decision: always send a real array (never
// JSON null) so "unknown" and "none" never diverge in a multi-select the
// user has no way to distinguish between.
function patchArray(
  formData: FormData,
  key: string,
  patch: Record<string, string | number | string[] | null>,
  patchKey: string = key
) {
  if (!formData.has(key)) return;
  patch[patchKey] = tagList(formData, key);
}

// Every checklist row and the Prospect Data panel need to redirect back to
// the SAME viewed command-stage tab (not reset to the derived active
// stage) after a save — ?stage= rides along on every crm redirect below.
function dealRedirectPath(orgId: string, dealId: string, stage?: string, error?: string): string {
  const params = new URLSearchParams({ deal: dealId });
  if (stage) params.set("stage", stage);
  if (error) params.set("error", error);
  return `/w/${orgId}/crm?${params.toString()}`;
}

export async function createDeal(formData: FormData) {
  const orgId = requireString(formData, "orgId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const rawValue = optionalString(formData, "value");

  const { data: dealId, error } = await supabase.rpc("create_deal", {
    p_org_id: orgId,
    p_first_name: requireString(formData, "first_name"),
    p_last_name: optionalString(formData, "last_name"),
    p_company: optionalString(formData, "company"),
    p_email: optionalString(formData, "email"),
    p_phone: optionalString(formData, "phone"),
    p_value: rawValue ? Number(rawValue) : undefined,
    p_trade: optionalString(formData, "trade"),
    p_source: optionalString(formData, "source"),
    p_lead_type: optionalString(formData, "lead_type"),
    p_service_address_street: requireString(formData, "service_address_street"),
    p_service_address_city: optionalString(formData, "service_address_city"),
    p_service_address_state: optionalString(formData, "service_address_state"),
    p_service_address_zip: optionalString(formData, "service_address_zip"),
    p_billing_address: optionalString(formData, "billing_address"),
  });

  if (error) {
    redirect(`/w/${orgId}/crm?new=1&error=${encodeURIComponent(error.message)}`);
  }

  redirect(`/w/${orgId}/crm?deal=${dealId}`);
}

export async function updateDealStage(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const dealId = requireString(formData, "dealId");
  const stage = requireString(formData, "stage");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("update_deal_stage", {
    p_deal_id: dealId,
    p_new_stage: stage,
  });

  if (error) {
    redirect(
      `/w/${orgId}/crm?deal=${dealId}&error=${encodeURIComponent(error.message)}`
    );
  }

  redirect(`/w/${orgId}/crm?deal=${dealId}`);
}

export async function addDealNote(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const dealId = requireString(formData, "dealId");
  const content = requireString(formData, "content");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("add_deal_note", {
    p_deal_id: dealId,
    p_content: content,
  });

  if (error) {
    redirect(
      `/w/${orgId}/crm?deal=${dealId}&error=${encodeURIComponent(error.message)}`
    );
  }

  redirect(`/w/${orgId}/crm?deal=${dealId}`);
}

export async function updateDealDetails(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const dealId = requireString(formData, "dealId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const patch: Record<string, string | number | string[] | null> = {};
  patchScalar(formData, "contact_name", patch);
  patchScalar(formData, "company", patch);
  patchScalar(formData, "email", patch);
  patchScalar(formData, "phone", patch);
  patchNumber(formData, "value", patch);
  patchScalar(formData, "trade", patch);
  patchNumber(formData, "crew_size", patch);
  patchScalar(formData, "lead_type", patch);
  patchScalar(formData, "project_address", patch);
  patchScalar(formData, "billing_address", patch);
  patchScalar(formData, "first_name", patch);
  patchScalar(formData, "last_name", patch);
  patchScalar(formData, "secondary_phone", patch);
  patchScalar(formData, "remodel_or_new_construction", patch);
  patchArray(formData, "existing_roof_type", patch);
  patchArray(formData, "roof_type_requested", patch);
  patchScalar(formData, "service_address_street", patch);
  patchScalar(formData, "service_address_city", patch);
  patchScalar(formData, "service_address_state", patch);
  patchScalar(formData, "service_address_zip", patch);
  patchScalar(formData, "referral_name", patch);

  const { error } = await supabase.rpc("update_deal_fields", {
    p_deal_id: dealId,
    p_patch: patch,
  });

  if (error) {
    redirect(
      `/w/${orgId}/crm?deal=${dealId}&error=${encodeURIComponent(error.message)}`
    );
  }

  redirect(`/w/${orgId}/crm?deal=${dealId}`);
}

// ============================================================================
// Stage 4 — Lead Control Center. Every checklist row/quick-edit below
// redirects back to the SAME ?stage= tab the user was viewing (unlike the
// full edit-details form above, which returns to the deal's default view).
// ============================================================================

export async function updateDealOwner(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const dealId = requireString(formData, "dealId");
  const stage = optionalString(formData, "stage");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  // Not optionalString() here on purpose: choosing "Unassigned" submits ''
  // and needs to reach the RPC as a real NULL to actually clear owner_id.
  // optionalString() coercing '' to undefined was the bug — undefined would
  // silently leave owner_id unchanged (assign_deal_owner assigns p_owner_id
  // directly, no coalesce, so NULL here genuinely unassigns).
  const rawOwnerId = formData.get("owner_id");
  const ownerId = typeof rawOwnerId === "string" && rawOwnerId.length > 0 ? rawOwnerId : null;

  // The generated RPC type has p_owner_id as optional-string (no null in its
  // union) since Postgres can't express "nullable" separately from "has a
  // default" — but the SQL default IS null, so omitting the key entirely
  // reaches the same NULL the RPC needs to actually clear owner_id.
  const { error } = await supabase.rpc("assign_deal_owner", {
    p_deal_id: dealId,
    ...(ownerId !== null ? { p_owner_id: ownerId } : {}),
  });

  redirect(dealRedirectPath(orgId, dealId, stage, error?.message));
}

export async function updateDealTags(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const dealId = requireString(formData, "dealId");
  const stage = optionalString(formData, "stage");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const patch: Record<string, string | number | string[] | null> = {};
  patchArray(formData, "tags", patch);

  const { error } = await supabase.rpc("update_deal_fields", {
    p_deal_id: dealId,
    p_patch: patch,
  });

  redirect(dealRedirectPath(orgId, dealId, stage, error?.message));
}

// The single write path for every "column"/"columns"-sourced checklist
// row. `field` names the config field key (e.g. "first_name",
// "existing_roof_type") — mapped to a patch entry via a fixed switch (not
// dynamic SQL; field is never interpolated into a query). Unknown/readonly
// keys hit the default case and produce an empty patch (no-op) rather than
// erroring, since a stale row from an edited config shouldn't hard-fail.
function columnFieldPatch(field: string, formData: FormData): Record<string, string | number | string[] | null> {
  const patch: Record<string, string | number | string[] | null> = {};
  switch (field) {
    case "first_name":
      patchScalar(formData, "value", patch, "first_name");
      break;
    case "last_name":
      patchScalar(formData, "value", patch, "last_name");
      break;
    case "phone":
      patchScalar(formData, "value", patch, "phone");
      break;
    case "email":
      patchScalar(formData, "value", patch, "email");
      break;
    case "lead_type":
      patchScalar(formData, "value", patch, "lead_type");
      break;
    case "remodel_or_new_construction":
      patchScalar(formData, "value", patch, "remodel_or_new_construction");
      break;
    case "value":
      patchNumber(formData, "value", patch, "value");
      break;
    case "existing_roof_type":
      patchArray(formData, "value", patch, "existing_roof_type");
      break;
    case "roof_type_requested":
      patchArray(formData, "value", patch, "roof_type_requested");
      break;
    default:
      break;
  }
  return patch;
}

export async function updateDealColumnField(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const dealId = requireString(formData, "dealId");
  const field = requireString(formData, "field");
  const stage = optionalString(formData, "stage");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("update_deal_fields", {
    p_deal_id: dealId,
    p_patch: columnFieldPatch(field, formData),
  });

  redirect(dealRedirectPath(orgId, dealId, stage, error?.message));
}

export async function updateDealServiceAddress(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const dealId = requireString(formData, "dealId");
  const stage = optionalString(formData, "stage");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const patch: Record<string, string | number | string[] | null> = {};
  patchScalar(formData, "street", patch, "service_address_street");
  patchScalar(formData, "city", patch, "service_address_city");
  patchScalar(formData, "state", patch, "service_address_state");
  patchScalar(formData, "zip", patch, "service_address_zip");

  const { error } = await supabase.rpc("update_deal_fields", {
    p_deal_id: dealId,
    p_patch: patch,
  });

  redirect(dealRedirectPath(orgId, dealId, stage, error?.message));
}

// Writes one deals.intake_checklist path — the JSON-sourced counterpart to
// updateDealColumnField above. `path` arrives JSON-encoded (a hidden input
// can't carry an array natively); `field_type` picks number-vs-string
// coercion for the raw form value before it's sent as jsonb.
export async function updateChecklistField(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const dealId = requireString(formData, "dealId");
  const stage = optionalString(formData, "stage");
  const path = JSON.parse(requireString(formData, "path")) as string[];
  const fieldType = optionalString(formData, "field_type");
  const raw = optionalString(formData, "value");
  const value = fieldType === "number" ? (raw === undefined ? null : Number(raw)) : raw ?? null;

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("update_intake_checklist_field", {
    p_deal_id: dealId,
    p_field_path: path,
    p_value: value,
  });

  redirect(dealRedirectPath(orgId, dealId, stage, error?.message));
}

export async function completeSiteSurvey(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const dealId = requireString(formData, "dealId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("complete_site_survey", { p_deal_id: dealId });

  redirect(dealRedirectPath(orgId, dealId, error ? "site_visit" : "scope", error?.message));
}

export async function orderScope(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const dealId = requireString(formData, "dealId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("order_scope", { p_deal_id: dealId });

  redirect(dealRedirectPath(orgId, dealId, error ? "scope" : "quote", error?.message));
}

export async function presentQuote(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const dealId = requireString(formData, "dealId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("present_quote", { p_deal_id: dealId });

  redirect(dealRedirectPath(orgId, dealId, error ? "quote" : "negotiating", error?.message));
}

export async function archiveDeal(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const dealId = requireString(formData, "dealId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("archive_deal", { p_deal_id: dealId });

  if (error) {
    redirect(
      `/w/${orgId}/crm?deal=${dealId}&error=${encodeURIComponent(error.message)}`
    );
  }

  // Archived deals drop off the board query — closing the panel (rather
  // than redirecting back to ?deal=dealId) avoids landing on a deal the
  // very next render will no longer show in the column it came from.
  redirect(`/w/${orgId}/crm`);
}

export async function restoreDeal(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const dealId = requireString(formData, "dealId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("restore_deal", { p_deal_id: dealId });

  if (error) {
    redirect(
      `/w/${orgId}/crm?deal=${dealId}&error=${encodeURIComponent(error.message)}`
    );
  }

  redirect(`/w/${orgId}/crm?deal=${dealId}`);
}
