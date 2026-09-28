import Link from "next/link";
import { redirect } from "next/navigation";
import { requireModuleAccess } from "@/lib/workspace/context";
import { parseEstimateBranding } from "@/lib/estimating/branding";
import { EstimateDocument } from "@/components/estimating/EstimateDocument";
import { EstimateOutdoorShell } from "@/components/estimating/EstimateOutdoorShell";
import { SignedCopyStatus } from "@/components/estimating/SignedCopyStatus";
import { isSignedCopyState } from "@/lib/estimating/signed-copy";
import { SIGN_FAILURE_COPY, isSignFailure } from "@/lib/estimating/sign-states";
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
  searchParams,
}: {
  params: { orgId: string; estimateId: string };
  searchParams: { copy?: string; signError?: string };
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

  // A2.1c — PRESENT MODE GETS NO PICKER, and that is a decision rather than a
  // compiler-satisfying empty array. Present Mode is the customer facing the
  // tablet: opening a price list in front of the homeowner is the single worst
  // place that control could appear. The document is already locked here so the
  // picker would not render anyway — passing an empty catalog means it cannot
  // render even if that ever changes.
  return (
    <div className="min-h-dvh bg-bg px-4 py-6 sm:px-8">
      {/* U-W1.37 (D4) — THE WAY BACK, AND ONLY ONCE IT IS SIGNED.
          Golden path run 1, Jacob's words: "after I presented the estimate and
          signed it, there's no navigation no way to go back no nothing."
          MEASURED: signing redirects here (estimatePresentHref, in
          lib/estimating/actions.ts), and this page's own content holds ZERO
          links. Every onward control — View PDF, Download PDF, Create work
          order — lives in EstimateSignatureBlock behind `!presentationMode`,
          deliberately, because they are the operator's and this is the screen
          the homeowner reads. So the single most important action in the
          application ended on the one view where everything that follows it is
          hidden.
          The fix is not to un-hide them here — that would put office controls
          back on a customer's document, which is D3 in this very session. It is
          to hand the operator back their own screen the moment the signature
          exists. Before signing, this stays exactly as clean as it was. */}
      {estimate.status === "signed" && (
        <div className="mx-auto mb-4 flex max-w-3xl flex-col gap-1">
          <Link
            href={`/w/${params.orgId}/estimating/${estimate.id}`}
            className="inline-flex min-h-14 items-center text-base font-medium text-accent-strong sm:min-h-0"
          >
            ← Back to the estimate
          </Link>
          <p className="text-sm text-muted">
            Signed. The PDF, and the job it becomes, are on the estimate.
          </p>
        </div>
      )}
      {/* X-W1.14: shown only for a signed estimate, so a crafted ?copy= on an
          unsigned one cannot claim a copy went out. */}
      {/* X-W1.16: a failed signature is a code looked up in sign-states.ts. */}
      {isSignFailure(searchParams.signError) ? (
        <p
          role="alert"
          data-sign-error={searchParams.signError}
          className="mx-auto mb-4 max-w-3xl rounded-md bg-warn-soft px-3 py-2 text-sm text-text"
        >
          {SIGN_FAILURE_COPY[searchParams.signError]}
        </p>
      ) : null}
      {estimate.status === "signed" && isSignedCopyState(searchParams.copy) ? (
        <SignedCopyStatus
          state={searchParams.copy}
          email={estimate.email}
          orgId={params.orgId}
          estimateId={estimate.id}
        />
      ) : null}
      <EstimateOutdoorShell showToggle={false}>
        <EstimateDocument
          orgId={params.orgId}
          estimate={estimate}
          lineItems={lineItems}
          catalog={[]}
          canViewFinancials={false}
          signature={signature}
          branding={branding}
          presentationMode
        />
      </EstimateOutdoorShell>
    </div>
  );
}
