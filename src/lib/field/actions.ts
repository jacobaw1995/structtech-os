"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { classifyFieldError, type FieldError } from "@/lib/field/field-errors";
import { recordFieldEvent } from "@/lib/observability/field-events";

// Same conventions as src/lib/coordination/actions.ts: server actions
// redirect(), never return data (CLAUDE.md rule 6); every mutation goes
// through a security-definer RPC (rule 3).

function requireString(formData: FormData, key: string): string {
  const value = formData.get(key);
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`missing required field: ${key}`);
  }
  return value;
}

/** Trimmed, and may be empty — the database decides whether empty is allowed. */
function trimmed(formData: FormData, key: string): string {
  const value = formData.get(key);
  return typeof value === "string" ? value.trim() : "";
}

function optionalString(formData: FormData, key: string): string | undefined {
  const value = formData.get(key);
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function optionalNumber(formData: FormData, key: string): number | undefined {
  const raw = optionalString(formData, key);
  return raw === undefined ? undefined : Number(raw);
}

// `error` is a CODE (lib/field/field-errors.ts), never a message: the job page
// looks it up and renders our sentence, so no URL can put words on a crew screen.
function jobHref(orgId: string, workOrderId: string, tab: "check-in" | "packet", error?: FieldError) {
  const params = new URLSearchParams({ tab });
  if (error) params.set("error", error);
  return `/w/${orgId}/field/${workOrderId}?${params.toString()}`;
}

// Same Router Cache rationale as revalidateWorkOrder in coordination/actions.ts.
function revalidateJob(orgId: string, workOrderId: string) {
  revalidatePath(`/w/${orgId}/field/${workOrderId}`);
}

export async function createCheckIn(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { data: checkInId, error } = await supabase.rpc("create_check_in", {
    p_work_order_id: workOrderId,
    // U-W1.28 — TRIMMED, AND DELIBERATELY ALLOWED TO BE EMPTY. The browser's
    // `required` blocks an empty box but not three spaces, and requireString()
    // accepted "   " as a string of length 3 and threw only on a genuinely
    // absent field — so whitespace reached the database, which refused it with
    // 'choose a crew, or type who is doing the work' (hint crew_required).
    // Sending the trimmed value keeps ONE authority on what counts as a crew
    // name: S's raise. The alternative — an HTML `pattern` — would block the
    // submit behind a browser-native bubble whose wording we do not control,
    // which is a second copy of the refusal and a worse one.
    p_crew_name: trimmed(formData, "crew_name"),
    p_hours: optionalNumber(formData, "hours"),
    p_materials_used: optionalString(formData, "materials_used"),
    p_blockers: optionalString(formData, "blockers"),
  });

  // X-W1.19: the outcome, durably. A code, never the database's message. Bounded
  // and never throws, so the check-in's own redirect is unaffected either way.
  await recordFieldEvent(supabase, {
    orgId,
    event: error ? "check_in_failed" : "check_in_saved",
    workOrderId,
    subjectRef: !error && typeof checkInId === "string" ? checkInId : null,
    outcome: error ? (error.code ? "refused" : "unconfirmed") : "ok",
  });

  if (error) {
    redirect(jobHref(orgId, workOrderId, "check-in", classifyFieldError(error)));
  }

  revalidateJob(orgId, workOrderId);
  redirect(jobHref(orgId, workOrderId, "check-in"));
}

export async function updateCheckIn(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");
  const checkInId = requireString(formData, "checkInId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("update_check_in", {
    p_check_in_id: checkInId,
    p_crew_name: optionalString(formData, "crew_name"),
    p_hours: optionalNumber(formData, "hours"),
    p_materials_used: optionalString(formData, "materials_used"),
    p_blockers: optionalString(formData, "blockers"),
  });

  if (error) {
    redirect(jobHref(orgId, workOrderId, "check-in", classifyFieldError(error)));
  }

  revalidateJob(orgId, workOrderId);
  // "NOT RECORDED" IS NOT ZERO, AND AN EMPTIED BOX IS NOT A CLEAR.
  // update_check_in writes `hours = coalesce(p_hours, hours)`, so a blank hours
  // field keeps the old figure; clearing is its own action (clearCheckInHours
  // below, Track S's clear_check_in_hours). If a recorded figure was submitted
  // empty, say so rather than let the old number reappear as if it were saved.
  const hoursNow = formData.get("hours");
  const hoursWas = formData.get("hours_was");
  if (hoursNow === "" && typeof hoursWas === "string" && hoursWas !== "") {
    redirect(jobHref(orgId, workOrderId, "check-in", "hours_use_clear"));
  }
  redirect(jobHref(orgId, workOrderId, "check-in"));
}

