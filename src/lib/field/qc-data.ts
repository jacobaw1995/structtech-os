import "server-only";
import { createHash } from "node:crypto";
import type { createClient } from "@/lib/supabase/server";
import type { QcRow } from "@/lib/field/qc";

// Reading the QC checklist's state.  Track X, X-W1.20, 2026-09-19; three states
// since 2026-09-21.
//
// qc_items is proposed to Track S (supabase/proposals/20260919_x_w1_20_qc_items.sql)
// and may not exist yet. "Not switched on" is then a NAMED state, never an empty
// checklist — an empty list and a missing table must not look alike.
//
// U-W1.30 (2026-09-23) — AND THERE IS A THIRD ANSWER, WHICH WAS BEING GIVEN AS
// ONE OF THE OTHER TWO. This function had two outcomes and three causes:
//   · the table is absent            -> { enabled: false }   correct
//   · the call THREW                 -> { enabled: false }   WRONG: a failure
//       reported as a configuration fact, so a crew read "the QC checklist isn't
//       switched on" when the truth was "we could not ask".
//   · any other PostgREST error      -> { enabled: true, rows: [] }   WORSE: an
//       unreadable checklist rendered as EVERY REQUIREMENT OUTSTANDING. That is
//       "does not exist" inferred from "cannot see", on the screen a crew uses
//       to decide whether they may leave the roof.
// Three causes, three answers. `unreadable` is now its own state all the way to
// the screen, and the panel neither claims the checks are done nor claims they
// are outstanding.
//
// qc_items EXISTS in production as of migration 20260922221943, so `not_enabled`
// should no longer be reachable there. It is kept because a branch that cannot
// happen today is exactly the branch that happens after the next rollback.
//
// THE EVIDENCE, measured by Track X against the live endpoint on 2026-09-21 after
// qc_items was applied (20260922004806, 20:48 EDT) — reconciled here 2026-09-25,
// where U and X had independently built this same three-state read and the two
// were merged: a request without a valid user token answers 42501 "permission
// denied for table qc_items", and a malformed one answers PGRST301 "JWT
// cryptographic operation failed". Both are real, reachable answers from this
// table, and neither means the table is absent — so only the two codes that MEAN
// absent produce `not_enabled`, and everything else is `unreadable` with the
// reason kept.

/** The reference a QC row stores for a photo: sha256 of the data URL, 16 hex. */
export function photoRef(dataUrl: string): string {
  return createHash("sha256").update(dataUrl).digest("hex").slice(0, 16);
}

type Supabase = ReturnType<typeof createClient>;
export type QcRead =
  | { state: "ok"; rows: QcRow[] }
  /** The table is not there: this deployment has no QC checklist at all. */
  | { state: "not_enabled" }
  /** We could not ask. Says nothing about what is or is not recorded. */
  | { state: "unreadable"; reason: "refused" | "failed" | "timeout" };

/** The table-missing codes, and nothing else, mean "not_enabled". */
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
  // BOUND, and wrapped, twice over. An unbound `supabase.from` threw "Cannot read
  // properties of undefined (reading 'rest')" and took the whole job page down
  // with a 500 — caught on a stubbed production build, 2026-09-19. A STALL is the
  // other half: the read is raced against QC_READ_BOUND_MS so a hung request
  // cannot hold the Check-in tab. A crew member's screen must never be lost to
  // the checklist that is meant to help them, so every failure here degrades to a
  // NAMED state and the page still renders. (It used to degrade to "not switched
  // on" for every cause; see the note above.)
  const from = (supabase.from as unknown as QcQuery).bind(supabase);
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<QcRead>((resolve) => {
    timer = setTimeout(() => resolve({ state: "unreadable", reason: "timeout" }), QC_READ_BOUND_MS);
  });
  const read = (async (): Promise<QcRead> => {
    try {
      // first_occurred_at / first_actor_id added by 20260922221943 — the live row
      // carries BOTH the first attestation and the latest, and they are two facts.
      // The surface shows the first and says so (see QcPanel).
      const { data, error } = await from("qc_items")
        .select("requirement_key,kind,photo_ref,count_value,occurred_at,first_occurred_at")
        .eq("work_order_id", workOrderId)
        .is("cleared_at", null);
      // 42P01 undefined_table / PGRST205 unknown relation — the migration is not applied.
      if (error) return TABLE_MISSING.has(error.code ?? "") ? { state: "not_enabled" } : { state: "unreadable", reason: "refused" };
      return { state: "ok", rows: data ?? [] };
    } catch {
      // A throw is a failure to ask, not an answer about configuration.
      return { state: "unreadable", reason: "failed" };
    }
  })();
  try {
    return await Promise.race([read, timeout]);
  } finally {
    clearTimeout(timer);
  }
}
