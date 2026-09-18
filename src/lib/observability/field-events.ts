import "server-only";
import { createHash } from "node:crypto";
import type { createClient } from "@/lib/supabase/server";

// Durable field telemetry.  Track X, X-W1.19, 2026-09-17. Pilot 2026-10-07.
//
// WHY NOT LOGS. Runtime logs on this Vercel plan last one hour, so a question asked
// the morning after the pilot ("did the crew open the job?") has no answer there.
// Events go to public.field_events through record_field_event() — proposed to Track S
// (supabase/proposals/20260917_x_w1_19_field_events.sql), proved on a local fixture.
//
// TWO RULES, BOTH MECHANICAL:
//   1. A RECORD THAT FAILS NEVER FAILS WHAT THE CREW WAS DOING. recordFieldEvent()
//      never throws and never takes longer than RECORD_BOUND_MS; every outcome is a
//      returned value the caller is free to ignore. Until the migration is applied
//      the RPC does not exist and every call returns "not_recording" — silently, to
//      the crew.
//   2. NO DOLLARS, NO CUSTOMER DATA. The argument types below admit only ids, event
//      codes, a short lower-case outcome code, a hex reference and integers — and
//      the table's column types admit nothing else either. A file is referenced by
//      fileRef(path), a 16-hex hash, because filenames carry whatever was typed.

export type FieldEvent =
  | "signed_in"
  | "work_order_opened"
  | "packet_opened"
  | "page_ready"
  | "file_opened"
  | "file_removed"
  | "check_in_saved"
  | "check_in_failed";

export type RecordOutcome = "recorded" | "not_recording" | "refused" | "failed" | "timeout";

/** Bounded: a telemetry write may add at most this much to any request. */
export const RECORD_BOUND_MS = 800;

const OUTCOME_RE = /^[a-z_]{1,40}$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** A stable, non-reversible reference to a stored file: never its name. */
export function fileRef(path: string): string {
  return createHash("sha256").update(path).digest("hex").slice(0, 16);
}

type Supabase = ReturnType<typeof createClient>;
type Rpc = (fn: string, args: Record<string, unknown>) => PromiseLike<{ error: { code?: string; message?: string } | null }>;

export async function recordFieldEvent(
  supabase: Supabase,
  e: {
    orgId: string | null;
    event: FieldEvent;
    workOrderId?: string | null;
    subjectRef?: string | null;
    outcome?: string | null;
    durationMs?: number | null;
    clientSentAt?: string | null;
  }
): Promise<RecordOutcome> {
  try {
    // Refuse anything that is not an id or a code BEFORE it leaves the process, so a
    // caller mistake cannot even be attempted as a write.
    if (e.orgId !== null && !UUID_RE.test(e.orgId)) return "refused";
    if (e.workOrderId && !UUID_RE.test(e.workOrderId)) return "refused";
    if (e.outcome && !OUTCOME_RE.test(e.outcome)) return "refused";
    if (e.subjectRef && !/^([0-9a-f]{16}|[0-9a-f-]{36})$/.test(e.subjectRef)) return "refused";
    const duration =
      typeof e.durationMs === "number" && Number.isFinite(e.durationMs)
        ? Math.max(0, Math.min(600_000, Math.round(e.durationMs)))
        : null;

    // The RPC is not in the generated types until the migration exists.
    const rpc = (supabase.rpc as unknown as Rpc).bind(supabase);
    const call = Promise.resolve(
      rpc("record_field_event", {
        p_org_id: e.orgId,
        p_event: e.event,
        p_work_order_id: e.workOrderId ?? null,
        p_subject_ref: e.subjectRef ?? null,
        p_outcome: e.outcome ?? null,
        p_duration_ms: duration,
        p_client_sent_at: e.clientSentAt ?? null,
      })
    ).then(({ error }): RecordOutcome => {
      if (!error) return "recorded";
      // PGRST202: function not found — the migration has not been applied.
      if (error.code === "PGRST202" || error.code === "42883") return "not_recording";
      return "refused";
    });
    let timer: ReturnType<typeof setTimeout> | undefined;
    const bound = new Promise<RecordOutcome>((resolve) => {
      timer = setTimeout(() => resolve("timeout"), RECORD_BOUND_MS);
    });
    try {
      return await Promise.race([call.catch((): RecordOutcome => "failed"), bound]);
    } finally {
      clearTimeout(timer);
    }
  } catch {
    return "failed";
  }
}
