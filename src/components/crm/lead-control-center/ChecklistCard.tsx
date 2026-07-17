import {
  primaryChecklistKeyForStage,
  getFieldValue,
  isFieldFilled,
  type CommandCenterState,
  type LeadControlCenterConfig,
  type DealRow,
  type LeadTypeOption,
} from "@/lib/crm/command-center";
import { completeSiteSurvey, orderScope, presentQuote } from "@/lib/crm/actions";
import { ChecklistFieldRow } from "./ChecklistFieldRow";

// The center panel's "card" — re-renders entirely off the viewed stage's
// config; nothing here is specific to a particular stage key beyond the
// three milestone-action bindings at the bottom (which map 1:1 to the
// three fixed RPCs from the Stage 3 migration — there's no way to make
// "which RPC advances which stage" itself config-driven without those RPCs
// existing per-tenant, which they don't).
export function ChecklistCard({
  orgId,
  dealId,
  viewedStage,
  state,
  config,
  deal,
  leadTypeOptions,
  remodelOptions,
}: {
  orgId: string;
  dealId: string;
  viewedStage: string;
  state: CommandCenterState;
  config: LeadControlCenterConfig;
  deal: DealRow;
  leadTypeOptions: LeadTypeOption[];
  remodelOptions: LeadTypeOption[];
}) {
  const stageDef = state.stages.find((s) => s.key === viewedStage);
  if (!stageDef) {
    return (
      <div className="flex flex-1 items-center justify-center rounded-lg border border-border bg-surface p-6 text-sm text-muted">
        Stage not found in this workspace&apos;s configuration.
      </div>
    );
  }

  const checklistKey = primaryChecklistKeyForStage(viewedStage);
  const checklist = checklistKey ? config.checklists[checklistKey] : null;
  const completion = checklistKey ? state.checklistCompletions[checklistKey] : null;

  const isCurrent = viewedStage === state.activeStage;

  return (
    <div className="flex flex-1 flex-col overflow-y-auto rounded-lg border border-border bg-surface p-4">
      {checklist && completion ? (
        <div className="mb-3 flex flex-col gap-2">
          <div className="flex items-baseline justify-between">
            <h3 className="text-xs font-semibold uppercase tracking-wide text-muted">{checklist.title}</h3>
            <span className="font-mono text-xs text-muted">
              {completion.filled}/{completion.total}
            </span>
          </div>
          <div className="h-1.5 w-full overflow-hidden rounded-full bg-surface2">
            <div
              className="h-full rounded-full bg-accent-strong transition-all"
              style={{ width: `${completion.percent}%` }}
            />
          </div>
        </div>
      ) : (
        <h3 className="mb-3 text-xs font-semibold uppercase tracking-wide text-muted">Stage details</h3>
      )}

      <div className="flex flex-col">
        {completion
          ? completion.items.map(({ field, filled, value }) => (
              <ChecklistFieldRow
                key={`${field.key}-${filled}`}
                orgId={orgId}
                dealId={dealId}
                stage={viewedStage}
                field={field}
                value={value}
                filled={filled}
                columnValues={columnValuesFor(deal, field)}
                leadTypeOptions={leadTypeOptions}
                remodelOptions={remodelOptions}
              />
            ))
          : stageDef.vitalFields.map((field) => {
              const filled = isFieldFilled(deal, field);
              return (
                <ChecklistFieldRow
                  key={`${field.key}-${filled}`}
                  orgId={orgId}
                  dealId={dealId}
                  stage={viewedStage}
                  field={field}
                  value={getFieldValue(deal, field)}
                  filled={filled}
                  columnValues={columnValuesFor(deal, field)}
                  leadTypeOptions={leadTypeOptions}
                  remodelOptions={remodelOptions}
                />
              );
            })}
      </div>

      {isCurrent && (
        <MilestoneAction orgId={orgId} dealId={dealId} viewedStage={viewedStage} deal={deal} state={state} />
      )}
    </div>
  );
}

function columnValuesFor(deal: DealRow, field: { source: { kind: string; columns?: string[] } }): Record<string, string> | undefined {
  if (field.source.kind !== "columns" || !field.source.columns) return undefined;
  const record: Record<string, string> = {};
  for (const column of field.source.columns) {
    const raw = (deal as unknown as Record<string, unknown>)[column];
    record[column] = typeof raw === "string" ? raw : "";
  }
  return record;
}

function MilestoneAction({
  orgId,
  dealId,
  viewedStage,
  deal,
  state,
}: {
  orgId: string;
  dealId: string;
  viewedStage: string;
  deal: DealRow;
  state: CommandCenterState;
}) {
  if (viewedStage === "site_visit" && !deal.site_survey_complete_at) {
    return (
      <MilestoneButton orgId={orgId} dealId={dealId} action={completeSiteSurvey} label="Mark Site Visit Complete" disabled={false} />
    );
  }
  if (viewedStage === "scope" && !deal.roof_scope_ordered_at) {
    return (
      <MilestoneButton
        orgId={orgId}
        dealId={dealId}
        action={orderScope}
        label="Order Scope"
        disabled={!state.advanceGate.allowed}
        reason={state.advanceGate.allowed ? undefined : state.advanceGate.reason ?? undefined}
      />
    );
  }
  if (viewedStage === "quote" && !deal.quote_presented_at) {
    return (
      <MilestoneButton
        orgId={orgId}
        dealId={dealId}
        action={presentQuote}
        label="Present Quote"
        disabled={deal.value == null}
        reason={deal.value == null ? "Set a quote amount first" : undefined}
      />
    );
  }
  return null;
}

function MilestoneButton({
  orgId,
  dealId,
  action,
  label,
  disabled,
  reason,
}: {
  orgId: string;
  dealId: string;
  action: (formData: FormData) => void | Promise<void>;
  label: string;
  disabled: boolean;
  reason?: string;
}) {
  return (
    <form action={action} className="mt-4 flex flex-col gap-1.5 border-t border-border pt-4">
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="dealId" value={dealId} />
      <button
        type="submit"
        disabled={disabled}
        className="min-h-14 w-full rounded-md bg-accent-strong px-3 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-40 sm:min-h-0 sm:py-2"
      >
        {label}
      </button>
      {reason && <p className="text-center text-xs text-muted">{reason}</p>}
    </form>
  );
}
