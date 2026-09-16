import { redirect } from "next/navigation";
import Link from "next/link";
import { requireModuleAccess } from "@/lib/workspace/context";
import { parseEstimateBranding } from "@/lib/estimating/branding";
import { EstimateDocument } from "@/components/estimating/EstimateDocument";
import { EstimateOutdoorShell } from "@/components/estimating/EstimateOutdoorShell";
import { SignatureStatusPanel } from "@/components/signing/SignatureStatusPanel";
import { isSendResult, signingState, type LinkRow } from "@/lib/signing/remote";
import type { Database } from "@/lib/supabase/database.types";

type Estimate = Database["public"]["Tables"]["estimates"]["Row"];
type LineItem = Database["public"]["Tables"]["estimate_line_items"]["Row"];
type Signature = Database["public"]["Tables"]["signatures"]["Row"];
type Product = Database["public"]["Tables"]["products"]["Row"];

// Chunk 5 cutover — this IS the document now (was the 4-step wizard
// through Chunk 4; the document lived at the /document suffix through
// Chunks 2-4). No more step params, no more wizard. The old /document path
// is a redirect-only stub (document/page.tsx) for anything bookmarked.
export default async function EstimatePage({
  params,
  searchParams,
}: {
  params: { orgId: string; estimateId: string };
  searchParams: { error?: string; scopeUnmapped?: string; scopeUnparseable?: string; send?: string };
}) {
  const ctx = await requireModuleAccess(params.orgId, "estimating");
  const supabase = ctx.supabase;

  // Single-record fetch RPC (CLAUDE.md rule 4).
  const { data: fetched } = await supabase.rpc("fetch_estimate", {
    p_estimate_id: params.estimateId,
  });
  const estimate = fetched?.[0] as Estimate | undefined;

  if (!estimate || estimate.org_id !== params.orgId) {
    redirect(`/w/${params.orgId}/estimating`);
  }

  const [
    { data: lineItemsData },
    { data: signaturesData },
    { data: moduleRow },
    { data: orgRows },
    { data: catalogRows },
    { data: financials },
    linksRes,
    { data: canCreateData },
  ] = await Promise.all([
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
      // A2.1c — the catalog behind the "From catalog" picker. Active items only:
      // an archived item is one the tenant has decided not to sell any more, so
      // offering it on a new quote would be the archive doing nothing.
      // list_products() already nulls cost/sell/markup for a caller without
      // financials, so this is safe to hand to a client component as-is.
      supabase.rpc("list_products", { p_org_id: params.orgId }),
      supabase.rpc("can_view_financials", { p_org_id: params.orgId }),
      // U-W1.19 — the link history is the send history (see lib/signing/remote.ts).
      supabase
        .from("estimate_sign_links")
        .select("created_at, expires_at, revoked_at, used_at", { count: "exact" })
        .eq("estimate_id", params.estimateId),
      supabase.rpc("has_capability", { p_org_id: params.orgId, p_capability: "create_estimates" }),
    ]);

  const lineItems = (lineItemsData ?? []) as LineItem[];
  const catalog = (catalogRows ?? []) as Product[];
  const canViewFinancials = financials === true;
  const signature = (signaturesData?.[0] ?? null) as Signature | null;
  // U-W1.19 — send for signature, office side. A read that failed or came back
  // short is `null`, which the panel says rather than rendering "not sent".
  const links =
    !linksRes.error && linksRes.data && linksRes.count === linksRes.data.length
      ? (linksRes.data as LinkRow[])
      : null;
  const signing = signingState({
    estimateStatus: estimate.status,
    signedAt: signature?.signed_at ?? estimate.signed_at ?? null,
    signerName: signature?.signer_name ?? null,
    links,
    now: Date.now(),
  });
  const branding = parseEstimateBranding(
    moduleRow?.[0]?.config ?? null,
    orgRows?.[0]?.name ?? "Estimate"
  );

  return (
    <div className="flex h-full flex-col gap-4 overflow-y-auto py-2">
      <Link href={`/w/${params.orgId}/estimating`} className="text-sm text-muted">
        ← Estimates
      </Link>
      <SignatureStatusPanel
        orgId={params.orgId}
        estimateId={estimate.id}
        state={signing}
        result={isSendResult(searchParams.send) ? searchParams.send : null}
        customerEmail={estimate.email?.trim() || null}
        canSend={canCreateData === true && canViewFinancials}
      />
      <EstimateOutdoorShell>
        <EstimateDocument
          orgId={params.orgId}
          estimate={estimate}
          lineItems={lineItems}
          catalog={catalog}
          canViewFinancials={canViewFinancials}
          signature={signature}
          branding={branding}
          errorMessage={searchParams.error}
          scopeUnmapped={searchParams.scopeUnmapped ? searchParams.scopeUnmapped.split(",") : []}
          scopeUnparseable={searchParams.scopeUnparseable ? searchParams.scopeUnparseable.split(",") : []}
        />
      </EstimateOutdoorShell>
    </div>
  );
}
