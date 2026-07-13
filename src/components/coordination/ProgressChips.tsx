import type { CoordinationStage } from "@/lib/coordination/stage";

// Wireframe 1d/2d: "Signed job → Sign-off → Work order → Materials →
// Schedule" pill row. complete=true gets the accent-soft fill (matches the
// hi-fi's "Sign-off: colors & finishes" highlighted pill); incomplete stays
// a plain bordered pill.
export function ProgressChips({ stages }: { stages: CoordinationStage[] }) {
  return (
    <div className="flex flex-wrap items-center gap-1">
      {stages.map((stage, i) => (
        <div key={stage.key} className="flex items-center gap-1">
          {i > 0 && <span className="text-muted">→</span>}
          <span
            className={`rounded-md px-2.5 py-1.5 text-xs font-medium ${
              stage.complete
                ? "bg-accent-soft text-accent-strong"
                : "border border-border text-muted"
            }`}
          >
            {stage.label}
          </span>
        </div>
      ))}
    </div>
  );
}
