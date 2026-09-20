import "server-only";
import { createHash } from "node:crypto";
import type { createClient } from "@/lib/supabase/server";
import type { QcRow } from "@/lib/field/qc";

// Reading the QC checklist's state.  Track X, X-W1.20, 2026-09-19.
//
// qc_items is proposed to Track S (supabase/proposals/20260919_x_w1_20_qc_items.sql)
// and may not exist yet. "Not switched on" is then a NAMED state, never an empty
// checklist — an empty list and a missing table must not look alike.

/** The reference a QC row stores for a photo: sha256 of the data URL, 16 hex. */
export function photoRef(dataUrl: string): string {
  return createHash("sha256").update(dataUrl).digest("hex").slice(0, 16);
}

type Supabase = ReturnType<typeof createClient>;
type Rows = { enabled: true; rows: QcRow[] } | { enabled: false };

type QcQuery = (table: string) => {
  select: (columns: string) => {
    eq: (column: string, value: string) => {
      is: (column: string, value: null) => PromiseLike<{ data: QcRow[] | null; error: { code?: string } | null }>;
    };
  };
};

export async function fetchQcRows(supabase: Supabase, workOrderId: string): Promise<Rows> {
  // BOUND, and wrapped. An unbound `supabase.from` threw "Cannot read properties
  // of undefined (reading 'rest')" and took the whole job page down with a 500 —
  // caught on a stubbed production build, 2026-09-19. A crew member's screen must
  // never be lost to the checklist that is meant to help them, so every failure
  // here degrades to "not switched on" and the page still renders.
  const from = (supabase.from as unknown as QcQuery).bind(supabase);
  try {
    const { data, error } = await from("qc_items")
      .select("requirement_key,kind,photo_ref,count_value,occurred_at")
      .eq("work_order_id", workOrderId)
      .is("cleared_at", null);
    // 42P01 undefined_table / PGRST205 unknown relation — the migration is not applied.
    if (error) {
      return error.code === "42P01" || error.code === "PGRST205" ? { enabled: false } : { enabled: true, rows: [] };
    }
    return { enabled: true, rows: data ?? [] };
  } catch {
    return { enabled: false };
  }
}