// Hours back to "not recorded" (NULL) — never 0. Track S's clear_check_in_hours:
// the author or the office tier; on an already-empty value it writes nothing.
export async function clearCheckInHours(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");
  const checkInId = requireString(formData, "checkInId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("clear_check_in_hours", { p_check_in_id: checkInId });
  if (error) {
    redirect(jobHref(orgId, workOrderId, "check-in", classifyFieldError(error)));
  }

  revalidateJob(orgId, workOrderId);
  redirect(jobHref(orgId, workOrderId, "check-in"));
}

export async function deleteCheckIn(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");
  const checkInId = requireString(formData, "checkInId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("delete_check_in", {
    p_check_in_id: checkInId,
  });

  if (error) {
    redirect(jobHref(orgId, workOrderId, "check-in", classifyFieldError(error)));
  }

  revalidateJob(orgId, workOrderId);
  redirect(jobHref(orgId, workOrderId, "check-in"));
}

export async function addCheckInPhoto(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");
  const checkInId = requireString(formData, "checkInId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("add_check_in_photo", {
    p_check_in_id: checkInId,
    p_photo_data_url: requireString(formData, "photo_data_url"),
  });

  if (error) {
    redirect(jobHref(orgId, workOrderId, "check-in", classifyFieldError(error)));
  }

  revalidateJob(orgId, workOrderId);
  redirect(jobHref(orgId, workOrderId, "check-in"));
}

export async function removeCheckInPhoto(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");
  const checkInId = requireString(formData, "checkInId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("remove_check_in_photo", {
    p_check_in_id: checkInId,
    p_photo_data_url: requireString(formData, "photo_data_url"),
  });

  if (error) {
    redirect(jobHref(orgId, workOrderId, "check-in", classifyFieldError(error)));
  }

  revalidateJob(orgId, workOrderId);
  redirect(jobHref(orgId, workOrderId, "check-in"));
}

export async function updateProductionPacketNotes(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");
  const productionPacketId = requireString(formData, "productionPacketId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("update_production_packet_notes", {
    p_production_packet_id: productionPacketId,
    p_notes: optionalString(formData, "notes") ?? "",
  });

  if (error) {
    redirect(jobHref(orgId, workOrderId, "packet", classifyFieldError(error)));
  }

  revalidateJob(orgId, workOrderId);
  redirect(jobHref(orgId, workOrderId, "packet"));
}

export async function deleteProductionPacket(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");
  const productionPacketId = requireString(formData, "productionPacketId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("delete_production_packet", {
    p_production_packet_id: productionPacketId,
  });

  if (error) {
    redirect(jobHref(orgId, workOrderId, "packet", classifyFieldError(error)));
  }

  revalidateJob(orgId, workOrderId);
  redirect(jobHref(orgId, workOrderId, "packet"));
}

export async function addProductionPacketCallout(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");
  const productionPacketId = requireString(formData, "productionPacketId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("add_production_packet_callout", {
    p_production_packet_id: productionPacketId,
    p_label: requireString(formData, "label"),
    p_detail: optionalString(formData, "detail"),
  });

  if (error) {
    redirect(jobHref(orgId, workOrderId, "packet", classifyFieldError(error)));
  }

  revalidateJob(orgId, workOrderId);
  redirect(jobHref(orgId, workOrderId, "packet"));
}

export async function updateProductionPacketCallout(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");
  const productionPacketId = requireString(formData, "productionPacketId");
  const calloutId = requireString(formData, "calloutId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("update_production_packet_callout", {
    p_production_packet_id: productionPacketId,
    p_callout_id: calloutId,
    p_label: optionalString(formData, "label"),
    p_detail: optionalString(formData, "detail"),
  });

  if (error) {
    redirect(jobHref(orgId, workOrderId, "packet", classifyFieldError(error)));
  }

  revalidateJob(orgId, workOrderId);
  redirect(jobHref(orgId, workOrderId, "packet"));
}

export async function deleteProductionPacketCallout(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");
  const productionPacketId = requireString(formData, "productionPacketId");
  const calloutId = requireString(formData, "calloutId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("delete_production_packet_callout", {
    p_production_packet_id: productionPacketId,
    p_callout_id: calloutId,
  });

  if (error) {
    redirect(jobHref(orgId, workOrderId, "packet", classifyFieldError(error)));
  }

  revalidateJob(orgId, workOrderId);
  redirect(jobHref(orgId, workOrderId, "packet"));
}
