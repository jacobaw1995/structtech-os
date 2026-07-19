import Link from "next/link";
import type { Database } from "@/lib/supabase/database.types";
import { priorityLabel } from "@/lib/tracker/config";

type TrackerItem = Database["public"]["Tables"]["tracker_items"]["Row"];

export function ItemCard({
  item,
  href,
  selected,
  typeLabel,
  assigneeName,
}: {
  item: TrackerItem;
  href: string;
  selected: boolean;
  typeLabel: string;
  assigneeName: string | null;
}) {
  const isUrgentOrHigh = item.priority === "urgent" || item.priority === "high";

  return (
    <Link
      href={href}
      className={`flex flex-col gap-1.5 rounded-md border bg-surface p-3 text-left transition-colors hover:border-accent ${
        selected ? "border-accent ring-1 ring-accent" : "border-border"
      }`}
    >
      <span className="text-sm font-medium text-text">{item.title}</span>
      <div className="flex flex-wrap items-center gap-1.5">
        <span className="rounded-full bg-accent-soft px-2 py-0.5 text-[11px] text-accent-strong">
          {typeLabel}
        </span>
        <span
          className={`rounded-full px-2 py-0.5 text-[11px] ${
            isUrgentOrHigh ? "bg-warn-soft text-warn" : "bg-surface2 text-muted"
          }`}
        >
          {priorityLabel(item.priority)}
        </span>
      </div>
      {assigneeName && <span className="text-xs text-muted">{assigneeName}</span>}
    </Link>
  );
}
