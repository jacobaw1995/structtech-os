import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createOrgFileUploadUrl } from "@/lib/storage/org-files";
import {
  MAX_FILE_BYTES,
  isAllowedFileType,
  orgFilesEnabled,
  type FilesState,
} from "@/lib/storage/work-order-files-states";

// Issues a signed upload url for one office file on one work order. X-W1.15.
//
// A route handler, not a server action, because it must RETURN the url (server
// actions redirect and never return data — CLAUDE.md rule 6), and the file itself
// never passes through here (Vercel's 4.5 MB request cap; see org-files.ts).
//
// The checks below mirror the storage policy so the refusal arrives BEFORE a
// file is chosen and sent. They are not the control. The control is the
// storage.objects INSERT policy, which storage evaluates with this caller's JWT
// when it signs the url.
type Body = { filename?: unknown; size?: unknown; type?: unknown };
const state = (s: FilesState, status: number) => NextResponse.json({ state: s }, { status });

export async function POST(
  request: NextRequest,
  { params }: { params: { orgId: string; workOrderId: string } }
) {
  if (!orgFilesEnabled()) return state("off", 409);

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) return NextResponse.json({ state: "signed_out" }, { status: 401 });

  let body: Body;
  try {
    body = (await request.json()) as Body;
  } catch {
    return state("upload_failed", 400);
  }
  const filename = typeof body.filename === "string" ? body.filename : "";
  const size = typeof body.size === "number" ? body.size : -1;
  const type = typeof body.type === "string" ? body.type : "";
  if (!filename || size < 0) return state("upload_failed", 400);
  if (size > MAX_FILE_BYTES) return state("too_large", 413);
  if (!isAllowedFileType(type)) return state("wrong_type", 415);

  // The work order must be visible to this caller, in this org: the same fact the
  // policy's work_orders join checks. A crew member never gets here for a master
  // (fetch_work_order applies the crew gate), and gets refused below for a trade.
  const { data: fetched } = await supabase.rpc("fetch_work_order", {
    p_work_order_id: params.workOrderId,
  });
  const workOrder = fetched?.[0];
  if (!workOrder || workOrder.org_id !== params.orgId) return state("upload_refused", 403);

  const { data: canManage } = await supabase.rpc("can_view_master_work_order", {
    p_org_id: params.orgId,
  });
  if (canManage !== true) return state("upload_refused", 403);

  const result = await createOrgFileUploadUrl({
    orgId: params.orgId,
    category: "office-uploads",
    entityId: workOrder.id,
    filename,
  });
  if (!result.ok) return state(result.refused ? "upload_refused" : "upload_failed", result.refused ? 403 : 502);

  return NextResponse.json({ state: "ready", signedUrl: result.data.signedUrl });
}
