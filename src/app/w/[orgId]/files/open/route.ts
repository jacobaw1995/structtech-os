import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { signOrgFile } from "@/lib/storage/org-files";
import { parseOrgFilePath } from "@/lib/storage/paths";
import { fileRef, recordFieldEvent } from "@/lib/observability/field-events";

// Open one office file. X-W1.19.
// A link here instead of a pre-signed url does two things: the url is signed at the
// moment of opening (60 s), so a page left open on a phone for an hour still opens
// its files; and the open is recorded (file_opened, by a hash of the path — never
// the filename). The recording is bounded and cannot stop the file opening.
export async function GET(request: NextRequest, { params }: { params: { orgId: string } }) {
  const path = request.nextUrl.searchParams.get("path") ?? "";
  const parsed = parseOrgFilePath(path);
  const back = (code: string) => {
    const wo = parsed?.entityId;
    const where = request.nextUrl.searchParams.get("from") === "office" ? "coordination" : "field";
    const target = wo ? `/w/${params.orgId}/${where}/${wo}?${where === "field" ? "tab=packet&" : ""}files=${code}#files` : `/w/${params.orgId}`;
    return NextResponse.redirect(new URL(target, request.url), 303);
  };
  if (!parsed || parsed.orgId !== params.orgId) return back("open_failed");

  const signed = await signOrgFile({ orgId: params.orgId, path, expiresInSeconds: 60 });
  const supabase = createClient();
  await recordFieldEvent(supabase, {
    orgId: params.orgId,
    event: "file_opened",
    workOrderId: parsed.entityId,
    subjectRef: fileRef(path),
    outcome: signed.ok ? "ok" : "refused",
  });
  if (!signed.ok) return back("open_failed");
  return NextResponse.redirect(signed.data.url, 303);
}
