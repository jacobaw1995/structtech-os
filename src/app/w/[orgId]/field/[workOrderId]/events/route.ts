import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { recordFieldEvent } from "@/lib/observability/field-events";

// Browser → field_events, for the one fact only the browser knows: when the job page
// became usable (`page_ready`, with the time it took). X-W1.19.
//
// The browser may send page_ready and NOTHING ELSE: every other event is recorded on
// the server where it happens, so a client cannot forge "opened" or "checked in".
// Always answers 204 — a beacon has no one to show an error to, and a crew member's
// phone must never retry telemetry in a loop.
export async function POST(
  request: NextRequest,
  { params }: { params: { orgId: string; workOrderId: string } }
) {
  try {
    const body = (await request.json().catch(() => null)) as {
      event?: unknown;
      durationMs?: unknown;
      clientSentAt?: unknown;
      queued?: unknown;
    } | null;
    if (body?.event === "page_ready") {
      const supabase = createClient();
      const {
        data: { session },
      } = await supabase.auth.getSession();
      if (session) {
        const sent = typeof body.clientSentAt === "string" && !Number.isNaN(Date.parse(body.clientSentAt))
          ? new Date(body.clientSentAt).toISOString()
          : null;
        await recordFieldEvent(supabase, {
          orgId: params.orgId,
          event: "page_ready",
          workOrderId: params.workOrderId,
          durationMs: typeof body.durationMs === "number" ? body.durationMs : null,
          // "queued": the phone was offline and sent it later — visible, not hidden.
          outcome: body.queued === true ? "sent_late" : "ok",
          clientSentAt: sent,
        });
      }
    }
  } catch {
    // telemetry never answers with an error
  }
  return new NextResponse(null, { status: 204 });
}
