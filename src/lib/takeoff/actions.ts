"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// The take-off review's ONE write: set_take_off_decision(line, disposition,
// work order). Its refusals are Track S's sentences and are shown verbatim —
// they name the trade and the next step, and a paraphrase would lose both.
//
// What it refuses, read from the live body 2026-09-14, so the surface can avoid
// offering it (U-W1.6):
//   - a caller without view_financials, or without view_estimates
//   - a disposition outside material / not_material / undecided
//   - a line not on a job's estimate
//   - a trade on a line that is not decided material
//   - not_material or undecided while a material exists for the line
//   - material with no trade while a material exists for the line
// and, from the validate trigger, a work order that is not a live trade on the
// line's job.

export async function setTakeOffDecision(formData: FormData) {
  const orgId = formData.get("orgId");
  const masterWorkOrderId = formData.get("masterWorkOrderId");
  const lineId = formData.get("lineId");
  const disposition = formData.get("disposition");
  const workOrderRaw = formData.get("workOrderId");

  if (typeof orgId !== "string" || typeof masterWorkOrderId !== "string" || typeof lineId !== "string") {
    throw new Error("setTakeOffDecision: malformed form");
  }

  const back = `/w/${orgId}/coordination/${masterWorkOrderId}`;
  const anchor = `#line-${lineId}`;

  // Nothing chosen is a named cause, not a crash and not a default. The radios
  // are `required`, so this is reached only when the browser check is bypassed.
  if (typeof disposition !== "string" || disposition.length === 0) {
    redirect(
      `${back}?takeoffError=${encodeURIComponent(
        "Choose material or not material for this line — nothing was chosen, so nothing was saved."
      )}&line=${encodeURIComponent(lineId)}${anchor}`
    );
  }

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  // A trade is sent only with "material". Anything else sends null, because the
  // RPC refuses a work order on a line that is not material, and a hidden
  // select that still carries a value is exactly the re-send rule 8 is about.
  const workOrderId =
    disposition === "material" && typeof workOrderRaw === "string" && workOrderRaw.length > 0
      ? workOrderRaw
      : null;

  // RULE 8 — A RE-SEND IS NOT A DECISION. Measured 2026-09-14 (rolled back) on
  // the Fake Lead line: calling set_take_off_decision with the line's CURRENT
  // disposition and trade saves, and rewrites disposition_source from
  // `backfill` to `human` with a new decided_by and decided_at. This form always
  // re-sends the trade it was given, so "Save decision" with nothing changed
  // would turn an inferred decision into one a person made. The stored decision
  // is read here, and an unchanged submission writes nothing. (The RPC itself
  // reads NEW alone; reported to Track S.)
  const { data: stored, error: readError } = await supabase
    .from("take_off_lines")
    .select("disposition, trade_work_order_id, estimate_status")
    .eq("estimate_line_item_id", lineId)
    .not("estimate_status", "is", null);
  if (readError || !stored || stored.length !== 1) {
    redirect(
      `${back}?takeoffError=${encodeURIComponent(
        "The line's current decision could not be read, so nothing was saved. Reload and try again."
      )}&line=${encodeURIComponent(lineId)}${anchor}`
    );
  }
  const now = stored[0];
  const storedDisposition = now.disposition ?? "undecided";
  if (storedDisposition === disposition && (now.trade_work_order_id ?? null) === workOrderId) {
    redirect(`${back}?line=${encodeURIComponent(lineId)}&takeoffNotice=unchanged${anchor}`);
  }

  const { error } = await supabase.rpc("set_take_off_decision", {
    p_estimate_line_item_id: lineId,
    p_disposition: disposition,
    // Omitted rather than sent as null: the parameter defaults to null in SQL,
    // which is what the RPC reads as "no trade".
    ...(workOrderId ? { p_work_order_id: workOrderId } : {}),
  });

  revalidatePath(back);
  if (error) {
    redirect(`${back}?takeoffError=${encodeURIComponent(error.message)}&line=${encodeURIComponent(lineId)}${anchor}`);
  }
  redirect(`${back}?line=${encodeURIComponent(lineId)}${anchor}`);
}
