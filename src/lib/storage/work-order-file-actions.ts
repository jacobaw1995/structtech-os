"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { deleteOrgFile } from "@/lib/storage/org-files";
import { parseOrgFilePath } from "@/lib/storage/paths";
import { orgFilesEnabled, type FilesState } from "@/lib/storage/work-order-files-states";

// Delete one office file from a work order. X-W1.15.
// Redirects to the coordination page with a CODE; the page supplies the words.
export async function deleteWorkOrderFile(formData: FormData) {
  const orgId = String(formData.get("orgId") ?? "");
  const workOrderId = String(formData.get("workOrderId") ?? "");
  const path = String(formData.get("path") ?? "");
  const back = (s: FilesState) =>
    redirect(`/w/${orgId}/coordination/${workOrderId}?files=${s}#files`);

  if (!orgFilesEnabled()) back("off");

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  // The path must name THIS work order in THIS org — a form value is not trusted
  // to point at the file the button was drawn next to.
  const parsed = parseOrgFilePath(path);
  if (!parsed || parsed.orgId !== orgId || parsed.entityId !== workOrderId || parsed.category !== "office-uploads") {
    back("delete_refused");
  }

  const { data: canManage } = await supabase.rpc("can_view_master_work_order", { p_org_id: orgId });
  if (canManage !== true) back("delete_refused");

  const result = await deleteOrgFile({ orgId, path });
  revalidatePath(`/w/${orgId}/coordination/${workOrderId}`);
  revalidatePath(`/w/${orgId}/field/${workOrderId}`);
  back(result.ok ? "deleted" : result.refused ? "delete_refused" : "delete_failed");
}
