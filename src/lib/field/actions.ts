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
    p_crew_name: requireString(formData, "crew_name"),
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
  // U-W1.20 — "NOT RECORDED" IS NOT ZERO, AND A CLEARED BOX IS NOT A SAVE.
  // update_check_in writes `hours = coalesce(p_hours, hours)`, so a blank hours
  // field keeps the old figure (measured in its body 2026-09-17). If the row had
  // hours and the box was submitted empty, the save kept them — say so, instead
  // of letting the redirect repaint the old number as if nothing happened.
  const hoursNow = formData.get("hours");
  const hoursWas = formData.get("hours_was");
  if (hoursNow === "" && typeof hoursWas === "string" && hoursWas !== "") {
    redirect(jobHref(orgId, workOrderId, "check-in", "hours_not_cleared"));
  }
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
