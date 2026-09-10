"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// Same conventions as src/lib/catalog/actions.ts and coordination/actions.ts:
// server actions redirect(), never return data (CLAUDE.md rule 6); every
// mutation goes through a security-definer RPC (rule 3); getSession() before
// any DB call (rule 1).
//
// NOTE WHAT IS ABSENT: there is no createPurchaseOrder action that omits a
// job. `create_purchase_order`'s no-job branch resolves the org with
//   select org_id from org_members where user_id = auth.uid() limit 1
// — no ORDER BY, no org argument — so for a user in more than one org it picks
// arbitrarily. That is not hypothetical here: the only human who would draft a
// PO off a supplier call is in THREE orgs (Brothers Metal Roofing, Material
// Matrix, StructTech), measured 2026-09-09. A jobless draft from a
// workspace-scoped screen could land in the wrong tenant, and the PO could
// then never leave draft because nothing writes job_id after the insert.
// Reported to Track S; not worked around here.

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

function poHref(orgId: string, poId: string, error?: string) {
  const qs = error ? `?error=${encodeURIComponent(error)}` : "";
  return `/w/${orgId}/coordination/po/${poId}${qs}`;
}

async function client() {
  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");
  return supabase;
}

export async function createPurchaseOrder(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");
  // Always present. See the note at the top of this file for why there is no
  // jobless path.
  const jobId = requireString(formData, "jobId");

  const supabase = await client();
  const { data, error } = await supabase.rpc("create_purchase_order", {
    p_job_id: jobId,
    p_supplier_name: requireString(formData, "supplier_name"),
  });

  if (error) {
    redirect(
      `/w/${orgId}/coordination/${workOrderId}?error=${encodeURIComponent(error.message)}`
    );
  }
  revalidatePath(`/w/${orgId}/coordination/${workOrderId}`);
  redirect(poHref(orgId, data as unknown as string));
}

export async function updatePurchaseOrder(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const poId = requireString(formData, "poId");

  const supabase = await client();
  const { error } = await supabase.rpc("update_purchase_order", {
    p_po_id: poId,
    p_supplier_name: optionalString(formData, "supplier_name"),
    p_status: optionalString(formData, "status"),
  });

  if (error) {
    // Surfaced verbatim (A1.3a's rule): the RPC's refusals name the field and
    // the required action, and rewording them loses that.
    redirect(poHref(orgId, poId, error.message));
  }
  revalidatePath(poHref(orgId, poId));
  redirect(poHref(orgId, poId));
}

export async function addPurchaseOrderLine(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const poId = requireString(formData, "poId");

  const qtyRaw = optionalString(formData, "quantity_ordered");
  const qty = qtyRaw === undefined ? undefined : Number(qtyRaw);

  const supabase = await client();
  const { error } = await supabase.rpc("add_purchase_order_line", {
    p_po_id: poId,
    p_material_item_id: requireString(formData, "material_item_id"),
    p_quantity_ordered: Number.isFinite(qty as number) ? qty : undefined,
    // A line with no promised date SAVES — the migration says so explicitly
    // ("SCOPE 2.8: a line with no promised_date saves"). You order first and
    // learn the date later, which is the order the real conversation happens
    // in.
    p_promised_date: optionalString(formData, "promised_date"),
  });

  if (error) redirect(poHref(orgId, poId, error.message));
  revalidatePath(poHref(orgId, poId));
  redirect(poHref(orgId, poId));
}

export async function updatePurchaseOrderLine(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const poId = requireString(formData, "poId");

  const qtyRaw = optionalString(formData, "quantity_ordered");
  const qty = qtyRaw === undefined ? undefined : Number(qtyRaw);

  const supabase = await client();
  const { error } = await supabase.rpc("update_purchase_order_line", {
    p_line_id: requireString(formData, "lineId"),
    p_quantity_ordered: Number.isFinite(qty as number) ? qty : undefined,
    p_promised_date: optionalString(formData, "promised_date"),
  });

  if (error) redirect(poHref(orgId, poId, error.message));
  revalidatePath(poHref(orgId, poId));
  redirect(poHref(orgId, poId));
}

export async function deletePurchaseOrderLine(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const poId = requireString(formData, "poId");

  const supabase = await client();
  const { error } = await supabase.rpc("delete_purchase_order_line", {
    p_line_id: requireString(formData, "lineId"),
  });

  if (error) redirect(poHref(orgId, poId, error.message));
  revalidatePath(poHref(orgId, poId));
  redirect(poHref(orgId, poId));
}
