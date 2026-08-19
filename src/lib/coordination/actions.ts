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

// Next's client-side Router Cache treats redirect(x) back to the route the
// form was already on as a no-op — this busts that cache entry first.
function revalidateWorkOrder(orgId: string, workOrderId: string) {
  revalidatePath(`/w/${orgId}/coordination/${workOrderId}`);
}

// A1.4 — void and restore on a master move its trades too, so revalidating
// only the page the form was on leaves every trade page showing a stale
// voided state. This busts the whole coordination subtree instead.
function revalidateCoordination(orgId: string) {
  revalidatePath(`/w/${orgId}/coordination`, "layout");
}

// A1.2 — the creation RPC is split: this one makes the job and its master work
// order. Trades are added under the master by createTradeWorkOrder below (A1.3a).
export async function createJobFromEstimate(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const estimateId = requireString(formData, "estimateId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  // Returns jsonb {job_id, master_work_order_id} — it creates two rows and both
  // ids are load-bearing, so there is no single uuid it could return instead.
  const { data, error } = await supabase.rpc("create_job_from_estimate", {
    p_estimate_id: estimateId,
  });

  const estimateHref = (message: string) =>
    `/w/${orgId}/estimating/${estimateId}?error=${encodeURIComponent(message)}`;

  if (error) {
    redirect(estimateHref(error.message));
  }

  const masterWorkOrderId = (data as { master_work_order_id?: string } | null)
    ?.master_work_order_id;

  // Without this the redirect below builds /coordination/undefined — a 404 that
  // reads as "the work order is missing" rather than "the call came back wrong".
  if (!masterWorkOrderId) {
    redirect(
      estimateHref(
        "work order was not created — create_job_from_estimate returned no master_work_order_id"
      )
    );
  }

  revalidateWorkOrder(orgId, masterWorkOrderId);
  redirect(workOrderHref(orgId, masterWorkOrderId));
}

// A1.3a. Creates a trade under a master. org_id, estimate_id and job_id are NOT
// parameters — create_trade_work_order reads all three off the master, which is
// what makes it impossible to land a trade in the wrong org or on the wrong job.
//
// Every invalid case (trade under a trade, half-specified assignee, duplicate
// active trade, predecessor from another job) is refused by the RPC with a
// readable message, and that message is what the user sees. Deliberately no
// client-side re-implementation of those rules: the RPC is the gate, and a
// second copy of the logic here would drift from it.
export async function createTradeWorkOrder(formData: FormData) {
  const orgId = requireString(formData, "orgId");
  const masterWorkOrderId = requireString(formData, "masterWorkOrderId");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  // Passed through as-is rather than via requireString: an empty trade is a
  // case the RPC already answers ("trade is required on a trade work order"),
  // and throwing here would replace that message with an error boundary.
  const trade = formData.get("trade");

  const { error } = await supabase.rpc("create_trade_work_order", {
    p_master_work_order_id: masterWorkOrderId,
    p_trade: typeof trade === "string" ? trade : "",
    p_assignee_type: optionalString(formData, "assignee_type"),
    p_assignee_ref: optionalString(formData, "assignee_ref"),
    p_predecessor_id: optionalString(formData, "predecessor_id"),
  });

  if (error) {
    redirect(workOrderHref(orgId, masterWorkOrderId, error.message));
  }

  // Back to the master, not into the new trade: trades are normally added
  // several at a time, and the master is where the list that proves it worked
  // is rendered.
  revalidateWorkOrder(orgId, masterWorkOrderId);
  redirect(workOrderHref(orgId, masterWorkOrderId));
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

  revalidateCoordination(orgId);
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

  revalidateCoordination(orgId);
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
  revalidateCoordination(orgId);
  redirect(`/w/${orgId}/coordination`);
}
