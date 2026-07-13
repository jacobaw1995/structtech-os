"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// Same conventions as src/lib/estimating/actions.ts: server actions
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

function workOrderHref(orgId: string, workOrderId: string, error?: string) {
  const qs = error ? `?error=${encodeURIComponent(error)}` : "";
  return `/w/${orgId}/coordination/${workOrderId}${qs}`;
}

// Same Router Cache rationale as revalidateEstimate in estimating/actions.ts
// — redirecting back to the page the form was already on is a no-op without
// this.
function revalidateWorkOrder(orgId: string, workOrderId: string) {
  revalidatePath(`/w/${orgId}/coordination/${workOrderId}`);
}

export async function createWorkOrderFromEstimate(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const estimateId = requireString(formData, "estimateId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { data: workOrderId, error } = await supabase.rpc(
    "create_work_order_from_estimate",
    { p_estimate_id: estimateId }
  );

  if (error) {
    redirect(
      `/w/${orgId}/estimating/${estimateId}?step=4&error=${encodeURIComponent(error.message)}`
    );
  }

  revalidateWorkOrder(orgId, workOrderId);
  redirect(workOrderHref(orgId, workOrderId));
}

export async function recordWorkOrderSignOff(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("record_work_order_sign_off", {
    p_work_order_id: workOrderId,
    p_notes: optionalString(formData, "notes"),
  });

  if (error) {
    redirect(workOrderHref(orgId, workOrderId, error.message));
  }

  revalidateWorkOrder(orgId, workOrderId);
  redirect(workOrderHref(orgId, workOrderId));
}

export async function addMaterialItem(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("add_material_item", {
    p_work_order_id: workOrderId,
    p_name: requireString(formData, "name"),
    p_quantity: optionalNumber(formData, "quantity"),
    p_ready_by: optionalString(formData, "ready_by"),
    p_sort_order: optionalNumber(formData, "sort_order"),
  });

  if (error) {
    redirect(workOrderHref(orgId, workOrderId, error.message));
  }

  revalidateWorkOrder(orgId, workOrderId);
  redirect(workOrderHref(orgId, workOrderId));
}

export async function updateMaterialItem(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");
  const materialItemId = requireString(formData, "materialItemId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("update_material_item", {
    p_material_item_id: materialItemId,
    p_name: optionalString(formData, "name"),
    p_quantity: optionalNumber(formData, "quantity"),
    p_ready_by: optionalString(formData, "ready_by"),
  });

  if (error) {
    redirect(workOrderHref(orgId, workOrderId, error.message));
  }

  revalidateWorkOrder(orgId, workOrderId);
  redirect(workOrderHref(orgId, workOrderId));
}

export async function deleteMaterialItem(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");
  const materialItemId = requireString(formData, "materialItemId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("delete_material_item", {
    p_material_item_id: materialItemId,
  });

  if (error) {
    redirect(workOrderHref(orgId, workOrderId, error.message));
  }

  revalidateWorkOrder(orgId, workOrderId);
  redirect(workOrderHref(orgId, workOrderId));
}

export async function addScheduleBlock(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("add_schedule_block", {
    p_work_order_id: workOrderId,
    p_crew_name: requireString(formData, "crew_name"),
    p_start_date: requireString(formData, "start_date"),
    p_end_date: requireString(formData, "end_date"),
  });

  if (error) {
    redirect(workOrderHref(orgId, workOrderId, error.message));
  }

  revalidateWorkOrder(orgId, workOrderId);
  redirect(workOrderHref(orgId, workOrderId));
}

export async function updateScheduleBlock(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");
  const scheduleBlockId = requireString(formData, "scheduleBlockId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("update_schedule_block", {
    p_schedule_block_id: scheduleBlockId,
    p_crew_name: optionalString(formData, "crew_name"),
    p_start_date: optionalString(formData, "start_date"),
    p_end_date: optionalString(formData, "end_date"),
  });

  if (error) {
    redirect(workOrderHref(orgId, workOrderId, error.message));
  }

  revalidateWorkOrder(orgId, workOrderId);
  redirect(workOrderHref(orgId, workOrderId));
}

export async function deleteScheduleBlock(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");
  const scheduleBlockId = requireString(formData, "scheduleBlockId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("delete_schedule_block", {
    p_schedule_block_id: scheduleBlockId,
  });

  if (error) {
    redirect(workOrderHref(orgId, workOrderId, error.message));
  }

  revalidateWorkOrder(orgId, workOrderId);
  redirect(workOrderHref(orgId, workOrderId));
}

export async function voidWorkOrder(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("void_work_order", {
    p_work_order_id: workOrderId,
  });

  if (error) {
    redirect(workOrderHref(orgId, workOrderId, error.message));
  }

  revalidateWorkOrder(orgId, workOrderId);
  redirect(workOrderHref(orgId, workOrderId));
}

export async function restoreWorkOrder(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("restore_work_order", {
    p_work_order_id: workOrderId,
  });

  if (error) {
    redirect(workOrderHref(orgId, workOrderId, error.message));
  }

  revalidateWorkOrder(orgId, workOrderId);
  redirect(workOrderHref(orgId, workOrderId));
}

export async function deleteWorkOrder(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const workOrderId = requireString(formData, "workOrderId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("delete_work_order", {
    p_work_order_id: workOrderId,
  });

  if (error) {
    redirect(workOrderHref(orgId, workOrderId, error.message));
  }

  // Unlike void/restore, the row is gone — nothing left at workOrderHref to
  // revalidate into. Back to the list.
  redirect(`/w/${orgId}/coordination`);
}
