"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

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

function jobHref(orgId: string, workOrderId: string, tab: "check-in" | "packet", error?: string) {
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

  const { error } = await supabase.rpc("create_check_in", {
    p_work_order_id: workOrderId,
    p_crew_name: requireString(formData, "crew_name"),
    p_hours: optionalNumber(formData, "hours"),
    p_materials_used: optionalString(formData, "materials_used"),
    p_blockers: optionalString(formData, "blockers"),
  });

  if (error) {
    redirect(jobHref(orgId, workOrderId, "check-in", error.message));
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
    redirect(jobHref(orgId, workOrderId, "check-in", error.message));
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
    redirect(jobHref(orgId, workOrderId, "check-in", error.message));
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
    redirect(jobHref(orgId, workOrderId, "check-in", error.message));
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
    redirect(jobHref(orgId, workOrderId, "check-in", error.message));
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
    redirect(jobHref(orgId, workOrderId, "packet", error.message));
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
    redirect(jobHref(orgId, workOrderId, "packet", error.message));
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
    redirect(jobHref(orgId, workOrderId, "packet", error.message));
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
    redirect(jobHref(orgId, workOrderId, "packet", error.message));
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
    redirect(jobHref(orgId, workOrderId, "packet", error.message));
  }

  revalidateJob(orgId, workOrderId);
  redirect(jobHref(orgId, workOrderId, "packet"));
}
