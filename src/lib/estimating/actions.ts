"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { parseLeadControlCenterConfig } from "@/lib/crm/command-center";
import { parseScopeLineItemsConfig, generateScopeLineItems } from "@/lib/estimating/scope-line-items";

// Same conventions as src/lib/crm/actions.ts: server actions redirect(),
// never return data (CLAUDE.md rule 6); every mutation goes through a
// security-definer RPC (rule 3).

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

export async function createEstimateFromDeal(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const dealId = requireString(formData, "dealId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { data: estimateId, error } = await supabase.rpc("create_estimate_from_deal", {
    p_deal_id: dealId,
  });

  if (error) {
    redirect(`/w/${orgId}/crm?deal=${dealId}&error=${encodeURIComponent(error.message)}`);
  }

  // Chunk 5 cutover: the canonical estimate page IS the document now — no
  // more ?step=1.
  revalidateEstimateDocument(orgId, estimateId);
  redirect(estimateDocumentHref(orgId, estimateId));
}

// Chunk 5 relocation: "Present to client" (StepPresent.tsx, deleted) lives
// near Totals in the unified document now. It does two things in one
// action — snapshot presented_total/presented_at (present_estimate is
// unchanged, still callable from 'draft' or 'presented' per the Chunk 1
// decision) AND navigate straight into Present Mode, since handing the
// tablet to the customer is the entire point of clicking it.
function estimatePresentHref(orgId: string, estimateId: string, error?: string) {
  const qs = error ? `?error=${encodeURIComponent(error)}` : "";
  return `/w/${orgId}/estimating/${estimateId}/present${qs}`;
}

export async function presentEstimate(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const estimateId = requireString(formData, "estimateId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("present_estimate", {
    p_estimate_id: estimateId,
  });

  if (error) {
    redirect(estimateDocumentHref(orgId, estimateId, { error: error.message }));
  }

  revalidateEstimateDocument(orgId, estimateId);
  redirect(estimatePresentHref(orgId, estimateId));
}

export async function signEstimate(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const estimateId = requireString(formData, "estimateId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("sign_estimate", {
    p_estimate_id: estimateId,
    p_signer_name: requireString(formData, "signer_name"),
    p_signer_role: requireString(formData, "signer_role"),
    p_signature_data: requireString(formData, "signature_data"),
  });

  if (error) {
    redirect(estimatePresentHref(orgId, estimateId, error.message));
  }

  revalidatePath(`/w/${orgId}/estimating/${estimateId}/present`);
  revalidateEstimateDocument(orgId, estimateId);
  redirect(estimatePresentHref(orgId, estimateId));
}

export async function voidEstimate(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const estimateId = requireString(formData, "estimateId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("void_estimate", {
    p_estimate_id: estimateId,
  });

  if (error) {
    redirect(estimateDocumentHref(orgId, estimateId, { error: error.message }));
  }

  revalidateEstimateDocument(orgId, estimateId);
  redirect(estimateDocumentHref(orgId, estimateId));
}

// ============================================================================
// Document actions (Chunk 3 of the estimate builder rebuild) — same RPCs
// as the wizard actions above where the RPC already covers the field, but
// these redirect back to /document (no ?step=) instead of the wizard's
// step URL. Kept as separate functions rather than parameterizing the
// wizard ones because two live call sites need two different redirect
// targets until Chunk 5 deletes the wizard and this becomes the only path.
// ============================================================================

function estimateDocumentHref(
  orgId: string,
  estimateId: string,
  opts?: { error?: string; unmapped?: string[]; unparseable?: string[] }
) {
  const params = new URLSearchParams();
  if (opts?.error) params.set("error", opts.error);
  if (opts?.unmapped?.length) params.set("scopeUnmapped", opts.unmapped.join(","));
  if (opts?.unparseable?.length) params.set("scopeUnparseable", opts.unparseable.join(","));
  const qs = params.toString();
  return `/w/${orgId}/estimating/${estimateId}/document${qs ? `?${qs}` : ""}`;
}

function revalidateEstimateDocument(orgId: string, estimateId: string) {
  revalidatePath(`/w/${orgId}/estimating/${estimateId}/document`);
}

export async function updateEstimateDocumentContact(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const estimateId = requireString(formData, "estimateId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("update_estimate_contact", {
    p_estimate_id: estimateId,
    p_contact_name: optionalString(formData, "contact_name"),
    p_company: optionalString(formData, "company"),
    p_phone: optionalString(formData, "phone"),
    p_email: optionalString(formData, "email"),
  });

  if (error) {
    redirect(estimateDocumentHref(orgId, estimateId, { error: error.message }));
  }

  revalidateEstimateDocument(orgId, estimateId);
  redirect(estimateDocumentHref(orgId, estimateId));
}

