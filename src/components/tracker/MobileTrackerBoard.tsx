"use client";

import { useEffect, useState } from "react";
import { ItemCard } from "@/components/tracker/ItemCard";
import type { TrackerStatus } from "@/lib/tracker/config";
import type { Database } from "@/lib/supabase/database.types";

type TrackerItem = Database["public"]["Tables"]["tracker_items"]["Row"];

// Mobile-only board (mirrors crm/MobilePipelineBoard.tsx): swipeable status
// pills + one column of full-width cards, rendered from the same
// server-fetched data as the desktop kanban board.
export function MobileTrackerBoard({
  statuses,
  itemsByStatus,
  boardHref,
  selectedItem,
  typeLabels,
  assigneeNames,
}: {
  statuses: (TrackerStatus & { count: number })[];
  itemsByStatus: Map<string, TrackerItem[]>;
  boardHref: string;
  selectedItem: TrackerItem | null;
  typeLabels: Map<string, string>;
  assigneeNames: Map<string, string>;
}) {
  const initialIndex = selectedItem
    ? Math.max(0, statuses.findIndex((s) => s.key === selectedItem.status))
    : 0;
  const [activeIndex, setActiveIndex] = useState(initialIndex);

  useEffect(() => {
    if (!selectedItem) return;
    const idx = statuses.findIndex((s) => s.key === selectedItem.status);
    if (idx >= 0) setActiveIndex(idx);
  }, [selectedItem, statuses]);

  if (statuses.length === 0) return null;

  const active = statuses[Math.min(activeIndex, statuses.length - 1)];
  const activeItems = itemsByStatus.get(active.key) ?? [];

  return (
    <div className="flex flex-1 flex-col gap-3 overflow-hidden">
      <div className="flex items-center gap-1">
        <button
          type="button"
          aria-label="Previous status"
          disabled={activeIndex === 0}
          onClick={() => setActiveIndex((i) => Math.max(0, i - 1))}
          className="flex h-11 w-8 shrink-0 items-center justify-center text-muted disabled:opacity-30"
        >
          ‹
        </button>

        <div className="flex flex-1 gap-2 overflow-x-auto scroll-px-1 pb-1">
          {statuses.map((status, i) => (
            <button
              key={status.key}
              type="button"
              onClick={() => setActiveIndex(i)}
              className={`flex min-h-11 shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full px-4 text-sm font-medium ${
                i === activeIndex ? "bg-accent-strong text-white" : "bg-surface2 text-muted"
              }`}
            >
              {status.label}
              <span className={i === activeIndex ? "text-white/70" : "text-muted/70"}>
                {status.count}
              </span>
            </button>
          ))}
        </div>

        <button
          type="button"
          aria-label="Next status"
          disabled={activeIndex === statuses.length - 1}
          onClick={() => setActiveIndex((i) => Math.min(statuses.length - 1, i + 1))}
          className="flex h-11 w-8 shrink-0 items-center justify-center text-muted disabled:opacity-30"
        >
          ›
        </button>
      </div>

      <div className="flex items-center justify-center gap-1.5">
        {statuses.map((status, i) => (
          <span
            key={status.key}
            aria-hidden="true"
            className={`h-1.5 w-1.5 rounded-full ${i === activeIndex ? "bg-accent-strong" : "bg-border"}`}
          />
        ))}
      </div>

      <div className="flex flex-1 flex-col gap-2 overflow-y-auto">
        {activeItems.length === 0 ? (
          <div className="rounded-md border border-dashed border-border px-3 py-6 text-center text-sm text-muted">
            Empty
          </div>
        ) : (
          activeItems.map((item) => (
            <ItemCard
              key={item.id}
              item={item}
              href={`${boardHref}?item=${item.id}`}
              selected={selectedItem?.id === item.id}
              typeLabel={typeLabels.get(item.type) ?? item.type}
              assigneeName={item.assignee_id ? assigneeNames.get(item.assignee_id) ?? null : null}
            />
          ))
        )}
      </div>
    </div>
  );
}
