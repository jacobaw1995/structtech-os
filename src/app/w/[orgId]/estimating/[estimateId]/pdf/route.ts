import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { renderEstimatePdf } from "@/lib/estimating/pdf";
import { parseEstimateBranding } from "@/lib/estimating/branding";
import type { Database } from "@/lib/supabase/database.types";

type Estimate = Database["public"]["Tables"]["estimates"]["Row"];
type LineItem = Database["public"]["Tables"]["estimate_line_items"]["Row"];
type Signature = Database["public"]["Tables"]["signatures"]["Row"];

// Generated on-demand, not persisted (docs/SCOPE.md "Tenant-customizable
// document templates": signatures.pdf_url stays null until R2 storage
// lands — this route is the preview/download path in the meantime).
export async function GET(
  request: NextRequest,
  { params }: { params: { orgId: string; estimateId: string } }
) {
  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) {
    return new NextResponse("Unauthorized", { status: 401 });
  }

  // Single-record fetch RPC (CLAUDE.md rule 4), same org guard the page
  // component applies — fetch_estimate only guarantees org membership, not
  // THIS org.
  const { data: fetched } = await supabase.rpc("fetch_estimate", {
    p_estimate_id: params.estimateId,
  });
  const estimate = fetched?.[0] as Estimate | undefined;

  if (!estimate || estimate.org_id !== params.orgId) {
    return new NextResponse("Not found", { status: 404 });
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
      // Single-record fetch RPC (CLAUDE.md rule 4), not a direct
      // .select().eq(id).single() — same reason fetch_deal/fetch_estimate
      // exist.
      supabase.rpc("fetch_organization", { p_org_id: params.orgId }),
    ]);

  const lineItems = (lineItemsData ?? []) as LineItem[];
  const signature = (signaturesData?.[0] ?? null) as Signature | null;
  const branding = parseEstimateBranding(
    moduleRow?.[0]?.config ?? null,
    orgRows?.[0]?.name ?? "Estimate"
  );

  const pdfBytes = await renderEstimatePdf({ estimate, lineItems, signature, branding });

  const download = request.nextUrl.searchParams.get("download") === "1";

  return new NextResponse(Buffer.from(pdfBytes), {
    headers: {
      "Content-Type": "application/pdf",
      "Content-Disposition": `${download ? "attachment" : "inline"}; filename="estimate-${estimate.id.slice(0, 8)}.pdf"`,
      "Cache-Control": "private, no-store",
    },
  });
}
