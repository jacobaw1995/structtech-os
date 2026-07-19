"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

// Server actions redirect(), never return data (CLAUDE.md rule 6) — every
// action below mutates via a security-definer RPC (supabase/migrations/
// 20260722120000_tracker_module.sql), then redirects back into the tracker
// UI so the next server render picks up fresh data. Mirrors lib/crm/actions.ts.

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

// Every item action carries a `returnTo` hidden field — items are actionable
// from both the project board and the cross-project "All open" view, and
// each needs to land back where the user was, not a single hardcoded route.
function returnPath(formData: FormData, fallback: string): string {
  return optionalString(formData, "returnTo") ?? fallback;
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

// ============================================================================
// Projects
// ============================================================================

export async function createTrackerProject(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const supabase = await authedClient();

  const { data: projectId, error } = await supabase.rpc("create_tracker_project", {
    p_org_id: orgId,
    p_name: requireString(formData, "name"),
    p_description: optionalString(formData, "description"),
  });

  if (error) {
    redirect(withError(`/w/${orgId}/tracker?new=1`, error.message));
  }

  redirect(`/w/${orgId}/tracker/${projectId}`);
}

export async function updateTrackerProject(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const projectId = requireString(formData, "projectId");
  const supabase = await authedClient();

  const { error } = await supabase.rpc("update_tracker_project", {
    p_project_id: projectId,
    p_name: optionalString(formData, "name"),
    p_description: optionalString(formData, "description"),
    p_status: optionalString(formData, "status"),
  });

  redirect(withError(`/w/${orgId}/tracker/${projectId}`, error?.message));
}

export async function archiveTrackerProject(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const projectId = requireString(formData, "projectId");
  const supabase = await authedClient();

  const { error } = await supabase.rpc("archive_tracker_project", {
    p_project_id: projectId,
  });

  redirect(withError(`/w/${orgId}/tracker`, error?.message));
}

export async function restoreTrackerProject(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const projectId = requireString(formData, "projectId");
  const supabase = await authedClient();

  const { error } = await supabase.rpc("restore_tracker_project", {
    p_project_id: projectId,
  });

  redirect(withError(`/w/${orgId}/tracker/${projectId}`, error?.message));
}

export async function deleteTrackerProject(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const projectId = requireString(formData, "projectId");
  const supabase = await authedClient();

  const { error } = await supabase.rpc("delete_tracker_project", {
    p_project_id: projectId,
  });

  // On failure (project still has items — see the RPC's guard), land back
  // on that project's board with the error rather than the list, since the
  // list has nowhere obvious to surface a per-project message.
  redirect(withError(error ? `/w/${orgId}/tracker/${projectId}` : `/w/${orgId}/tracker`, error?.message));
}

// ============================================================================
// Items — the quick-add path is THE critical UX (spec: title + type +
// priority in ~2 taps from a phone). Kept to its own action with the
// smallest possible required-field set.
// ============================================================================

export async function createTrackerItem(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const projectId = requireString(formData, "projectId");
  const supabase = await authedClient();

  const { error } = await supabase.rpc("create_tracker_item", {
    p_org_id: orgId,
    p_project_id: projectId,
    p_title: requireString(formData, "title"),
    p_type: optionalString(formData, "type") ?? "task",
    p_priority: optionalString(formData, "priority") ?? "normal",
    p_description: optionalString(formData, "description"),
  });

  redirect(withError(`/w/${orgId}/tracker/${projectId}`, error?.message));
}

export async function updateTrackerItemStatus(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const itemId = requireString(formData, "itemId");
  const supabase = await authedClient();

  const { error } = await supabase.rpc("update_tracker_item", {
    p_item_id: itemId,
    p_status: requireString(formData, "status"),
  });

  redirect(withError(returnPath(formData, `/w/${orgId}/tracker`), error?.message));
}

export async function updateTrackerItemDetails(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const itemId = requireString(formData, "itemId");
  const supabase = await authedClient();

  const { error } = await supabase.rpc("update_tracker_item", {
    p_item_id: itemId,
    p_title: optionalString(formData, "title"),
    p_description: optionalString(formData, "description"),
    p_type: optionalString(formData, "type"),
    p_priority: optionalString(formData, "priority"),
  });

  redirect(withError(returnPath(formData, `/w/${orgId}/tracker`), error?.message));
}

export async function updateTrackerItemAssignee(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const itemId = requireString(formData, "itemId");
  const supabase = await authedClient();

  // Same "" -> explicit clear pattern as updateDealOwner (lib/crm/actions.ts)
  // — p_clear_assignee is the RPC's dedicated unassign flag since coalesce
  // alone can't distinguish "not given" from "set to null".
  const rawAssigneeId = formData.get("assignee_id");
  const assigneeId = typeof rawAssigneeId === "string" && rawAssigneeId.length > 0 ? rawAssigneeId : null;

  const { error } = await supabase.rpc("update_tracker_item", {
    p_item_id: itemId,
    ...(assigneeId !== null ? { p_assignee_id: assigneeId } : { p_clear_assignee: true }),
  });

  redirect(withError(returnPath(formData, `/w/${orgId}/tracker`), error?.message));
}

export async function archiveTrackerItem(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const itemId = requireString(formData, "itemId");
  const supabase = await authedClient();

  const { error } = await supabase.rpc("archive_tracker_item", { p_item_id: itemId });

  redirect(withError(returnPath(formData, `/w/${orgId}/tracker`), error?.message));
}

export async function restoreTrackerItem(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const itemId = requireString(formData, "itemId");
  const supabase = await authedClient();

  const { error } = await supabase.rpc("restore_tracker_item", { p_item_id: itemId });

  redirect(withError(returnPath(formData, `/w/${orgId}/tracker`), error?.message));
}

export async function deleteTrackerItem(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const itemId = requireString(formData, "itemId");
  const projectId = requireString(formData, "projectId");
  const supabase = await authedClient();

  const { error } = await supabase.rpc("delete_tracker_item", { p_item_id: itemId });

  // Deleting always lands back on the project board (not returnTo) — the
  // item no longer exists, so a returnTo carrying ?item=<deleted-id> would
  // just 404 the panel open again.
  redirect(withError(`/w/${orgId}/tracker/${projectId}`, error?.message));
}
