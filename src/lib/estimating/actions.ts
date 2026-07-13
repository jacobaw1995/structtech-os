"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

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

function estimateHref(orgId: string, estimateId: string, step?: number, error?: string) {
  const params = new URLSearchParams();
  if (step) params.set("step", String(step));
  if (error) params.set("error", error);
  const qs = params.toString();
  return `/w/${orgId}/estimating/${estimateId}${qs ? `?${qs}` : ""}`;
}

// Next's client-side Router Cache treats redirect(x) back to the route the
// form was already on as a no-op — it doesn't refetch, so the mutation
// (correctly persisted server-side) never shows up without a manual
// reload. revalidatePath() before the redirect busts that cache entry so
// the next render actually re-fetches. Path-only (no query) because
// revalidatePath keys on pathname, and every step of this flow lives under
// the same [estimateId] segment.
function revalidateEstimate(orgId: string, estimateId: string) {
  revalidatePath(`/w/${orgId}/estimating/${estimateId}`);
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

  revalidateEstimate(orgId, estimateId);
  redirect(estimateHref(orgId, estimateId, 1));
}

export async function updateEstimateDetails(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const estimateId = requireString(formData, "estimateId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("update_estimate_details", {
    p_estimate_id: estimateId,
    p_squares: optionalNumber(formData, "squares"),
    p_pitch: optionalString(formData, "pitch"),
    p_site_address: optionalString(formData, "site_address"),
  });

  if (error) {
    redirect(estimateHref(orgId, estimateId, 2, error.message));
  }

  revalidateEstimate(orgId, estimateId);
  redirect(estimateHref(orgId, estimateId, 2));
}

export async function addEstimateLineItem(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const estimateId = requireString(formData, "estimateId");
  const sortOrder = optionalNumber(formData, "sort_order");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("add_estimate_line_item", {
    p_estimate_id: estimateId,
    p_description: requireString(formData, "description"),
    p_quantity: optionalNumber(formData, "quantity"),
    p_unit_price: optionalNumber(formData, "unit_price"),
    p_sort_order: sortOrder,
  });

  if (error) {
    redirect(estimateHref(orgId, estimateId, 2, error.message));
  }

  revalidateEstimate(orgId, estimateId);
  redirect(estimateHref(orgId, estimateId, 2));
}

export async function updateEstimateLineItem(formData: FormData) {
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
  });

  if (error) {
    redirect(estimateHref(orgId, estimateId, 2, error.message));
  }

  revalidateEstimate(orgId, estimateId);
  redirect(estimateHref(orgId, estimateId, 2));
}

export async function deleteEstimateLineItem(formData: FormData) {
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
    redirect(estimateHref(orgId, estimateId, 2, error.message));
  }

  revalidateEstimate(orgId, estimateId);
  redirect(estimateHref(orgId, estimateId, 2));
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
    redirect(estimateHref(orgId, estimateId, 3, error.message));
  }

  revalidateEstimate(orgId, estimateId);
  redirect(estimateHref(orgId, estimateId, 3));
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
    redirect(estimateHref(orgId, estimateId, 4, error.message));
  }

  revalidateEstimate(orgId, estimateId);
  redirect(estimateHref(orgId, estimateId, 4));
}
