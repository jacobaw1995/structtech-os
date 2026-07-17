import Link from "next/link";
import type { CommandCenterState } from "@/lib/crm/command-center";

// Command-stage tabs (the job path — distinct from the kanban stage
// dropdown in the left panel). Reached stages navigate via ?stage=;
// unreached stages render inert (spec: "tabs gate/enable by completion").
export function StageTabs({
  orgId,
  dealId,
  viewedStage,
  state,
}: {
  orgId: string;
  dealId: string;
  viewedStage: string;
  state: CommandCenterState;
}) {
  return (
    <div className="flex gap-2 overflow-x-auto pb-1">
      {state.stages.map((stage) => {
        const isViewed = stage.key === viewedStage;
        if (!stage.reached) {
          return (
            <span
              key={stage.key}
              className="shrink-0 rounded-full border border-border px-3 py-1.5 text-sm text-muted opacity-50"
            >
              {stage.label}
            </span>
          );
        }
        return (
          <Link
            key={stage.key}
            href={`/w/${orgId}/crm?deal=${dealId}&stage=${stage.key}`}
            className={`shrink-0 rounded-full border px-3 py-1.5 text-sm font-medium ${
              isViewed
                ? "border-accent-strong bg-accent-strong text-white"
                : "border-border bg-bg text-text hover:bg-surface2"
            }`}
          >
            {stage.label}
            {stage.current && !isViewed && <span className="ml-1.5 inline-block h-1.5 w-1.5 rounded-full bg-accent-strong" />}
          </Link>
        );
      })}
    </div>
  );
}
