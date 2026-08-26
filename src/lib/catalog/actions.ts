"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// Same conventions as src/lib/estimating/actions.ts: server actions redirect(),
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
  if (raw === undefined) return undefined;
  const n = Number(raw);
  return Number.isFinite(n) ? n : undefined;
}

function catalogHref(orgId: string, params?: Record<string, string>) {
  const qs = params ? `?${new URLSearchParams(params).toString()}` : "";
  return `/w/${orgId}/estimating/catalog${qs}`;
}

function revalidateCatalog(orgId: string) {
  revalidatePath(`/w/${orgId}/estimating/catalog`);
}

export async function createProduct(formData: FormData) {
  const orgId = requireString(formData, "orgId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  // A2.1c — cost plus EITHER sell OR markup; the RPC derives the other.
  // No "which did you type" flag is sent, and that is deliberate: the rule is
  // unambiguous without one (markup alone -> derive sell; sell alone -> derive
  // markup; both -> they must agree within a cent or the write is REFUSED).
  // A flag would be a parameter the server never actually needs to consult.
  const { error } = await supabase.rpc("create_product", {
    p_org_id: orgId,
    p_name: requireString(formData, "name"),
    p_category: optionalString(formData, "category"),
    p_unit: optionalString(formData, "unit"),
    p_cost: optionalNumber(formData, "cost"),
    p_sell: optionalNumber(formData, "sell"),
    p_markup: optionalNumber(formData, "markup"),
  });

  if (error) {
    redirect(catalogHref(orgId, { error: error.message }));
  }

  revalidateCatalog(orgId);
  redirect(catalogHref(orgId));
}

// jsonb patch, matching update_deal_fields' shape (§4.3: extend the shipped
// pattern, do not invent a second one). Only keys actually present in the form
// are sent, so an edit of `name` alone cannot blank `cost` as a side effect.
export async function updateProduct(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const productId = requireString(formData, "productId");

  const patch: Record<string, string | number | boolean | null> = {};
  for (const key of ["name", "category", "unit"] as const) {
    const v = formData.get(key);
    if (typeof v === "string") patch[key] = v.length > 0 ? v : null;
  }
  for (const key of ["cost", "sell", "markup"] as const) {
    const v = formData.get(key);
    if (typeof v === "string") {
      if (v.length === 0) {
        patch[key] = null;
      } else {
        const n = Number(v);
        if (Number.isFinite(n)) patch[key] = n;
      }
    }
  }
  // markup alone -> update_product derives sell; sell alone -> derives markup;
  // both -> refused unless they agree within a cent.
  if (formData.get("active") !== null) {
    patch.active = formData.get("active") === "on";
  }

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("update_product", {
    p_product_id: productId,
    p_patch: patch,
  });

  if (error) {
    redirect(catalogHref(orgId, { edit: productId, error: error.message }));
  }

  revalidateCatalog(orgId);
  redirect(catalogHref(orgId));
}

// §2.6 full CRUD. Two distinct verbs, deliberately not collapsed into one:
// ARCHIVE (active=false) keeps the row so historical estimate lines that
// reference it still resolve; DELETE removes it and is REFUSED by the RPC when
// any estimate line item still points at it, with the count named (A1.4's
// precedent — refuse and say how many, never cascade silently).
export async function setProductActive(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const productId = requireString(formData, "productId");
  const active = requireString(formData, "active") === "true";

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("update_product", {
    p_product_id: productId,
    p_patch: { active },
  });

  if (error) {
    redirect(catalogHref(orgId, { error: error.message }));
  }

  revalidateCatalog(orgId);
  redirect(catalogHref(orgId));
}

export async function deleteProduct(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const productId = requireString(formData, "productId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("delete_product", {
    p_product_id: productId,
  });

  if (error) {
    // The RPC's refusal message names the referencing line-item count, so it
    // is surfaced verbatim rather than reworded (A1.3a's rule for RPC errors).
    redirect(catalogHref(orgId, { error: error.message }));
  }

  revalidateCatalog(orgId);
  redirect(catalogHref(orgId));
}
