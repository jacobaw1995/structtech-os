import { redirect } from "next/navigation";
import { requireModuleAccess } from "@/lib/workspace/context";
import { parseEstimateBranding } from "@/lib/estimating/branding";
import { EstimateDocument } from "@/components/estimating/EstimateDocument";
import { EstimateOutdoorShell } from "@/components/estimating/EstimateOutdoorShell";
import type { Database } from "@/lib/supabase/database.types";

type Estimate = Database["public"]["Tables"]["estimates"]["Row"];
type LineItem = Database["public"]["Tables"]["estimate_line_items"]["Row"];
type Signature = Database["public"]["Tables"]["signatures"]["Row"];

// Chunk 5 — Present Mode: the same document, full-screen, customer-facing.
// WorkspaceShell (src/components/workspace/WorkspaceShell.tsx) strips its
// own chrome for any route ending in /present, so this renders with no
// sidebar/topbar at all. A pure VIEW — visiting this URL never mutates
// anything; "Present to client" (the editor's button) is what calls
// present_estimate() before navigating here. `presentationMode` on
// EstimateDocument hides every operator-only affordance EXCEPT the
// signature block, which stays fully live — a customer signs IN Present
// Mode, at the kitchen table, on the tablet (Jacob's Chunk 5 correction).
export default async function EstimatePresentPage({
  params,
}: {
  params: { orgId: string; estimateId: string };
}) {
  const ctx = await requireModuleAccess(params.orgId, "estimating");
  const supabase = ctx.supabase;

  const { data: fetched } = await supabase.rpc("fetch_estimate", {
    p_estimate_id: params.estimateId,
  });
  const estimate = fetched?.[0] as Estimate | undefined;

  if (!estimate || estimate.org_id !== params.orgId) {
    redirect(`/w/${params.orgId}/estimating`);
  }

  const [{ data: lineItemsData }, { data: signaturesData }, { data: moduleRow }, { data: orgRows }] =
    await Promise.all([
      supabase
        .from("estimate_line_items")
        .select("*")
        .eq("estimate_id", estimate.id)
        .order("sort_order", { ascending: true }),
      supabase
        .from("signatures")
        .select("*")
        .eq("estimate_id", estimate.id)
        .order("signed_at", { ascending: false })
        .limit(1),
      supabase
        .from("tenant_modules")
        .select("config")
        .eq("org_id", params.orgId)
        .eq("module_key", "estimating"),
      supabase.rpc("fetch_organization", { p_org_id: params.orgId }),
    ]);

  const lineItems = (lineItemsData ?? []) as LineItem[];
  const signature = (signaturesData?.[0] ?? null) as Signature | null;
  const branding = parseEstimateBranding(
    moduleRow?.[0]?.config ?? null,
    orgRows?.[0]?.name ?? "Estimate"
  );

  return (
    <div className="min-h-dvh bg-bg px-4 py-6 sm:px-8">
      <EstimateOutdoorShell>
        <EstimateDocument
          orgId={params.orgId}
          estimate={estimate}
          lineItems={lineItems}
          signature={signature}
          branding={branding}
          presentationMode
        />
      </EstimateOutdoorShell>
    </div>
  );
}
