import Link from "next/link";
import { QuickActionsRow } from "./QuickActionsRow";
import { ProspectDataPanel } from "./ProspectDataPanel";
import { RevisionHistory } from "./RevisionHistory";
import { StageTabs } from "./StageTabs";
import { ChecklistCard } from "./ChecklistCard";
import { LeadNotesPanel } from "./LeadNotesPanel";
import { MobileLogActivity } from "./MobileLogActivity";
import { estimateStatusLabel, estimateStatusClasses } from "@/lib/estimating/status";
import { formatMoney, type CrmStage } from "@/lib/crm/stages";
import { createEstimateFromDeal } from "@/lib/estimating/actions";
import type { CommandCenterState, LeadControlCenterConfig, DealRow } from "@/lib/crm/command-center";
import type { Database } from "@/lib/supabase/database.types";

type DealNote = Database["public"]["Tables"]["deal_notes"]["Row"];
type DealActivity = Database["public"]["Tables"]["deal_activity"]["Row"];
type Estimate = Database["public"]["Tables"]["estimates"]["Row"];

// Replaces the old thin DealPanel entirely. Desktop/tablet renders a true
// 3-panel layout; mobile renders a genuinely different single-column
// ordering (header -> quick actions -> log activity -> stage tabs ->
// checklist -> prospect data collapsed below), not a CSS reflow of the
// same markup — same "separate tree, shared data" precedent crm/page.tsx
// already uses for MobilePipelineBoard vs the desktop kanban board.
export function LeadControlCenter({
  orgId,
  deal,
  kanbanStages,
  lccConfig,
  state,
  viewedStage,
  notes,
  activity,
  members,
  closeHref,
  errorMessage,
  estimates,
  canCreateEstimate,
}: {
  orgId: string;
  deal: DealRow;
  kanbanStages: CrmStage[];
  lccConfig: LeadControlCenterConfig;
  state: CommandCenterState;
  viewedStage: string;
  notes: DealNote[];
  activity: DealActivity[];
  members: { user_id: string; full_name: string | null }[];
  closeHref: string;
  errorMessage?: string;
  estimates: Estimate[];
  canCreateEstimate: boolean;
}) {
  const activeStageLabel = state.stages.find((s) => s.key === state.activeStage)?.label ?? "—";
  const overallPercent =
    state.stages.length === 0 ? 0 : Math.round(((state.stages.findIndex((s) => s.key === state.activeStage) + 1) / state.stages.length) * 100);
  const remodelOptions = [
    { value: "remodel", label: "Remodel" },
    { value: "new_construction", label: "New Construction" },
  ];

  function authorName(userId: string | null): string {
    if (!userId) return "Unknown";
    return members.find((m) => m.user_id === userId)?.full_name ?? "Unknown";
  }

  const header = (
    <div className="flex items-start justify-between gap-2">
      <div>
        <h2 className="text-xl font-semibold text-text">{deal.contact_name}</h2>
        <p className="text-sm text-muted">{activeStageLabel}</p>
      </div>
      <Link
        href={closeHref}
        aria-label="Close"
        className="-mr-2 -mt-2 flex h-11 w-11 shrink-0 items-center justify-center text-lg text-muted hover:text-text"
      >
        ✕
      </Link>
    </div>
  );

  const progressBar = (
    <div>
      <div className="flex items-baseline justify-between text-xs">
        <span className="font-semibold uppercase tracking-wide text-muted">Progress</span>
        <span className="font-mono text-muted">{overallPercent}%</span>
      </div>
      <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-surface2">
        <div className="h-full rounded-full bg-accent-strong transition-all" style={{ width: `${overallPercent}%` }} />
      </div>
    </div>
  );

  const checklistCard = (
    <ChecklistCard
      orgId={orgId}
      dealId={deal.id}
      viewedStage={viewedStage}
      state={state}
      config={lccConfig}
      deal={deal}
      leadTypeOptions={lccConfig.leadTypeOptions}
      remodelOptions={remodelOptions}
    />
  );

  const prospectData = (
    <ProspectDataPanel orgId={orgId} deal={deal} viewedStage={viewedStage} kanbanStages={kanbanStages} members={members} />
  );

  const estimatesBlock = canCreateEstimate && !deal.archived_at && (
    <div className="flex flex-col gap-2">
      <h3 className="text-xs font-semibold uppercase tracking-wide text-muted">Estimates</h3>
      <div className="flex flex-col gap-1.5">
        {estimates.length === 0 && <p className="text-xs text-muted">No estimates yet.</p>}
        {estimates.map((estimate) => (
          <Link
            key={estimate.id}
            href={`/w/${orgId}/estimating/${estimate.id}`}
            className="flex items-center justify-between rounded-md bg-surface2 px-3 py-2 text-sm text-text hover:bg-accent-soft"
          >
            <span className="font-mono">{formatMoney(estimate.presented_total ?? estimate.subtotal)}</span>
            <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${estimateStatusClasses(estimate.status)}`}>
              {estimateStatusLabel(estimate.status)}
            </span>
          </Link>
        ))}
      </div>
      <form action={createEstimateFromDeal}>
        <input type="hidden" name="orgId" value={orgId} />
        <input type="hidden" name="dealId" value={deal.id} />
        <button
          type="submit"
          className="min-h-14 w-full rounded-md border border-accent-strong px-3 text-sm font-medium text-accent-strong hover:bg-accent-soft sm:min-h-0 sm:py-1.5 sm:text-xs"
        >
          + Create estimate
        </button>
      </form>
    </div>
  );

  return (
    <div className="fixed inset-0 z-40 flex flex-col overflow-y-auto bg-bg p-4 sm:static sm:z-auto sm:flex-1 sm:overflow-hidden sm:bg-transparent sm:p-0">
      {errorMessage && <p className="mb-3 rounded-md bg-warn-soft px-3 py-2 text-xs text-text sm:hidden">{errorMessage}</p>}

      {/* MOBILE — single column, own ordering per spec */}
      <div className="flex flex-1 flex-col gap-4 sm:hidden">
        {header}
        <QuickActionsRow orgId={orgId} dealId={deal.id} phone={deal.phone} />
        <MobileLogActivity orgId={orgId} dealId={deal.id} notes={notes} activity={activity} authorName={authorName} />
        {progressBar}
        <StageTabs orgId={orgId} dealId={deal.id} viewedStage={viewedStage} state={state} />
        {checklistCard}
        <details className="rounded-lg border border-border bg-surface p-4">
          <summary className="cursor-pointer select-none text-xs font-semibold uppercase tracking-wide text-muted">
            Prospect Data
          </summary>
          <div className="mt-3 flex flex-col gap-4">
            {prospectData}
            {estimatesBlock}
          </div>
        </details>
      </div>

      {/* DESKTOP/TABLET — true 3-panel */}
      <div className="hidden flex-1 gap-4 overflow-hidden sm:flex">
        <aside className="flex w-72 shrink-0 flex-col gap-4 overflow-y-auto rounded-lg border border-border bg-surface p-4">
          <QuickActionsRow orgId={orgId} dealId={deal.id} phone={deal.phone} />
          {prospectData}
          {estimatesBlock}
          <RevisionHistory activity={activity} authorName={authorName} />
        </aside>

        <div className="flex min-w-0 flex-1 flex-col gap-3">
          {errorMessage && <p className="rounded-md bg-warn-soft px-3 py-2 text-xs text-text">{errorMessage}</p>}
          {header}
          {progressBar}
          <StageTabs orgId={orgId} dealId={deal.id} viewedStage={viewedStage} state={state} />
          {checklistCard}
        </div>

        <LeadNotesPanel orgId={orgId} dealId={deal.id} notes={notes} authorName={authorName} />
      </div>
    </div>
  );
}
