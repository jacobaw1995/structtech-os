"use client";

import { useState } from "react";
import { OutdoorModeContext } from "@/lib/estimating/outdoor-context";

// The old EstimateFlowShell's outdoor-mode toggle MUST survive the wizard's
// deletion (CLAUDE.md: available via a toggle, NOT default-on, on
// estimating/field screens) — this is its new home, wrapping the unified
// document instead of the 4-step flow.
//
// Same load-bearing reason as before: a client component can't push state
// INTO already-rendered server children except through a DOM attribute a
// CSS selector reacts to — `EstimateDocument` (and everything inside it)
// stays a server component, so the toggle here only ever talks to it via
// `data-outdoor` + Tailwind's arbitrary descendant selector, never a prop.
// SignaturePad is the one exception (Chunk 3's outdoor-context.tsx comment
// still applies): it draws with the raw canvas 2D API, a code path CSS
// can't reach, so it reads the boolean directly via OutdoorModeContext.
//
// Deliberately a broad override (`[&_.border-border]:!border-white/20` etc.)
// rather than hand-threading a `group-data-[outdoor=true]:*` variant onto
// every individual element the way the original wizard did — the document
// is far larger now (customer/job-site/line-items/totals/notes/signature,
// all with their own borders and muted text) and re-deriving that by hand
// here would be a lot of surface area for a "must survive," not
// "must be repolished" requirement. Flagging as a reasonable simplification,
// not a silent shortcut.
export function EstimateOutdoorShell({ children }: { children: React.ReactNode }) {
  const [outdoor, setOutdoor] = useState(false);

  return (
    <OutdoorModeContext.Provider value={outdoor}>
      <div className="flex flex-col gap-3">
        <button
          type="button"
          onClick={() => setOutdoor((v) => !v)}
          className="self-end min-h-[40px] rounded-full border border-border px-3 text-xs font-medium text-text"
        >
          {outdoor ? "☀ Outdoor mode" : "Outdoor mode"}
        </button>
        <div
          className={
            outdoor
              ? "rounded-2xl bg-black p-1 [&_.bg-surface]:!bg-black [&_.bg-surface2]:!bg-black " +
                "[&_.border-border]:!border-white/30 [&_.text-text]:!text-white [&_.text-muted]:!text-white/70 " +
                "[&_.divide-border]:[&>*]:!divide-white/20"
              : ""
          }
        >
          {children}
        </div>
      </div>
    </OutdoorModeContext.Provider>
  );
}
