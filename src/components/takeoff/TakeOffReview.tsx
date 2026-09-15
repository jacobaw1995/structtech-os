import { DecisionForm } from "@/components/takeoff/DecisionForm";
import {
  itemStateText,
  nyDate,
  sourceText,
  type ReviewLine,
  type TakeOffReview as Review,
  type TradeRef,
} from "@/lib/takeoff/review";

// The job-level take-off review (U-W1.14). Server component: the only client
// piece is the per-line DecisionForm. What it does NOT have is a "take off"
// button — see the stop note at the bottom.

type Props = {
  orgId: string;
  masterWorkOrderId: string;
  review: Review;
  trades: TradeRef[];
  memberName: (id: string | null) => string | null;
  error: string | null;
  unchanged: boolean;
  focusLineId: string | null;
};

export function TakeOffReview({ orgId, masterWorkOrderId, review, trades, memberName, error, unchanged, focusLineId }: Props) {
  const total = review.lines.length;
  const tradeName = (id: string | null) => trades.find((t) => t.id === id)?.trade || "an unnamed trade";
  const tradeHref = (id: string | null) => (id ? `/w/${orgId}/coordination/${id}` : null);
  const addTradeHref = `/w/${orgId}/coordination/${masterWorkOrderId}#add-trade`;

  const form = (line: ReviewLine) => (
    <DecisionForm
      orgId={orgId}
      masterWorkOrderId={masterWorkOrderId}
      lineId={line.lineId}
      current={line.disposition}
      currentTradeId={line.tradeWorkOrderId}
      materialTradeName={line.materialItemId ? tradeName(line.materialWorkOrderId) : null}
      materialTradeHref={line.materialItemId ? tradeHref(line.materialWorkOrderId) : null}
      liveTrades={review.liveTrades}
      addTradeHref={addTradeHref}
    />
  );

  const row = (line: ReviewLine, opts: { open?: boolean; withForm?: "open" | "closed" | "none"; extra?: string }) => (
    <li
      key={line.lineId}
      id={`line-${line.lineId}`}
      data-line-state={`${line.disposition}|${line.tradeState}|${line.itemState}`}
      className="scroll-mt-4 border-b border-border py-3 last:border-0"
    >
      <div className="flex flex-wrap items-baseline justify-between gap-x-3">
        <p className="min-w-0 text-sm font-medium text-text">{line.description || "Untitled line"}</p>
        <p className="shrink-0 font-mono text-xs tabular-nums text-muted">
          {line.quantity ?? "—"}
          {line.unit ? ` ${line.unit}` : ""}
        </p>
      </div>
      {opts.extra && <p className="mt-0.5 text-xs leading-relaxed text-text">{opts.extra}</p>}
      {sourceText(line, memberName) && (
        <p
          data-source={line.source ?? ""}
          className={`mt-0.5 text-xs leading-relaxed ${line.source === "backfill" ? "text-[var(--warn-strong)]" : "text-muted"}`}
        >
          {sourceText(line, memberName)}
        </p>
      )}
      {error && focusLineId === line.lineId && (
        <p className="mt-2 rounded-md border border-warn bg-warn-soft px-3 py-2 text-sm text-text">{error}</p>
      )}
      {unchanged && focusLineId === line.lineId && (
        <p className="mt-2 rounded-md bg-surface2 px-3 py-2 text-sm text-text">
          Nothing was saved — that is already this line&rsquo;s decision.
        </p>
      )}
      {opts.withForm === "open" && form(line)}
      {opts.withForm === "closed" && (
        <details open={focusLineId === line.lineId} className="mt-1">
          <summary className="flex min-h-14 cursor-pointer items-center text-xs font-medium text-accent-strong sm:min-h-8">
            Change decision
          </summary>
          {form(line)}
        </details>
      )}
    </li>
  );

  return (
    <section id="takeoff" data-takeoff-review className="scroll-mt-4 rounded-lg border border-border bg-surface">
      <header className="border-b border-border px-4 py-3">
        <h2 className="text-sm font-semibold text-text">Take-off review</h2>
        <p className="mt-0.5 text-xs text-muted">
          <span className="font-mono tabular-nums">{total}</span> {total === 1 ? "line" : "lines"} on this job&rsquo;s
          estimate
          {review.estimateStatus ? ` (${review.estimateStatus})` : ""} ·{" "}
          <span className="font-mono tabular-nums">{review.liveTrades.length}</span> live{" "}
          {review.liveTrades.length === 1 ? "trade" : "trades"}
        </p>
      </header>

      {total === 0 && review.leftovers.length === 0 ? (
        <p className="px-4 py-3 text-sm text-muted">This job&rsquo;s estimate has no lines to review.</p>
      ) : (
        <div className="flex flex-col divide-y divide-border">
          {/* 2. WHAT CAME ACROSS */}
          <Block
            id="came-across"
            title="What came across"
            count={review.cameAcross.length}
            of={total}
            unit="lines have a material on a trade"
            empty="No line has a material yet."
          >
            {groupByTrade(review.cameAcross).map(([wo, lines]) => (
              <div key={wo ?? "none"} className="mt-2">
                <p className="text-xs font-semibold uppercase tracking-wide text-muted">
                  {tradeHref(wo) ? (
                    <a href={tradeHref(wo)!} className="text-accent-strong">
                      {tradeName(wo)}
                    </a>
                  ) : (
                    tradeName(wo)
                  )}{" "}
                  · <span className="font-mono tabular-nums">{lines.length}</span>
                </p>
                <ul>{lines.map((l) => row(l, { withForm: "closed", extra: itemStateText(l, tradeName) }))}</ul>
              </div>
            ))}
          </Block>

          {/* 3. THE THREE UNDECIDED QUESTIONS — three blocks, three counts. */}
          <Block
            id="is-material"
            title="Is this material?"
            count={review.isMaterial.length}
            of={total}
            unit="lines have no decision"
            empty="Every line has a decision."
          >
            {review.isMaterial.length > 0 && review.liveTrades.length === 0 && (
              // SCOPE §2.8 — say so, link to the fix, block nothing. A line can
              // be decided material without a trade; only "which trade" waits.
              <p data-no-trades className="mt-2 text-sm leading-relaxed text-[var(--warn-strong)]">
                This job has no live trades. You can decide whether each line is material now; which
                trade a material line goes on can only be answered once a trade exists.{" "}
                <a href={addTradeHref} className="font-medium text-accent-strong underline">
                  Add a trade
                </a>
                .
              </p>
            )}
            <ul>{review.isMaterial.map((l) => row(l, { withForm: "open" }))}</ul>
          </Block>

          <Block
            id="which-trade"
            title="Which trade?"
            count={review.whichTrade.length}
            of={review.lines.filter((l) => l.disposition === "material").length}
            unit="material lines have no trade"
            empty="Every material line has a trade."
          >
            {review.whichTrade.length > 0 && review.liveTrades.length === 0 && (
              <p className="mt-2 text-sm text-[var(--warn-strong)]">
                This job has no live trades, so none of these can be answered yet.{" "}
                <a href={addTradeHref} className="font-medium text-accent-strong underline">
                  Add a trade
                </a>
                .
              </p>
            )}
            <ul>{review.whichTrade.map((l) => row(l, { withForm: "open" }))}</ul>
          </Block>

          <Block
            id="trade-voided"
            title="The chosen trade was voided"
            count={review.tradeVoided.length}
            of={review.lines.filter((l) => l.disposition === "material").length}
            unit="material lines point at a voided trade"
            empty="No material line points at a voided trade."
          >
            <ul>
              {review.tradeVoided.map((l) =>
                row(l, { withForm: "open", extra: `Decided for ${tradeName(l.tradeWorkOrderId)}, which has been voided.` })
              )}
            </ul>
          </Block>

          {/* Decided, material, on a live trade, with no material yet. */}
          <Block
            id="not-taken-off"
            title="Decided, no material yet"
            count={review.decidedNotTakenOff.length}
            of={total}
            unit="lines are ready to become materials"
            empty="No decided line is waiting for a material."
          >
            <ul>
              {review.decidedNotTakenOff.map((l) =>
                row(l, { withForm: "closed", extra: `Goes on ${tradeName(l.tradeWorkOrderId)}.` })
              )}
            </ul>
          </Block>

          {/* 6. LEFTOVERS AND REMOVALS */}
          <Block
            id="removed"
            title="Materials a person deleted"
            count={review.removedByHuman.length}
            of={total}
            unit="lines had their material deleted"
            empty="No taken-off material has been deleted."
          >
            <ul>
              {review.removedByHuman.map((l) =>
                row(l, {
                  withForm: "closed",
                  extra: `${itemStateText(l, tradeName)}${
                    l.decision?.item_removed_at
                      ? ` Deleted by ${memberName(l.decision.item_removed_by) ?? "a person whose name is not recorded"} on ${nyDate(l.decision.item_removed_at)}.`
                      : ""
                  }`,
                })
              )}
            </ul>
          </Block>

          <Block
            id="leftovers"
            title="Materials whose estimate line is gone"
            count={review.leftovers.length}
            unit={review.leftovers.length === 1 ? "material on this job" : "materials on this job"}
            empty="Every taken-off material still has its estimate line."
          >
            <ul>
              {review.leftovers.map((m) => (
                <li key={m.materialItemId} className="border-b border-border py-3 last:border-0">
                  <div className="flex flex-wrap items-baseline justify-between gap-x-3">
                    <p className="text-sm font-medium text-text">{m.description ?? "Untitled material"}</p>
                    <p className="font-mono text-xs tabular-nums text-muted">
                      {m.quantity ?? "—"}
                      {m.unit ? ` ${m.unit}` : ""}
                    </p>
                  </div>
                  <p className="mt-0.5 text-xs leading-relaxed text-text">
                    {m.itemState === "estimate_line_deleted"
                      ? "The estimate line it was taken off from has been deleted."
                      : "The estimate line it was taken off from is not on this job's estimate."}{" "}
                    It stays on {tradeName(m.materialWorkOrderId)} until someone keeps or deletes it
                    {tradeHref(m.materialWorkOrderId) ? (
                      <>
                        {" "}
                        <a href={tradeHref(m.materialWorkOrderId)!} className="text-accent-strong underline">
                          there
                        </a>
                      </>
                    ) : null}
                    .
                  </p>
                </li>
              ))}
            </ul>
          </Block>

          {review.unrecognised.length > 0 && (
            <Block
              id="unrecognised"
              title="States this page does not recognise"
              count={review.unrecognised.length}
              of={total}
              unit="lines"
              empty=""
            >
              <ul>
                {review.unrecognised.map((l) =>
                  row(l, { withForm: "none", extra: `The database reports "${l.itemState ?? "no state"}" for this line.` })
                )}
              </ul>
            </Block>
          )}

          <Block
            id="not-material"
            title="Decided not material"
            count={review.notMaterial.length}
            of={total}
            unit="lines"
            empty="No line is decided not material."
            collapsed
          >
            <ul>{review.notMaterial.map((l) => row(l, { withForm: "closed" }))}</ul>
          </Block>
        </div>
      )}

      {/* STOPPED HERE, per the controller's ruling: the materialise action waits
          for Track S to report whether generate_take_off or materialize_take_off
          survives. Nothing on this surface creates a material. */}
    </section>
  );
}

