"use client";

import { useState } from "react";
import Link from "next/link";

// Generalized version of EstimateFlowShell's pattern (single thumb column,
// capped phone width, group-data-[outdoor=true]/field:* CSS variant driven
// by a data-outdoor attribute) — reused by both the Today page (no tabs)
// and the job-detail page (Check-in/Packet tabs). Outdoor defaults OFF
// (CLAUDE.md, updated 7/13 per Jacob) — normal light theme on load, crew
// toggles it on if they need the high-contrast view. Same default as
// EstimateFlowShell now, just kept as its own component since Field still
// needs the Today-page (no-tabs) variant estimating doesn't have.
export function FieldShell({
  backHref,
  backLabel,
  tabs,
  children,
}: {
  backHref?: string;
  backLabel?: string;
  tabs?: { label: string; href: string; active: boolean }[];
  children: React.ReactNode;
}) {
  const [outdoor, setOutdoor] = useState(false);

  return (
    <div
      data-outdoor={outdoor ? "true" : "false"}
      className={`group/field min-h-full ${outdoor ? "bg-black" : "bg-bg"}`}
    >
      <div className="mx-auto flex max-w-md flex-col gap-4 py-2">
        <div className="flex items-center justify-between">
          {backHref ? (
            <Link
              href={backHref}
              className="text-sm text-muted group-data-[outdoor=true]/field:text-white/70"
            >
              {backLabel ?? "← Back"}
            </Link>
          ) : (
            <span />
          )}
          <button
            type="button"
            onClick={() => setOutdoor((v) => !v)}
            className="min-h-[40px] rounded-full border border-border px-3 text-xs font-medium text-text group-data-[outdoor=true]/field:border-white group-data-[outdoor=true]/field:text-white"
          >
            {outdoor ? "☀ Outdoor mode" : "Outdoor mode"}
          </button>
        </div>

        {tabs && (
          <div className="flex gap-2">
            {tabs.map((tab) => (
              <Link
                key={tab.label}
                href={tab.href}
                className={`flex min-h-11 flex-1 items-center justify-center rounded-lg text-sm font-medium ${
                  tab.active
                    ? "bg-accent-strong text-white"
                    : "border border-border text-muted group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:text-white/70"
                }`}
              >
                {tab.label}
              </Link>
            ))}
          </div>
        )}

        {children}
      </div>
    </div>
  );
}
