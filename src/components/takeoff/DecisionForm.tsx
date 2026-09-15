"use client";

import { useState } from "react";
import { setTakeOffDecision } from "@/lib/takeoff/actions";
import type { TradeRef } from "@/lib/takeoff/review";

type Disposition = "material" | "not_material" | "undecided";

/**
 * One line's decision. Client-side only so the trade picker can follow the
 * disposition choice: a trade is meaningful for "material" and nothing else, and
 * set_take_off_decision refuses a trade sent with anything else.
 *
 * NEVER OFFERS WHAT THE RPC REFUSES (U-W1.6). When a material already exists for
 * the line, "not material" and "undecided" are refused ("delete that material
 * first"), and so is "material with no trade" — so those are not offered. What
 * is offered instead is the one move the RPC accepts: choose the trade, and the
 * material moves there.
 */
export function DecisionForm({
  orgId,
  masterWorkOrderId,
  lineId,
  current,
  currentTradeId,
  materialTradeName,
  materialTradeHref,
  liveTrades,
  addTradeHref,
}: {
  orgId: string;
  masterWorkOrderId: string;
  lineId: string;
  current: Disposition;
  currentTradeId: string | null;
  /** Set when a material item exists for this line. */
  materialTradeName: string | null;
  materialTradeHref: string | null;
  liveTrades: TradeRef[];
  addTradeHref: string;
}) {
  const hasItem = materialTradeName !== null;
  const [choice, setChoice] = useState<Disposition>(hasItem ? "material" : current);
  const liveCurrent = liveTrades.some((t) => t.id === currentTradeId) ? currentTradeId : null;
  // With a material, the only accepted write is a MOVE to another live trade.
  // If there is no other live trade, every submission is either refused or an
  // unchanged re-send, so no submission is offered.
  const canMove = liveTrades.some((t) => t.id !== currentTradeId);
  const offerSubmit = !hasItem || canMove;

  const options: { value: Disposition; label: string }[] = hasItem
    ? [{ value: "material", label: "Material" }]
    : [
        { value: "material", label: "Material" },
        { value: "not_material", label: "Not material" },
        // Offered only to UNDO a decision. On a line that is already undecided,
        // choosing undecided changes nothing, and a control that changes nothing
        // is not a control.
        ...(current !== "undecided" ? [{ value: "undecided" as const, label: "Undecided" }] : []),
      ];

  return (
    <form action={setTakeOffDecision} className="mt-2 flex flex-col gap-2">
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="masterWorkOrderId" value={masterWorkOrderId} />
      <input type="hidden" name="lineId" value={lineId} />

      {options.length > 1 ? (
        <fieldset className="flex flex-wrap gap-2">
          <legend className="sr-only">Is this line material?</legend>
          {options.map((o) => (
            <label
              key={o.value}
              className={`flex min-h-14 cursor-pointer items-center gap-2 rounded-md border px-3 text-sm sm:min-h-10 ${
                choice === o.value ? "border-accent bg-accent-soft text-accent-strong" : "border-border text-text"
              }`}
            >
              <input
                type="radio"
                name="disposition"
                value={o.value}
                checked={choice === o.value}
                required
                onChange={() => setChoice(o.value)}
                className="h-4 w-4"
              />
              {o.label}
            </label>
          ))}
        </fieldset>
      ) : (
        <input type="hidden" name="disposition" value="material" />
      )}

      {hasItem && (
        <p className="text-xs leading-relaxed text-muted">
          A material for this line is on <span className="font-medium text-text">{materialTradeName}</span>. To
          mark the line not material or undecided, delete that material first
          {materialTradeHref ? (
            <>
              {" "}
              on{" "}
              <a href={materialTradeHref} className="text-accent-strong underline">
                its trade
              </a>
            </>
          ) : null}
          .{canMove ? " Choosing another trade below moves the material there." : " There is no other live trade on this job to move it to."}
        </p>
      )}

      {choice === "material" && offerSubmit &&
        (liveTrades.length === 0 ? (
          // SCOPE §2.8: say so and link to the fix. Saving "material" still
          // works — the trade question simply stays open until a trade exists.
          <p className="text-xs leading-relaxed text-[var(--warn-strong)]">
            This job has no live trades, so there is no trade to choose yet. You can still record
            the line as material now.{" "}
            <a href={addTradeHref} className="font-medium text-accent-strong underline">
              Add a trade
            </a>{" "}
            to answer which trade it goes on.
          </p>
        ) : (
          <label className="flex flex-col gap-1 text-xs text-muted">
            Which trade?
            <select
              name="workOrderId"
              defaultValue={liveCurrent ?? ""}
              className="min-h-14 rounded-md border border-border bg-bg px-2 text-sm text-text sm:min-h-10"
            >
              {/* No empty option once a material exists: the RPC refuses
                  "material, no trade" for a line with a material. */}
              {!hasItem && <option value="">No trade yet</option>}
              {liveTrades.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.trade || "Unnamed trade"}
                </option>
              ))}
            </select>
          </label>
        ))}

      {offerSubmit && (
      <button
        type="submit"
        className="flex min-h-14 items-center justify-center self-start rounded-md bg-accent-strong px-4 text-sm font-semibold text-white sm:min-h-10"
      >
        Save decision
      </button>
      )}
    </form>
  );
}
