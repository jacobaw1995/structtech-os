"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

// Server actions redirect(), never return data (CLAUDE.md rule 6). Every
// mutation below goes through a security-definer RPC (supabase/migrations/
// 20260726120000_build_tracker_module.sql). Mirrors lib/tracker/actions.ts.

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

function withError(path: string, error?: string): string {
  if (!error) return path;
  const separator = path.includes("?") ? "&" : "?";
  return `${path}${separator}error=${encodeURIComponent(error)}`;
}

async function authedClient() {
  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");
  return supabase;
}

export async function createRoadmapItem(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const supabase = await authedClient();

  // New items land at the bottom of the whole list (not just their
  // section) — the page groups by section text regardless of position, so
  // this only affects where a new row sits within its own group.
  const { data: maxRow } = await supabase
    .from("roadmap_items")
    .select("sort_order")
    .eq("org_id", orgId)
    .order("sort_order", { ascending: false })
    .limit(1)
    .maybeSingle();
  const nextSortOrder = (maxRow?.sort_order ?? -1) + 1;

  const { error } = await supabase.rpc("create_roadmap_item", {
    p_org_id: orgId,
    p_phase: requireString(formData, "phase"),
    p_section: requireString(formData, "section"),
    p_feature: requireString(formData, "feature"),
    p_status: optionalString(formData, "status") ?? "planned",
    p_notes: optionalString(formData, "notes"),
    p_sort_order: nextSortOrder,
  });

  redirect(withError(`/w/${orgId}/build${error ? "?new=1" : ""}`, error?.message));
}

export async function updateRoadmapItemStatus(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const itemId = requireString(formData, "itemId");
  const supabase = await authedClient();

  const { error } = await supabase.rpc("update_roadmap_fields", {
    p_id: itemId,
    p_patch: { status: requireString(formData, "status") },
  });

  redirect(withError(`/w/${orgId}/build`, error?.message));
}

export async function updateRoadmapItemPhase(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const itemId = requireString(formData, "itemId");
  const supabase = await authedClient();

  const { error } = await supabase.rpc("update_roadmap_fields", {
    p_id: itemId,
    p_patch: { phase: requireString(formData, "phase") },
  });

  redirect(withError(`/w/${orgId}/build`, error?.message));
}

export async function updateRoadmapItemNotes(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const itemId = requireString(formData, "itemId");
  const supabase = await authedClient();

  // Patch key is always present here (even "") so an emptied field really
  // clears — the jsonb-patch convention's whole point (update_deal_fields).
  const notes = formData.get("notes");

  const { error } = await supabase.rpc("update_roadmap_fields", {
    p_id: itemId,
    p_patch: { notes: typeof notes === "string" ? notes : "" },
  });

  redirect(withError(`/w/${orgId}/build`, error?.message));
}

export async function updateRoadmapItemDetails(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const itemId = requireString(formData, "itemId");
  const supabase = await authedClient();

  const { error } = await supabase.rpc("update_roadmap_fields", {
    p_id: itemId,
    p_patch: {
      section: requireString(formData, "section"),
      feature: requireString(formData, "feature"),
    },
  });

  redirect(withError(`/w/${orgId}/build`, error?.message));
}

export async function deleteRoadmapItem(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const itemId = requireString(formData, "itemId");
  const supabase = await authedClient();

  const { error } = await supabase.rpc("delete_roadmap_item", { p_id: itemId });

  redirect(withError(`/w/${orgId}/build`, error?.message));
}
