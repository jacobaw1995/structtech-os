"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { classifyFieldError, type FieldError } from "@/lib/field/field-errors";
import { isSpecialTripReason } from "@/lib/field/special-trip";
import { todayInNewYork } from "@/lib/home/model";

// RECORDING A SPECIAL TRIP. Track U, U-W1.42, 2026-09-29.
//
// The panel was built to shape on 2026-09-25 and deliberately NOT mounted,
// because the log did not exist and a control that appears to record something
// and does not is worse than no control. S landed 20260929025035 and the hold
// is released.
//
// THE DATE, AND WHY THE SURFACE SENDS ONE EVEN THOUGH IT NEED NOT.
// `p_occurred_on` defaults NULL and the applied function COALESCES a null to
// `(now() at time zone 'America/New_York')::date` — it does not refuse it. So
// sending nothing would already be correct. The surface sends a date anyway,
// derived the SAME way on the server (todayInNewYork()), for one reason: two
// places now agree on the crew's calendar day instead of one of them being
// silent, and if this action is ever called from somewhere that computes a
// date differently the disagreement shows up here rather than in a row.
//
// IT IS THE SERVER'S NEW YORK DATE, NEVER THE BROWSER'S. A phone with a wrong
// timezone would otherwise date a trip to the wrong day, and a special trip is
// COUNTED — "nine trips back for missing material last month" is a number
// somebody acts on, and a day either side of a month boundary moves it.

function optionalStr(formData: FormData, key: string): string | undefined {
  const v = formData.get(key);
  return typeof v === "string" && v.trim().length > 0 ? v : undefined;
}

function str(formData: FormData, key: string): string {
  const v = formData.get(key);
  return typeof v === "string" ? v : "";
}

function jobHref(orgId: string, workOrderId: string, error?: FieldError) {
  const qs = new URLSearchParams({ tab: "check-in" });
  if (error) qs.set("error", error);
  return `/w/${orgId}/field/${workOrderId}?${qs.toString()}`;
}

/**
 * U-W1.47 (2026-10-01) — WHERE TO COME BACK TO WHEN THE CALLER IS THE OFFICE.
 *
 * The office now reads these trips on the coordination work order, and the
 * office has no `field` module — redirecting them to /w/<org>/field/... after a
 * delete would be bounced by requireModuleAccess back to the workspace root.
 * Same seam, same shape and same guard as the production packet's returnTo
 * (U-W1.36): CHECKED, not trusted — a relative path inside this org's own
 * workspace, so a crafted form cannot turn a delete into an open redirect.
 */
function returnHref(formData: FormData, orgId: string, fallback: string, error?: FieldError): string {
  const raw = formData.get("returnTo");
  const prefix = `/w/${orgId}/`;
  const safe =
    typeof raw === "string" && raw.startsWith(prefix) && !raw.startsWith("//") && !raw.includes("://")
      ? raw
      : null;
  if (!safe) return fallback;
  return error ? `${safe}${safe.includes("?") ? "&" : "?"}error=${error}` : safe;
}

async function client() {
  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");
  return supabase;
}

export async function recordSpecialTrip(formData: FormData) {
  const orgId = str(formData, "orgId");
  const workOrderId = str(formData, "workOrderId");
  const reason = str(formData, "reason");

  // A code this surface does not know never reaches the database. S refuses it
  // too (special_trip_reason_required) — this is the cheaper half of the same
  // check, not a second opinion about what the codes are.
  if (!isSpecialTripReason(reason)) {
    redirect(jobHref(orgId, workOrderId, "special_trip_reason_required"));
  }

  const supabase = await client();
  const { error } = await supabase.rpc("record_special_trip", {
    p_work_order_id: workOrderId,
    p_reason_code: reason,
    p_occurred_on: todayInNewYork(),
    // U-W1.54 — ONE ARGUMENT. S's function returns the ORIGINAL trip's id when
    // it has seen this token, so a resend of a request whose answer was lost
    // records nothing and still reads as recorded. optionalStr, so a form that
    // somehow sends nothing sends NULL — which the function documents as "no
    // token, never deduplicated", i.e. yesterday's behaviour unchanged rather
    // than a blank string posing as a token.
    p_client_token: optionalStr(formData, "client_token"),
  });

  if (error) redirect(jobHref(orgId, workOrderId, classifyFieldError(error)));
  revalidatePath(`/w/${orgId}/field/${workOrderId}`);
  redirect(jobHref(orgId, workOrderId));
}

export async function deleteSpecialTrip(formData: FormData) {
  const orgId = str(formData, "orgId");
  const workOrderId = str(formData, "workOrderId");

  const supabase = await client();
  const { error } = await supabase.rpc("delete_special_trip", {
    p_special_trip_id: str(formData, "specialTripId"),
  });

  if (error) {
    redirect(returnHref(formData, orgId, jobHref(orgId, workOrderId, classifyFieldError(error)), classifyFieldError(error)));
  }
  revalidatePath(`/w/${orgId}/field/${workOrderId}`);
  revalidatePath(`/w/${orgId}/coordination/${workOrderId}`);
  redirect(returnHref(formData, orgId, jobHref(orgId, workOrderId)));
}
