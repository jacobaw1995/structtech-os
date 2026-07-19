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

function optionalNumber(formData: FormData, key: string): number | undefined {
  const raw = optionalString(formData, key);
  return raw === undefined ? undefined : Number(raw);
}

// Comma-separated tag/roof-type inputs -> text[]. Empty input intentionally
// resolves to [] (clears the array), not undefined — array params aren't
// subject to update_deal_details' coalesce-keeps-old-value convention the
// way scalar text params are, so "cleared the box" reads as "clear the
// tags," matching what a user typing into an empty-looking field expects.
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

  const { error } = await supabase.rpc("update_deal_details", {
    p_deal_id: dealId,
    p_contact_name: optionalString(formData, "contact_name"),
    p_company: optionalString(formData, "company"),
    p_email: optionalString(formData, "email"),
    p_phone: optionalString(formData, "phone"),
    p_value: optionalNumber(formData, "value"),
    p_trade: optionalString(formData, "trade"),
    p_crew_size: optionalNumber(formData, "crew_size"),
    p_lead_type: optionalString(formData, "lead_type"),
    p_project_address: optionalString(formData, "project_address"),
    p_billing_address: optionalString(formData, "billing_address"),
    p_first_name: optionalString(formData, "first_name"),
    p_last_name: optionalString(formData, "last_name"),
    p_secondary_phone: optionalString(formData, "secondary_phone"),
    p_remodel_or_new_construction: optionalString(formData, "remodel_or_new_construction"),
    p_existing_roof_type: formData.has("existing_roof_type") ? tagList(formData, "existing_roof_type") : undefined,
    p_roof_type_requested: formData.has("roof_type_requested") ? tagList(formData, "roof_type_requested") : undefined,
    p_service_address_street: optionalString(formData, "service_address_street"),
    p_service_address_city: optionalString(formData, "service_address_city"),
    p_service_address_state: optionalString(formData, "service_address_state"),
    p_service_address_zip: optionalString(formData, "service_address_zip"),
    p_referral_name: optionalString(formData, "referral_name"),
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

  const { error } = await supabase.rpc("update_deal_details", {
    p_deal_id: dealId,
    p_tags: tagList(formData, "tags"),
  });

  redirect(dealRedirectPath(orgId, dealId, stage, error?.message));
}

// The single write path for every "column"/"columns"-sourced checklist
// row. `field` names the config field key (e.g. "first_name",
// "existing_roof_type") — mapped to update_deal_details' named param via a
// fixed switch (not dynamic SQL; field is never interpolated into a
// query). Unknown/readonly keys hit the default case and no-op rather than
// erroring, since a stale row from an edited config shouldn't hard-fail.
function columnFieldRpcParams(field: string, formData: FormData): Record<string, unknown> {
  switch (field) {
    case "first_name":
      return { p_first_name: optionalString(formData, "value") };
    case "last_name":
      return { p_last_name: optionalString(formData, "value") };
    case "phone":
      return { p_phone: optionalString(formData, "value") };
    case "email":
      return { p_email: optionalString(formData, "value") };
    case "lead_type":
      return { p_lead_type: optionalString(formData, "value") };
    case "remodel_or_new_construction":
      return { p_remodel_or_new_construction: optionalString(formData, "value") };
    case "value":
      return { p_value: optionalNumber(formData, "value") };
    case "existing_roof_type":
      return { p_existing_roof_type: tagList(formData, "value") };
    case "roof_type_requested":
      return { p_roof_type_requested: tagList(formData, "value") };
    default:
      return {};
  }
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

  const { error } = await supabase.rpc("update_deal_details", {
    p_deal_id: dealId,
    ...columnFieldRpcParams(field, formData),
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

  const { error } = await supabase.rpc("update_deal_details", {
    p_deal_id: dealId,
    p_service_address_street: optionalString(formData, "street"),
    p_service_address_city: optionalString(formData, "city"),
    p_service_address_state: optionalString(formData, "state"),
    p_service_address_zip: optionalString(formData, "zip"),
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
