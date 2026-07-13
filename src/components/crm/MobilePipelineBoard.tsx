"use client";

import { useEffect, useState } from "react";
import { DealCard } from "@/components/crm/DealCard";
import type { CrmStage } from "@/lib/crm/stages";
import type { Database } from "@/lib/supabase/database.types";

type Deal = Database["public"]["Tables"]["deals"]["Row"];

// Mobile-only pipeline view (hi-fi wireframe §7 "Mobile home & pipeline"):
// swipeable stage pills + dot pagination, one stage's deals visible at a
// time as full-width cards — a genuinely different interaction from the
// desktop multi-column kanban board, not just a CSS reflow of it. That
// board lives unchanged in crm/page.tsx behind `hidden sm:flex`; this
// component is the `sm:hidden` counterpart, rendered from the same
// server-fetched data so there's one data fetch, two presentations.
export function MobilePipelineBoard({
  stages,
  dealsByStage,
  boardHref,
  selectedDeal,
}: {
  stages: (CrmStage & { count: number })[];
  dealsByStage: Map<string, Deal[]>;
  boardHref: string;
  selectedDeal: Deal | null;
}) {
  const initialIndex = selectedDeal
    ? Math.max(
        0,
        stages.findIndex((s) => s.key === selectedDeal.stage)
      )
    : 0;
  const [activeIndex, setActiveIndex] = useState(initialIndex);

  // Follow the open deal's stage if one gets selected after mount (e.g.
  // tapping a card, which navigates via Link/searchParams rather than
  // this component's own state).
  useEffect(() => {
    if (!selectedDeal) return;
    const idx = stages.findIndex((s) => s.key === selectedDeal.stage);
    if (idx >= 0) setActiveIndex(idx);
  }, [selectedDeal, stages]);

  if (stages.length === 0) return null;

  const active = stages[Math.min(activeIndex, stages.length - 1)];
  const activeDeals = dealsByStage.get(active.key) ?? [];

  return (
    <div className="flex flex-1 flex-col gap-3 overflow-hidden">
      <div className="flex items-center gap-1">
        <button
          type="button"
          aria-label="Previous stage"
          disabled={activeIndex === 0}
          onClick={() => setActiveIndex((i) => Math.max(0, i - 1))}
          className="flex h-11 w-8 shrink-0 items-center justify-center text-muted disabled:opacity-30"
        >
          ‹
        </button>

        <div className="flex flex-1 gap-2 overflow-x-auto scroll-px-1 pb-1">
          {stages.map((stage, i) => (
            <button
              key={stage.key}
              type="button"
              onClick={() => setActiveIndex(i)}
              className={`flex min-h-11 shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full px-4 text-sm font-medium ${
                i === activeIndex
                  ? "bg-accent-strong text-white"
                  : "bg-surface2 text-muted"
              }`}
            >
              {stage.label}
              <span
                className={
                  i === activeIndex ? "text-white/70" : "text-muted/70"
                }
              >
                {stage.count}
              </span>
            </button>
          ))}
        </div>

        <button
          type="button"
          aria-label="Next stage"
          disabled={activeIndex === stages.length - 1}
          onClick={() =>
            setActiveIndex((i) => Math.min(stages.length - 1, i + 1))
          }
          className="flex h-11 w-8 shrink-0 items-center justify-center text-muted disabled:opacity-30"
        >
          ›
        </button>
      </div>

      <div className="flex items-center justify-center gap-1.5">
        {stages.map((stage, i) => (
          <span
            key={stage.key}
            aria-hidden="true"
            className={`h-1.5 w-1.5 rounded-full ${
              i === activeIndex ? "bg-accent-strong" : "bg-border"
            }`}
          />
        ))}
      </div>

      <div className="flex flex-1 flex-col gap-2 overflow-y-auto">
        {activeDeals.length === 0 ? (
          <div className="rounded-md border border-dashed border-border px-3 py-6 text-center text-sm text-muted">
            Empty
          </div>
        ) : (
          activeDeals.map((deal) => (
            <DealCard
              key={deal.id}
              deal={deal}
              href={`${boardHref}?deal=${deal.id}`}
              selected={selectedDeal?.id === deal.id}
              nextAction={active.next_action}
            />
          ))
        )}
      </div>
    </div>
  );
}