// Handles every scalar estimate-document field except contact info: each
// EditableField instance submits only its own one field (plus the hidden
// orgId/estimateId), so on any given call every other optionalX() here
// reads undefined from FormData and coalesce() in the RPC no-ops it — one
// action safely covers all seven fields.
//
// tax_rate is stored as a fraction (0.07) but edited as a percent (the
// document shows "Tax (7%)") — this is the one field that needs a unit
// conversion between what the human types and what the column holds.
//
// valid_until/tax_rate are the two BACKLOG.md P0.5 exceptions: coalesce()
// can't clear them, so clearing needs its own signal. Because each
// EditableField submits only its own field, `formData.get(key) !== null`
// means THIS submission is for that field — an empty string there means
// the user cleared it (send p_clear_*=true), not that the field is absent
// from an unrelated field's submission (formData.get returns null then,
// same as always). No EditableField change needed — the empty submission
// already carries everything this action needs to detect a clear.
export async function updateEstimateDocumentDetails(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const estimateId = requireString(formData, "estimateId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const rawValidUntil = formData.get("valid_until");
  const clearValidUntil = typeof rawValidUntil === "string" && rawValidUntil.length === 0;

  const rawTaxPercent = formData.get("tax_rate_percent");
  const clearTaxRate = typeof rawTaxPercent === "string" && rawTaxPercent.length === 0;

  const taxPercent = optionalNumber(formData, "tax_rate_percent");

  const { error } = await supabase.rpc("update_estimate_details", {
    p_estimate_id: estimateId,
    p_clear_valid_until: clearValidUntil,
    p_clear_tax_rate: clearTaxRate,
    p_squares: optionalNumber(formData, "squares"),
    p_pitch: optionalString(formData, "pitch"),
    p_site_address: optionalString(formData, "site_address"),
    p_estimate_date: optionalString(formData, "estimate_date"),
    p_valid_until: optionalString(formData, "valid_until"),
    p_tax_rate: taxPercent === undefined ? undefined : taxPercent / 100,
    p_notes_terms: optionalString(formData, "notes_terms"),
  });

  if (error) {
    redirect(estimateDocumentHref(orgId, estimateId, { error: error.message }));
  }

  revalidateEstimateDocument(orgId, estimateId);
  redirect(estimateDocumentHref(orgId, estimateId));
}

// description is deliberately NOT requireString()'d here — SCOPE §2.8: the
// document's "+ Add line item" creates a blank row (description "",
// quantity 1, unit_price 0) that the user fills in afterward via
// EditableField, same as clicking into any other empty document field.
// requireString would throw on the empty string and crash the action.
export async function addEstimateDocumentLineItem(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const estimateId = requireString(formData, "estimateId");
  const descriptionRaw = formData.get("description");
  const description = typeof descriptionRaw === "string" ? descriptionRaw : "";

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("add_estimate_line_item", {
    p_estimate_id: estimateId,
    p_description: description,
    p_quantity: optionalNumber(formData, "quantity"),
    p_unit_price: optionalNumber(formData, "unit_price"),
    p_sort_order: optionalNumber(formData, "sort_order"),
    p_unit: optionalString(formData, "unit"),
  });

  if (error) {
    redirect(estimateDocumentHref(orgId, estimateId, { error: error.message }));
  }

  revalidateEstimateDocument(orgId, estimateId);
  redirect(estimateDocumentHref(orgId, estimateId));
}

export async function updateEstimateDocumentLineItem(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const estimateId = requireString(formData, "estimateId");
  const lineItemId = requireString(formData, "lineItemId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("update_estimate_line_item", {
    p_line_item_id: lineItemId,
    p_description: optionalString(formData, "description"),
    p_quantity: optionalNumber(formData, "quantity"),
    p_unit_price: optionalNumber(formData, "unit_price"),
    p_unit: optionalString(formData, "unit"),
  });

  if (error) {
    redirect(estimateDocumentHref(orgId, estimateId, { error: error.message }));
  }

  revalidateEstimateDocument(orgId, estimateId);
  redirect(estimateDocumentHref(orgId, estimateId));
}

export async function deleteEstimateDocumentLineItem(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const estimateId = requireString(formData, "estimateId");
  const lineItemId = requireString(formData, "lineItemId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("delete_estimate_line_item", {
    p_line_item_id: lineItemId,
  });

  if (error) {
    redirect(estimateDocumentHref(orgId, estimateId, { error: error.message }));
  }

  revalidateEstimateDocument(orgId, estimateId);
  redirect(estimateDocumentHref(orgId, estimateId));
}

export async function reorderEstimateDocumentLineItems(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const estimateId = requireString(formData, "estimateId");
  const orderedIds = JSON.parse(requireString(formData, "orderedIds")) as string[];

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("reorder_estimate_line_items", {
    p_estimate_id: estimateId,
    p_line_item_ids: orderedIds,
  });

  if (error) {
    redirect(estimateDocumentHref(orgId, estimateId, { error: error.message }));
  }

  revalidateEstimateDocument(orgId, estimateId);
  redirect(estimateDocumentHref(orgId, estimateId));
}

