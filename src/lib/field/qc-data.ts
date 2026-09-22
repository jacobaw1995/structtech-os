import "server-only";
import { createHash } from "node:crypto";
import type { createClient } from "@/lib/supabase/server";
import type { QcRow } from "@/lib/field/qc";

// Reading the QC checklist's state.  Track X, X-W1.20, 2026-09-19; three states
// since 2026-09-21.
//
// THREE ANSWERS, NOT TWO. NEVER INFER "DOES NOT EXIST" FROM "CANNOT SEE."
//   on          — the table answered; `rows` is what has been done (possibly none).
//   off         — the table does not exist on this project (the migration is not
//                 applied). Only the two codes that MEAN that produce it.
//   unreadable  — anything else: the database refused, the token was bad, the
//                 request failed or took too long. A fact about the REQUEST, not
//                 about the world, so the screen must not turn it into "nothing
//                 done yet" (on) or "no checklist here" (off).
//
// Until 2026-09-21 every error that was not "table missing" came back as
// { enabled: true, rows: [] } — so a refused read rendered seven rows saying
// "Not done yet", telling a crew member something false about the roof. Measured
// against the live endpoint the same evening, after Track S applied qc_items
// (20260922004806, 20:48 EDT): a request without a valid user token answers
// 42501 "permission denied for table qc_items", and a malformed one answers
// PGRST301 "JWT cryptographic operation failed". Both are real, reachable
// answers from this table; both now read as `unreadable`.

/** The reference a QC row stores for a photo: sha256 of the data URL, 16 hex. */
export function photoRef(dataUrl: string): string {
  return createHash("sha256").update(dataUrl).digest("hex").slice(0, 16);
}

type Supabase = ReturnType<typeof createClient>;
export type QcRead =
  | { state: "on"; rows: QcRow[] }
  | { state: "off" }
  | { state: "unreadable"; reason: "refused" | "failed" | "timeout" };

/** The table-missing codes, and nothing else, mean "off". */
const TABLE_MISSING = new Set(["42P01", "PGRST205"]);

/**
 * Bounded: a crew member's job page waits at most this long for the checklist.
 * Data reads are otherwise unbounded in this app (bounded-fetch.ts bounds auth
 * only), and a stalled read here would stall the whole Check-in tab.
 */
export const QC_READ_BOUND_MS = 2500;

type QcQuery = (table: string) => {
  select: (columns: string) => {
    eq: (column: string, value: string) => {
      is: (column: string, value: null) => PromiseLike<{ data: QcRow[] | null; error: { code?: string } | null }>;
    };
  };
};

export async function fetchQcRows(supabase: Supabase, workOrderId: string): Promise<QcRead> {
  // BOUND to the client: an unbound `supabase.from` threw and 500'd the whole job
  // page (caught on a stubbed production build, 2026-09-19).
  const from = (supabase.from as unknown as QcQuery).bind(supabase);
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<QcRead>((resolve) => {
    timer = setTimeout(() => resolve({ state: "unreadable", reason: "timeout" }), QC_READ_BOUND_MS);
  });
  const read = (async (): Promise<QcRead> => {
    try {
      const { data, error } = await from("qc_items")
        .select("requirement_key,kind,photo_ref,count_value,occurred_at")
        .eq("work_order_id", workOrderId)
        .is("cleared_at", null);
      if (error) return TABLE_MISSING.has(error.code ?? "") ? { state: "off" } : { state: "unreadable", reason: "refused" };
      return { state: "on", rows: data ?? [] };
    } catch {
      return { state: "unreadable", reason: "failed" };
    }
  })();
  try {
    return await Promise.race([read, timeout]);
  } finally {
    clearTimeout(timer);
  }
}
