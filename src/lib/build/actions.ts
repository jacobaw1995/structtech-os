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

// Every action carries a `returnTo` hidden field so it lands back on
// whichever project tab the user had open, not always the default tab —
// same reasoning as tracker/actions.ts's returnPath.
function returnPath(formData: FormData, fallback: string): string {
  return optionalString(formData, "returnTo") ?? fallback;
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
  const projectId = requireString(formData, "projectId");
  const supabase = await authedClient();

  // New items land at the bottom of THIS project's list (not just their
  // section, and not other projects' items) — the page groups by section
  // text regardless of position, so this only affects where a new row
  // sits within its own group.
  const { data: maxRow } = await supabase
    .from("roadmap_items")
    .select("sort_order")
    .eq("org_id", orgId)
    .eq("project_id", projectId)
    .order("sort_order", { ascending: false })
    .limit(1)
    .maybeSingle();
  const nextSortOrder = (maxRow?.sort_order ?? -1) + 1;

  const { error } = await supabase.rpc("create_roadmap_item", {
    p_org_id: orgId,
    p_project_id: projectId,
    p_phase: requireString(formData, "phase"),
    p_section: requireString(formData, "section"),
    p_feature: requireString(formData, "feature"),
    p_status: optionalString(formData, "status") ?? "planned",
    p_notes: optionalString(formData, "notes"),
    p_sort_order: nextSortOrder,
  });

  const base = returnPath(formData, `/w/${orgId}/build`);
  redirect(withError(error ? `${base}${base.includes("?") ? "&" : "?"}new=1` : base, error?.message));
}

export async function updateRoadmapItemStatus(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const itemId = requireString(formData, "itemId");
  const supabase = await authedClient();

  const { error } = await supabase.rpc("update_roadmap_fields", {
    p_id: itemId,
    p_patch: { status: requireString(formData, "status") },
  });

  redirect(withError(returnPath(formData, `/w/${orgId}/build`), error?.message));
}

export async function updateRoadmapItemPhase(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const itemId = requireString(formData, "itemId");
  const supabase = await authedClient();

  const { error } = await supabase.rpc("update_roadmap_fields", {
    p_id: itemId,
    p_patch: { phase: requireString(formData, "phase") },
  });

  redirect(withError(returnPath(formData, `/w/${orgId}/build`), error?.message));
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

  redirect(withError(returnPath(formData, `/w/${orgId}/build`), error?.message));
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

  redirect(withError(returnPath(formData, `/w/${orgId}/build`), error?.message));
}

export async function deleteRoadmapItem(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const itemId = requireString(formData, "itemId");
  const supabase = await authedClient();

  const { error } = await supabase.rpc("delete_roadmap_item", { p_id: itemId });

  redirect(withError(returnPath(formData, `/w/${orgId}/build`), error?.message));
}

// ============================================================================
// Projects
// ============================================================================

export async function createRoadmapProject(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const supabase = await authedClient();

  const { data: maxRow } = await supabase
    .from("roadmap_projects")
    .select("sort_order")
    .eq("org_id", orgId)
    .order("sort_order", { ascending: false })
    .limit(1)
    .maybeSingle();
  const nextSortOrder = (maxRow?.sort_order ?? -1) + 1;

  const name = requireString(formData, "name");
  // Slugify the display name into a stable key — lowercase, non-alphanumerics
  // to underscores, trimmed. The RPC's unique (org_id, key) constraint is
  // the real guard; this is just so "Material Matrix" doesn't require the
  // user to type "material_matrix" by hand.
  const key = name
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");

  const { data: projectId, error } = await supabase.rpc("create_roadmap_project", {
    p_org_id: orgId,
    p_key: key || `project_${Date.now()}`,
    p_name: name,
    p_sort_order: nextSortOrder,
  });

  if (error) {
    redirect(withError(`/w/${orgId}/build?newProject=1`, error.message));
  }

  redirect(`/w/${orgId}/build?project=${projectId}`);
}

export async function updateRoadmapProject(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const projectId = requireString(formData, "projectId");
  const supabase = await authedClient();

  const { error } = await supabase.rpc("update_roadmap_project", {
    p_project_id: projectId,
    p_name: optionalString(formData, "name"),
  });

  redirect(withError(returnPath(formData, `/w/${orgId}/build?project=${projectId}`), error?.message));
}

export async function deleteRoadmapProject(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const projectId = requireString(formData, "projectId");
  const supabase = await authedClient();

  const { error } = await supabase.rpc("delete_roadmap_project", { p_project_id: projectId });

  // On failure (project still has items — see the RPC's guard), land back
  // on that project's tab with the error rather than the default tab.
  redirect(withError(error ? `/w/${orgId}/build?project=${projectId}` : `/w/${orgId}/build`, error?.message));
}
