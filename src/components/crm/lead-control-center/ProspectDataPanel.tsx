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
        <span className="text-text">{deal.billing_address || deal.project_address || "—"}</span>
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