function groupByTrade(lines: ReviewLine[]): [string | null, ReviewLine[]][] {
  const m = new Map<string | null, ReviewLine[]>();
  for (const l of lines) {
    const k = l.materialWorkOrderId;
    m.set(k, [...(m.get(k) ?? []), l]);
  }
  return Array.from(m.entries());
}

function Block({
  id,
  title,
  count,
  of,
  unit,
  empty,
  collapsed,
  children,
}: {
  id: string;
  title: string;
  count: number;
  of?: number;
  unit: string;
  empty: string;
  collapsed?: boolean;
  children: React.ReactNode;
}) {
  // "0 of 0" is arithmetic, not information: with no denominator, show the count alone.
  if (of === 0) of = undefined;
  const head = (
    <div className="flex flex-wrap items-baseline justify-between gap-x-3">
      <h3 className="text-sm font-semibold text-text">{title}</h3>
      <p className="text-xs text-muted">
        <span className="font-mono tabular-nums">{count}</span>
        {of !== undefined && (
          <>
            {" "}
            of <span className="font-mono tabular-nums">{of}</span>
          </>
        )}{" "}
        {unit}
      </p>
    </div>
  );
  return (
    <div data-block={id} data-count={count} className="px-4 py-3">
      {collapsed && count > 0 ? (
        <details>
          <summary className="flex min-h-14 cursor-pointer list-none items-center sm:min-h-8 [&::-webkit-details-marker]:hidden">
            <div className="w-full">{head}</div>
          </summary>
          {children}
        </details>
      ) : (
        <>
          {head}
          {count === 0 ? <p className="mt-1 text-xs text-muted">{empty}</p> : children}
        </>
      )}
    </div>
  );
}
