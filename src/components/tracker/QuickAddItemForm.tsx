"use client";

import { useRef, useState } from "react";
import { createTrackerItem } from "@/lib/tracker/actions";
import type { TrackerType } from "@/lib/tracker/config";
import { PRIORITY_OPTIONS } from "@/lib/tracker/config";

// THE critical UX (spec): title + type + priority in ~2 taps from a phone.
// Type/priority default to sensible values (first configured type — 'task'
// — and 'normal') as pre-highlighted pills, so the common case is tap the
// title field, type, tap Add — changing type/priority costs exactly one
// extra tap each, never a dropdown hunt.
export function QuickAddItemForm({
  orgId,
  projectId,
  types,
}: {
  orgId: string;
  projectId: string;
  types: TrackerType[];
}) {
  const formRef = useRef<HTMLFormElement>(null);
  const [type, setType] = useState(types[0]?.key ?? "task");
  const [priority, setPriority] = useState("normal");
  const [expanded, setExpanded] = useState(false);
  const [title, setTitle] = useState("");

  return (
    <form
      ref={formRef}
      action={createTrackerItem}
      className="flex flex-col gap-2 rounded-lg border border-border bg-surface p-3"
    >
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="type" value={type} />
      <input type="hidden" name="priority" value={priority} />

      <div className="flex gap-2">
        <input
          name="title"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          onFocus={() => setExpanded(true)}
          required
          placeholder="Quick-add a task, bug, feature, or idea…"
          className="min-h-14 flex-1 rounded-md border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent sm:min-h-0 sm:py-1.5 sm:text-sm"
        />
        <button
          type="submit"
          disabled={title.trim().length === 0}
          className="flex min-h-14 shrink-0 items-center rounded-md bg-accent-strong px-4 text-sm font-medium text-white disabled:opacity-40 sm:min-h-0 sm:py-1.5"
        >
          Add
        </button>
      </div>

      {expanded && (
        <div className="flex flex-wrap items-center gap-3">
          <div className="flex flex-wrap gap-1.5">
            {types.map((t) => (
              <button
                key={t.key}
                type="button"
                onClick={() => setType(t.key)}
                className={`min-h-11 rounded-full px-3 text-xs font-medium sm:min-h-0 sm:py-1 ${
                  type === t.key ? "bg-accent-soft text-accent-strong" : "bg-surface2 text-muted"
                }`}
              >
                {t.label}
              </button>
            ))}
          </div>
          <div className="flex flex-wrap gap-1.5">
            {PRIORITY_OPTIONS.map((p) => (
              <button
                key={p.key}
                type="button"
                onClick={() => setPriority(p.key)}
                className={`min-h-11 rounded-full px-3 text-xs font-medium sm:min-h-0 sm:py-1 ${
                  priority === p.key ? "bg-warn-soft text-warn" : "bg-surface2 text-muted"
                }`}
              >
                {p.label}
              </button>
            ))}
          </div>
        </div>
      )}
    </form>
  );
}
