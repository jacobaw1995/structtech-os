import { crewReadyByText, readyByState, type ReadyByInput } from "@/lib/materials/ready-by";

// WHAT THIS TRADE'S MATERIALS ARE, AND WHETHER THEY ARE READY. U-W1.22, 2026-09-19.
//
// Item 5 of the twelve a crew could not do: the crew CAN read material_items
// (measured 2026-09-18 as the real crew account) — no screen showed them. A crew
// that cannot see whether its materials are ready cannot plan the day.
//
// NO MONEY, BY CONSTRUCTION: material_items has no price, cost, total or amount
// column at all (checked against information_schema 2026-09-19), and the query
// behind this list names four columns. There is nothing money-shaped to leak and
// nothing to filter.

export type FieldMaterial = ReadyByInput & {
  id: string;
  name: string;
  quantity: number;
  unit: string | null;
};

export function MaterialsList({ items, todayIso }: { items: FieldMaterial[]; todayIso: string }) {
  if (items.length === 0) {
    return (
      <p className="text-base text-muted group-data-[outdoor=true]/field:text-white/80">
        No materials have been added to this trade yet.
      </p>
    );
  }

  // THREE ANSWERS, NOT TWO. A material with no date, or with a date its order no
  // longer backs, is NOT "not ready yet" — nobody knows when it is ready, and a
  // crew plans differently for the two. Counting them as late would be a guess
  // dressed as a count.
  const states = items.map((i) => readyByState(i, todayIso));
  const ready = states.filter((s) => s.kind === "ready").length;
  const notYet = states.filter((s) => s.kind === "not_yet").length;
  const unconfirmed = states.length - ready - notYet;

  return (
    <div className="flex flex-col gap-3">
      {/* The count first: on a phone, the answer to "can we work?" should not
          require scrolling a list. */}
      <p className="text-base text-text group-data-[outdoor=true]/field:text-white">
        {ready === items.length
          ? `All ${items.length} material${items.length === 1 ? "" : "s"} ready.`
          : [
              `${ready} of ${items.length} ready`,
              notYet > 0 ? `${notYet} not yet` : null,
              unconfirmed > 0 ? `${unconfirmed} with no confirmed date` : null,
            ]
              .filter(Boolean)
              .join(" · ") + "."}
      </p>

      {items.map((item) => {
        const state = readyByState(item, todayIso);
        const text = crewReadyByText(state);
        return (
          <div
            key={item.id}
            data-ready-state={state.kind}
            className="flex flex-col gap-1 rounded-xl border border-border p-3 group-data-[outdoor=true]/field:border-white/40"
          >
            <div className="flex flex-wrap items-baseline justify-between gap-x-3">
              <p className="text-base font-semibold text-text group-data-[outdoor=true]/field:text-white">
                {item.name}
              </p>
              <p className="font-mono text-base tabular-nums text-text group-data-[outdoor=true]/field:text-white">
                {item.quantity}
                {item.unit ? ` ${item.unit}` : ""}
              </p>
            </div>
            <p
              className={`text-base font-medium ${
                state.kind === "ready"
                  ? "text-accent-strong group-data-[outdoor=true]/field:text-white"
                  : "text-[var(--warn-strong)] group-data-[outdoor=true]/field:text-white"
              }`}
            >
              {text.label}
            </p>
            <p className="text-sm leading-relaxed text-muted group-data-[outdoor=true]/field:text-white/80">
              {text.detail}
            </p>
          </div>
        );
      })}
    </div>
  );
}
