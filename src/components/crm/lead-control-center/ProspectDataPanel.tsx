import { StageSelect } from "@/components/crm/StageSelect";
import { OwnerSelect } from "./OwnerSelect";
import { TagsEditor } from "./TagsEditor";
import { EditLeadDetailsForm } from "./EditLeadDetailsForm";
import type { CrmStage } from "@/lib/crm/stages";
import type { DealRow } from "@/lib/crm/command-center";

export function ProspectDataPanel({
  orgId,
  deal,
  viewedStage,
  kanbanStages,
  members,
}: {
  orgId: string;
  deal: DealRow;
  viewedStage: string;
  kanbanStages: CrmStage[];
  members: { user_id: string; full_name: string | null }[];
}) {
  return (
    <div className="flex flex-col gap-3">
      <h3 className="text-xs font-semibold uppercase tracking-wide text-muted">Prospect Data</h3>

      <div>
        <p className="text-base font-semibold text-text">{deal.contact_name}</p>
      </div>

      <div className="flex flex-col gap-0.5 text-sm">
        <span className="text-xs uppercase tracking-wide text-muted">Phone</span>
        <span className="text-text">{deal.phone || "—"}</span>
      </div>

      <div className="flex flex-col gap-0.5 text-sm">
        <span className="text-xs uppercase tracking-wide text-muted">Billing address</span>
        <span className="text-text">{deal.billing_address || formatServiceAddress(deal) || "—"}</span>
      </div>

      <div className="flex flex-col gap-1">
        <span className="text-xs uppercase tracking-wide text-muted">Owner</span>
        <OwnerSelect orgId={orgId} dealId={deal.id} stage={viewedStage} currentOwnerId={deal.owner_id} members={members} />
      </div>

      <div className="flex flex-col gap-1">
        <span className="text-xs uppercase tracking-wide text-muted">Tags</span>
        <TagsEditor orgId={orgId} dealId={deal.id} stage={viewedStage} tags={deal.tags ?? []} />
      </div>

      <div className="flex flex-col gap-1">
        <span className="text-xs uppercase tracking-wide text-muted">Pipeline Stage</span>
        <StageSelect orgId={orgId} dealId={deal.id} currentStage={deal.stage} stages={kanbanStages} />
      </div>

      <EditLeadDetailsForm orgId={orgId} deal={deal} />
    </div>
  );
}

// Structured address is canonical now (fix pass 7/16) — project_address
// is retired going forward but not backfilled, so this is the same
// "structured, falling back to nothing" shape as create_estimate_from_deal
// without the project_address leg (that fallback lives at the RPC layer
// for the estimate; here there's no legacy value to fall back to, just an
// em dash if neither is set — the legacy hint in EditLeadDetailsForm is
// where an old project_address value still surfaces).
function formatServiceAddress(deal: DealRow): string {
  return [deal.service_address_street, deal.service_address_city, deal.service_address_state, deal.service_address_zip]
    .filter((part): part is string => Boolean(part && part.trim()))
    .join(", ");
}
