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
    p_contact_name: requireString(formData, "contact_name"),
    p_company: optionalString(formData, "company"),
    p_email: optionalString(formData, "email"),
    p_phone: optionalString(formData, "phone"),
    p_value: rawValue ? Number(rawValue) : undefined,
    p_trade: optionalString(formData, "trade"),
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
