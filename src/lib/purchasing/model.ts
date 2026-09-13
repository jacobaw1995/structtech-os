import type { Database } from "@/lib/supabase/database.types";

export type PurchaseOrder = Database["public"]["Tables"]["purchase_orders"]["Row"];
export type PurchaseOrderLine = Database["public"]["Tables"]["purchase_order_lines"]["Row"];
export type PurchaseOrderLinePromise =
  Database["public"]["Tables"]["purchase_order_line_promises"]["Row"];

/**
 * A2.3 purchase orders — the rules the SURFACE has to obey, kept next to the
 * types they came from.
 *
 * Everything here was verified against the applied migration
 * `20260907230009_a2_3_purchase_orders`, not against the proposal that
 * preceded it. The types above are Track S's, generated from
 * information_schema — this file adds no types of its own, on purpose. A
 * hand-written PO type would be a fifth mirror.
 */

/**
 * THE FOUR STATUSES, AND THERE IS NO `received`.
 *
 * The CHECK constraint is exactly ('draft','sent','confirmed','cancelled').
 * A2.5 owes the terminal state. Inventing "received" in the UI would put a
 * word on screen the database will refuse, which is the defect U-W1.6 closed
 * on the scheduling surface.
 */
export const PO_STATUSES = ["draft", "sent", "confirmed", "cancelled"] as const;
export type PoStatus = (typeof PO_STATUSES)[number];

export function isPoStatus(v: string): v is PoStatus {
  return (PO_STATUSES as readonly string[]).includes(v);
}

export const PO_STATUS_LABEL: Record<PoStatus, string> = {
  draft: "Draft",
  sent: "Sent",
  confirmed: "Confirmed",
  cancelled: "Cancelled",
};

/**
 * What a status MEANS, in the supplier's terms rather than the column's.
 * Shown next to the control that changes it, because "confirmed" alone does
 * not say who confirmed what.
 */
export const PO_STATUS_MEANING: Record<PoStatus, string> = {
  draft: "Not sent yet. Nothing here is committed to the supplier.",
  sent: "Sent to the supplier. No promise back yet.",
  confirmed: "The supplier has confirmed it.",
  cancelled: "Withdrawn. Its promised dates stop counting toward ready-by.",
};

/**
 * CANCELLATION LIVES ON THE PURCHASE ORDER, NOT THE LINE.
 *
 * `purchase_order_lines` has no status column at all. The ready-by derivation
 * reads `max(promised_date) ... where po.status <> 'cancelled'`, so a line
 * stops counting only because its PO was cancelled. The surface therefore
 * offers "cancel this purchase order" and never "cancel this line" — a line is
 * removed by deleting it, which is a different act with a different meaning.
 */
export const CANCELLATION_IS_ON_THE_HEADER = true;

/**
 * A PO WITH NO JOB CANNOT LEAVE DRAFT — and, since 2026-09-10, it can be fixed.
 *
 * `job_id` is nullable and `create_purchase_order` accepts null. The draft-exit
 * rule in update_purchase_order refuses ANY status other than draft while the
 * effective job is null — including `cancelled`, because cancelling is also
 * leaving draft. So a jobless draft has exactly two ways forward: attach a job
 * (optionally moving status in the same call), or delete it.
 *
 * HISTORY: until migration 20260910215139 there was no way to attach a job
 * after creation — job_id was written only at INSERT — and the refusal
 * string's advice ("Attach it to a job first") named an action the API did not
 * implement. The surface refused to offer jobless creation for that reason,
 * and for a second one: the create path inferred the tenant from
 * `limit 1` over the caller's memberships. Both are closed at the database.
 */
export function isStuckInDraft(po: Pick<PurchaseOrder, "job_id" | "status">): boolean {
  return po.job_id === null && po.status === "draft";
}

/**
 * NO MONEY. NOT ANYWHERE, AND NOT IMPLIED.
 *
 * The only numeric column across both PO tables is `quantity_ordered`. There
 * is no cost, price, total, or unit_cost, and A5.4 owes it. So the surface
 * shows no currency, no blank "cost" cell, and no "pricing coming soon" — an
 * empty column that looks like it is waiting for a number is a promise the
 * schema has not made.
 *
 * This is also why the three PO tables are safe for a crew to read: there is
 * no money on them for constraint 7 to protect. If A5.4 adds a cost column,
 * a `can_view_financials` RESTRICTIVE policy has to land in the same
 * migration, and this constant is where to come looking.
 */
export const PO_HAS_NO_MONEY = true;

/**
 * The promise history, from the append-only table.
 *
 * `purchase_order_line_promises` has SELECT and INSERT policies and NO update
 * or delete policy at all, and `update_purchase_order_line` inserts a row only
 * when the date actually changes. So the row count is the number of DISTINCT
 * dates that have been promised, and "they moved it three times" is a fact the
 * surface can state rather than an impression.
 *
 * Returns the promises oldest-first, which is the order a reader needs: the
 * first is what was originally promised, the last is what is promised now.
 *
 * A LINE ALWAYS HAS AT LEAST ONE PROMISE ROW: `add_purchase_order_line`
 * inserts one unconditionally, even when no date was given — recording
 * "ordered, no date yet" as a fact rather than as an absence. So an empty
 * history is not a state the surface has to design for, and `timesMoved` is
 * exactly `count - 1`.
 */
export function promiseHistory(
  promises: PurchaseOrderLinePromise[],
  lineId: string
): PurchaseOrderLinePromise[] {
  return promises
    .filter((p) => p.purchase_order_line_id === lineId)
    .sort((a, b) => a.recorded_at.localeCompare(b.recorded_at));
}

/** How many times a promised date has MOVED — one fewer than the row count. */
export function timesMoved(count: number): number {
  return Math.max(0, count - 1);
}

/**
 * HOW A JOB IS NAMED on a purchase order surface — one definition, used by
 * both the org-level picker and the PO page, so the two cannot drift into
 * calling the same job two different things.
 *
 * `jobs` has no title column. The customer (estimate company, else contact)
 * plus the service address is how a roofer refers to a job, and the address
 * is where the supplier delivers — the fact a PO most needs to be right about.
 */
export function jobLabel(
  job: {
    created_at: string;
    service_address_street: string | null;
    service_address_city: string | null;
    service_address_state: string | null;
    service_address_zip: string | null;
  },
  estimate: { company: string | null; contact_name: string | null } | null
): string {
  const who = estimate?.company?.trim() || estimate?.contact_name?.trim() || null;
  const where = [
    job.service_address_street,
    job.service_address_city,
    job.service_address_state,
    job.service_address_zip,
  ]
    .filter((p): p is string => Boolean(p && p.trim()))
    .join(", ");
  return (
    [who, where].filter(Boolean).join(" · ") ||
    `Job created ${new Date(job.created_at).toLocaleDateString("en-US", {
      month: "short",
      day: "numeric",
    })}`
  );
}
