import type { CoordinationStage } from "@/lib/coordination/stage";

// Wireframe 1d/2d: "Signed job → Sign-off → Work order → Materials →
// Schedule" pill row. complete=true gets the accent-soft fill (matches the
// hi-fi's "Sign-off: colors & finishes" highlighted pill); incomplete stays
// a plain bordered pill.
//
// U-W1.29 (2026-09-22) — THE RAIL HAD NO KEY. The controller read this row off
// the live admin session and saw "three visual states with no key". Measured
// here against the same job (sign-off not recorded, 1 material, 1 crew booked):
// there are TWO visual states, not three — "Signed job", "Work order",
// "Materials" and "Schedule" are byte-identical (fill oklch(0.93 0.03 250),
// 0px border) and only "Sign-off" is outlined. Two styles read as three because
// nothing on screen said what either style meant.
//
// A checkmark is the key, carried by the chip itself rather than by a legend
// underneath it: a legend is one more thing to find, and it is wrong the moment
// someone adds a third state. Screen readers get the same distinction in words.
//
// WHAT THIS DOES NOT FIX, because it is a product question and not a rendering
// one: `signed` and `work_order` are hardcoded `complete: true` in
// coordinationStages() — they cannot be anything else, ever. So two of these
// five chips now carry a checkmark that reports no fact, sitting beside two
// whose checkmarks are earned (materialCount > 0, scheduleCount > 0). Reported,
// not silently changed: which steps belong on this rail is Jacob's call.
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
            <span className="sr-only">{stage.complete ? "Done: " : "Not yet: "}</span>
            {stage.complete && <span aria-hidden="true">✓ </span>}
            {stage.label}
          </span>
        </div>
      ))}
    </div>
  );
}
