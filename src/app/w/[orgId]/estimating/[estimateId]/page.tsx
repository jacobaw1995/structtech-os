import { redirect } from "next/navigation";
import { requireModuleAccess } from "@/lib/workspace/context";
import { clampStep } from "@/lib/estimating/flow";
import { EstimateFlowShell } from "@/components/estimating/EstimateFlowShell";
import { StepPreliminary } from "@/components/estimating/StepPreliminary";
import { StepValidate } from "@/components/estimating/StepValidate";
import { StepPresent } from "@/components/estimating/StepPresent";
import { StepSign } from "@/components/estimating/StepSign";
import type { Database } from "@/lib/supabase/database.types";

type Estimate = Database["public"]["Tables"]["estimates"]["Row"];
type LineItem = Database["public"]["Tables"]["estimate_line_items"]["Row"];
type Signature = Database["public"]["Tables"]["signatures"]["Row"];

export default async function EstimatePage({
  params,
  searchParams,
}: {
  params: { orgId: string; estimateId: string };
  searchParams: { step?: string; error?: string };
}) {
  const ctx = await requireModuleAccess(params.orgId, "estimating");
  const supabase = ctx.supabase;

  // Single-record fetch RPC (CLAUDE.md rule 4), same pattern as fetch_deal
  // in crm/page.tsx.
  const { data: fetched } = await supabase.rpc("fetch_estimate", {
    p_estimate_id: params.estimateId,
  });
  const estimate = fetched?.[0] as Estimate | undefined;

  // fetch_estimate only guarantees org membership, not THIS org — same guard
  // crm/page.tsx applies to fetch_deal, for the same agency_admin
  // multi-org reason.
  if (!estimate || estimate.org_id !== params.orgId) {
    redirect(`/w/${params.orgId}/estimating`);
  }

  const [{ data: lineItemsData }, { data: signaturesData }] = await Promise.all([
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
  ]);

  const lineItems = (lineItemsData ?? []) as LineItem[];
  const signature = (signaturesData?.[0] ?? null) as Signature | null;

  const step = clampStep(Number(searchParams.step), estimate.status);
  const backHref = `/w/${params.orgId}/estimating`;

  return (
    <EstimateFlowShell
      backHref={backHref}
      currentStep={step}
      status={estimate.status}
    >
      {step === 1 && (
        <StepPreliminary orgId={params.orgId} estimate={estimate} />
      )}
      {step === 2 && (
        <StepValidate
          orgId={params.orgId}
          estimate={estimate}
          lineItems={lineItems}
          errorMessage={searchParams.error}
        />
      )}
      {step === 3 && (
        <StepPresent
          orgId={params.orgId}
          estimate={estimate}
          lineItems={lineItems}
          errorMessage={searchParams.error}
        />
      )}
      {step === 4 && (
        <StepSign
          orgId={params.orgId}
          estimate={estimate}
          signature={signature}
          errorMessage={searchParams.error}
        />
      )}
    </EstimateFlowShell>
  );
}