// ============================================================================
// Chunk 4 — Guided mode. Manual is build_mode's default (Chunk 1); Isaac
// never sees a change unless he switches. Switching is never blocking and
// never discards silently (SCOPE §2.8): Guided -> Manual is a pure flag
// flip (touches nothing else); Manual -> Guided (and "refresh" while
// already Guided) only ever inserts-or-refreshes lines tagged with a
// scope_key, and NEVER writes description or unit_price on refresh, and
// NEVER deletes anything — see the Chunk 4 migration header for the full
// reasoning.
// ============================================================================

async function runScopeGeneration(
  supabase: ReturnType<typeof createClient>,
  orgId: string,
  estimateId: string
): Promise<{ error: string | null; unmapped: string[]; unparseable: string[] }> {
  const { data: fetched } = await supabase.rpc("fetch_estimate", { p_estimate_id: estimateId });
  const estimate = fetched?.[0];
  if (!estimate || estimate.org_id !== orgId) {
    return { error: "estimate not found or not accessible", unmapped: [], unparseable: [] };
  }

  const { data: dealFetched } = await supabase.rpc("fetch_deal", { p_deal_id: estimate.deal_id });
  const deal = dealFetched?.[0];
  if (!deal) {
    return { error: "deal not found or not accessible", unmapped: [], unparseable: [] };
  }

  const [{ data: crmModuleRows }, { data: estimatingModuleRows }] = await Promise.all([
    supabase.from("tenant_modules").select("config").eq("org_id", orgId).eq("module_key", "crm"),
    supabase.from("tenant_modules").select("config").eq("org_id", orgId).eq("module_key", "estimating"),
  ]);

  const lccConfig = parseLeadControlCenterConfig(crmModuleRows?.[0]?.config ?? null);
  const scopeConfig = parseScopeLineItemsConfig(estimatingModuleRows?.[0]?.config ?? null);

  const { items, unmapped, unparseable } = generateScopeLineItems(deal, lccConfig, scopeConfig);

  if (items.length > 0) {
    const { error } = await supabase.rpc("upsert_estimate_scope_line_items", {
      p_estimate_id: estimateId,
      p_items: items.map((i) => ({
        scope_key: i.scopeKey,
        description: i.description,
        quantity: i.quantity,
        unit: i.unit,
      })),
    });
    if (error) return { error: error.message, unmapped, unparseable };
  }

  return { error: null, unmapped, unparseable };
}

export async function switchEstimateToGuided(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const estimateId = requireString(formData, "estimateId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error: modeError } = await supabase.rpc("update_estimate_build_mode", {
    p_estimate_id: estimateId,
    p_build_mode: "guided",
  });

  if (modeError) {
    redirect(estimateDocumentHref(orgId, estimateId, { error: modeError.message }));
  }

  const { error, unmapped, unparseable } = await runScopeGeneration(supabase, orgId, estimateId);

  revalidateEstimateDocument(orgId, estimateId);
  redirect(estimateDocumentHref(orgId, estimateId, { error: error ?? undefined, unmapped, unparseable }));
}

export async function switchEstimateToManual(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const estimateId = requireString(formData, "estimateId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  // Pure flag flip — no line items are touched, generated, or removed.
  const { error } = await supabase.rpc("update_estimate_build_mode", {
    p_estimate_id: estimateId,
    p_build_mode: "manual",
  });

  if (error) {
    redirect(estimateDocumentHref(orgId, estimateId, { error: error.message }));
  }

  revalidateEstimateDocument(orgId, estimateId);
  redirect(estimateDocumentHref(orgId, estimateId));
}

// Same generation as switchEstimateToGuided, without touching build_mode —
// for when the scope checklist changes after the estimate is already in
// Guided mode. Safe to click repeatedly (scope_key upsert is idempotent).
export async function refreshEstimateScopeLineItems(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const estimateId = requireString(formData, "estimateId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error, unmapped, unparseable } = await runScopeGeneration(supabase, orgId, estimateId);

  revalidateEstimateDocument(orgId, estimateId);
  redirect(estimateDocumentHref(orgId, estimateId, { error: error ?? undefined, unmapped, unparseable }));
}

export async function deleteEstimate(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const estimateId = requireString(formData, "estimateId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("delete_estimate", {
    p_estimate_id: estimateId,
  });

  if (error) {
    redirect(estimateDocumentHref(orgId, estimateId, { error: error.message }));
  }

  // Unlike the other estimate actions, the row is gone — nothing left at
  // estimateDocumentHref to revalidate into. Back to the list.
  redirect(`/w/${orgId}/estimating`);
}
