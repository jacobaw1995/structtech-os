"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// Same conventions as src/lib/catalog/actions.ts and coordination/actions.ts:
// server actions redirect(), never return data (CLAUDE.md rule 6); every
// mutation goes through a security-definer RPC (rule 3); getSession() before
// any DB call (rule 1).
//
// HISTORY, kept because the refusal is the reason for the fix. Until
// 2026-09-10 there was no jobless create action here, on purpose:
// `create_purchase_order`'s no-job branch resolved the org with
//   select org_id from org_members where user_id = auth.uid() limit 1
// — no ORDER BY, no org argument — and the one human who would draft off a
// supplier call is in three orgs. Migration 20260910215139
// (po_org_explicit_and_attach) closed it at the database: p_org_id is now
// REQUIRED and first, p_job_id is `default null`, and update_purchase_order
// gained p_job_id so a jobless draft can be attached later. Every write below
// NAMES its tenant; none infers one.

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
  // Where to send the user back to on a refusal — the job's master work order
  // or the coordination index. Explicit, because the form now lives on both.
  const returnTo = requireString(formData, "returnTo");
  // OPTIONAL since 20260910215139. "" from the picker's "No job yet" option
  // arrives as undefined and is sent as null — a draft off a supplier call.
  const jobId = optionalString(formData, "jobId");

  const supabase = await client();
  const { data, error } = await supabase.rpc("create_purchase_order", {
    // The tenant is NAMED, never inferred: this is the route's orgId, already
    // verified against the caller's memberships by requireModuleAccess().
    p_org_id: orgId,
    p_job_id: jobId,
    p_supplier_name: requireString(formData, "supplier_name"),
  });

  if (error) {
    redirect(`${returnTo}?error=${encodeURIComponent(error.message)}`);
  }
  revalidatePath(returnTo);
  redirect(poHref(orgId, data as unknown as string));
}

/**
 * Attach a job to a purchase order — and, optionally, move it out of draft in
 * the SAME call. update_purchase_order checks the draft-exit rule against
 * `coalesce(p_job_id, current job)`, so "attach and mark sent" is one write,
 * not two. That is what lets the surface offer the transition on a jobless
 * draft without offering a control the database refuses.
 */
export async function attachJobToPurchaseOrder(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const poId = requireString(formData, "poId");

  const supabase = await client();
  const { error } = await supabase.rpc("update_purchase_order", {
    p_po_id: poId,
    p_job_id: requireString(formData, "jobId"),
    p_status: optionalString(formData, "status"),
  });

  if (error) redirect(poHref(orgId, poId, error.message));
  revalidatePath(poHref(orgId, poId));
  redirect(poHref(orgId, poId));
}

/**
 * Delete a purchase order. SCOPE §2.6 — and for a jobless draft it is the ONLY
 * way out: cancelling is itself a transition out of draft, so
 * update_purchase_order refuses it without a job. A phone-call draft that fell
 * through would otherwise be permanent.
 */
export async function deletePurchaseOrder(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const poId = requireString(formData, "poId");

  const supabase = await client();
  const { error } = await supabase.rpc("delete_purchase_order", { p_po_id: poId });

  if (error) redirect(poHref(orgId, poId, error.message));
  revalidatePath(`/w/${orgId}/coordination`);
  redirect(`/w/${orgId}/coordination`);
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
