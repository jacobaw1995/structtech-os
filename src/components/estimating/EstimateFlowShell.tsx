"use client";

import { useState } from "react";
import Link from "next/link";
import { maxAllowedStep, STEP_LABELS } from "@/lib/estimating/flow";
import { OutdoorModeContext } from "@/lib/estimating/outdoor-context";

// Field-first (CLAUDE.md "Field & estimating (mobile)"): single thumb
// column, capped at phone width even on desktop, outdoor high-contrast
// toggle.
//
// The toggle is client state (data-outdoor on the wrapping div), read by
// descendant step components — all server components — purely through the
// CSS `group-data-[outdoor=true]/flow:*` variant. That's load-bearing: a
// client component can't push its state INTO already-rendered server
// children, so the outdoor styling can only be wired through a CSS
// selector that reacts to the DOM attribute, never through a prop.
export function EstimateFlowShell({
  backHref,
  currentStep,
  status,
  children,
}: {
  backHref: string;
  currentStep: number;
  status: string;
  children: React.ReactNode;
}) {
  const [outdoor, setOutdoor] = useState(false);
  const maxStep = maxAllowedStep(status);

  return (
    <div
      data-outdoor={outdoor ? "true" : "false"}
      // group-data-[outdoor=true]/flow:* only matches DESCENDANTS of this
      // element (that's how Tailwind's group variant works) — it can never
      // match the group-marker element's own classes, which is why the
      // background here is a plain ternary instead of the CSS variant every
      // other outdoor-aware element in this tree uses.
      className={`group/flow min-h-full ${outdoor ? "bg-black" : "bg-bg"}`}
    >
      <div className="mx-auto flex max-w-md flex-col gap-4 py-2">
        <div className="flex items-center justify-between">
          <Link
            href={backHref}
            className="text-sm text-muted group-data-[outdoor=true]/flow:text-white/70"
          >
            ← Estimates
          </Link>
          <button
            type="button"
            onClick={() => setOutdoor((v) => !v)}
            className="min-h-[40px] rounded-full border border-border px-3 text-xs font-medium text-text group-data-[outdoor=true]/flow:border-white group-data-[outdoor=true]/flow:text-white"
          >
            {outdoor ? "☀ Outdoor mode" : "Outdoor mode"}
          </button>
        </div>

        <ol className="flex items-center gap-1.5">
          {STEP_LABELS.map((label, i) => {
            const stepNum = i + 1;
            const reachable = stepNum <= maxStep;
            const isCurrent = stepNum === currentStep;
            return (
              <li key={label} className="flex flex-1 flex-col items-center gap-1">
                <div
                  className={`h-1.5 w-full rounded-full ${
                    isCurrent
                      ? "bg-accent-strong"
                      : reachable
                      ? "bg-accent-soft"
                      : "bg-surface2"
                  } group-data-[outdoor=true]/flow:bg-white/20 ${
                    isCurrent || reachable
                      ? "group-data-[outdoor=true]/flow:bg-white"
                      : ""
                  }`}
                />
                <span
                  className={`text-[10px] ${
                    isCurrent ? "font-semibold text-text" : "text-muted"
                  } group-data-[outdoor=true]/flow:text-white/80`}
                >
                  {stepNum}
                </span>
              </li>
            );
          })}
        </ol>

        <OutdoorModeContext.Provider value={outdoor}>
          {children}
        </OutdoorModeContext.Provider>
      </div>
    </div>
  );
}
