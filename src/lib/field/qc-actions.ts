"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { photoRef } from "@/lib/field/qc-data";
import { isQcKey, requirementByKey, type QcResult } from "@/lib/field/qc";
import { recordFieldEvent } from "@/lib/observability/field-events";
import { PHOTO_DATA_URL_CEILING } from "@/lib/field/photo";

// Recording a QC item.  Track X, X-W1.20, 2026-09-19.
//
// THE PHOTO TRAVELS THE PATH TRACK U FIXED. The browser shrinks it first
// (lib/field/photo.ts — a data URL over 1 MiB was silently truncated to
// 1,048,576 characters until 2026-09-16), and it is saved by the SAME
// add_check_in_photo() RPC the check-in photo picker uses. This file adds no
// second upload path, so there is no second place for that bug to come back.
// The QC row then stores a hash of that photo, never its name.
//
// Every outcome is a CODE on the URL (qc.ts), so no message from the database
// and no value from a link can put words on a crew screen.

function back(orgId: string, workOrderId: string, result: QcResult): never {
  redirect(`/w/${orgId}/field/${workOrderId}?tab=check-in&qc=${result}#qc`);
}

const MISSING = new Set(["42P01", "PGRST202", "PGRST205", "42883"]);

type Rpc = (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: { code?: string; message?: string } | null }>;

export async function recordQcItem(formData: FormData) {
  const orgId = String(formData.get("orgId") ?? "");
  const workOrderId = String(formData.get("workOrderId") ?? "");
  const key = String(formData.get("requirementKey") ?? "");
  const requirement = isQcKey(key) ? requirementByKey(key) : undefined;
  if (!requirement) back(orgId, workOrderId, "refused");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");
  const rpc = (supabase.rpc as unknown as Rpc).bind(supabase);

  let photo: string | null = null;
  let count: number | null = null;

  if (requirement.kind === "photo") {
    const dataUrl = String(formData.get("photo_data_url") ?? "");
    const checkInId = String(formData.get("checkInId") ?? "");
    // A QC photo hangs off today's check-in. Without one there is nothing to
    // attach it to, and saying so is better than inventing a check-in.
    if (!checkInId) back(orgId, workOrderId, "needs_check_in");
    if (!dataUrl.startsWith("data:image/")) back(orgId, workOrderId, "photo_failed");
    // MEASURED HERE, 2026-09-19, on a production build: a 1,200,023-character data
    // URL sent to this action arrives as exactly 1,048,576 characters — Track U's
    // truncation, which their fix prevents in the BROWSER. Without this line the
    // action would then record the requirement as satisfied by a corrupt photo,
    // which is worse than no photo: it stops anyone looking for the real one.
    if (dataUrl.length > PHOTO_DATA_URL_CEILING) back(orgId, workOrderId, "photo_too_large");

    const { error } = await rpc("add_check_in_photo", { p_check_in_id: checkInId, p_photo_data_url: dataUrl });
    if (error) back(orgId, workOrderId, error.code ? "photo_failed" : "unconfirmed");
    photo = photoRef(dataUrl);
  }

  if (requirement.kind === "count") {
    const raw = String(formData.get("count_value") ?? "").trim();
    const n = Number(raw);
    if (!/^\d{1,6}$/.test(raw) || !Number.isInteger(n) || n < 0 || n > 100_000) {
      back(orgId, workOrderId, "count_invalid");
    }
    count = n;
  }

  const { error } = await rpc("record_qc_item", {
    p_work_order_id: workOrderId,
    p_requirement_key: requirement.key,
    p_kind: requirement.kind,
    p_photo_ref: photo,
    p_count_value: count,
  });

  let result: QcResult = "recorded";
  if (error) result = MISSING.has(error.code ?? "") ? "not_enabled" : error.code ? "refused" : "unconfirmed";

  // Telemetry, bounded and never fatal (field-events.ts). A requirement key is a
  // code; no photo, name or number goes into the event.
  await recordFieldEvent(supabase, {
    orgId,
    event: "check_in_saved",
    workOrderId,
    outcome: result === "recorded" ? "qc_recorded" : "qc_not_recorded",
  });

  revalidatePath(`/w/${orgId}/field/${workOrderId}`);
  back(orgId, workOrderId, result);
}

export async function clearQcItem(formData: FormData) {
  const orgId = String(formData.get("orgId") ?? "");
  const workOrderId = String(formData.get("workOrderId") ?? "");
  const key = String(formData.get("requirementKey") ?? "");
  if (!isQcKey(key)) back(orgId, workOrderId, "refused");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const rpc = (supabase.rpc as unknown as Rpc).bind(supabase);
  const { error } = await rpc("clear_qc_item", { p_work_order_id: workOrderId, p_requirement_key: key });
  revalidatePath(`/w/${orgId}/field/${workOrderId}`);
  if (error) back(orgId, workOrderId, MISSING.has(error.code ?? "") ? "not_enabled" : error.code ? "refused" : "unconfirmed");
  back(orgId, workOrderId, "cleared");
}
