"use client";

import { useState } from "react";

// A2.1c / Step 1 — Jacob's decision (2026-08-26): enter cost plus EITHER sell
// OR markup, and the other fills in.
//
// The directionality problem was never a STORAGE problem, it was an INPUT
// problem — which is why the fix lives here and in the RPC, not in a generated
// column. A generated column can only ever run one direction, and that was the
// whole complaint.
//
// This component owns which field the user typed. The other is recomputed and
// labelled "calculated", so the two are never silently indistinguishable — the
// user should always be able to see which number they authored. It is a UI
// concern only — the server does not need to be told, because the derivation
// rule is unambiguous from which values arrive.
export function PriceFields({
  defaultCost,
  defaultSell,
  defaultMarkup,
  disabled,
}: {
  defaultCost?: number | string | null;
  defaultSell?: number | string | null;
  defaultMarkup?: number | string | null;
  disabled?: boolean;
}) {
  const [cost, setCost] = useState(str(defaultCost));
  const [sell, setSell] = useState(str(defaultSell));
  const [markup, setMarkup] = useState(str(defaultMarkup));
  // Which of sell/markup the user last authored. Starts at "sell" for an
  // existing row because sell is the money and is always authoritative.
  const [pinned, setPinned] = useState<"sell" | "markup">("sell");

  function onCost(v: string) {
    setCost(v);
    const c = num(v);
    if (c === null || c === 0) return;
    if (pinned === "markup") {
      const m = num(markup);
      if (m !== null) setSell(String(round2(c * (1 + m / 100))));
    } else {
      const s = num(sell);
      if (s !== null) setMarkup(String(round2(((s - c) / c) * 100)));
    }
  }

  function onSell(v: string) {
    setPinned("sell");
    setSell(v);
    const c = num(cost);
    const s = num(v);
    // markup needs a non-zero cost to mean anything — mirrors the RPC, which
    // refuses rather than inventing one. A zero-cost labour line simply has no
    // markup, and the field goes blank rather than showing a fabricated number.
    setMarkup(c === null || c === 0 || s === null ? "" : String(round2(((s - c) / c) * 100)));
  }

  function onMarkup(v: string) {
    setPinned("markup");
    setMarkup(v);
    const c = num(cost);
    const m = num(v);
    if (c === null || c === 0 || m === null) return;
    setSell(String(round2(c * (1 + m / 100))));
  }

  const costIsZeroish = num(cost) === 0 || num(cost) === null;

  return (
    <>
      <Num label="Cost" name="cost" value={cost} onChange={onCost} disabled={disabled} hint="what it costs you" />
      <Num
        label="Sell"
        name="sell"
        value={sell}
        onChange={onSell}
        disabled={disabled}
        hint={pinned === "markup" ? "calculated" : "entered"}
        derived={pinned === "markup"}
      />
      <Num
        label="Markup %"
        name="markup"
        value={markup}
        onChange={onMarkup}
        disabled={disabled}
        hint={costIsZeroish ? "needs a cost" : pinned === "sell" ? "calculated" : "entered"}
        derived={pinned === "sell"}
      />
    </>
  );
}

function Num({
  label,
  name,
  value,
  onChange,
  disabled,
  hint,
  derived,
}: {
  label: string;
  name: string;
  value: string;
  onChange: (v: string) => void;
  disabled?: boolean;
  hint?: string;
  derived?: boolean;
}) {
  return (
    <label className="flex w-28 flex-col gap-1">
      <span className="text-xs font-medium text-muted">{label}</span>
      <input
        type="number"
        step="0.01"
        // inputMode decimal so a phone offers the numeric pad rather than the
        // full keyboard — you type these standing on a driveway (SCOPE §2.4).
        inputMode="decimal"
        name={name}
        value={value}
        disabled={disabled}
        onChange={(e) => onChange(e.target.value)}
        // min-h-14 = 56dp below sm (§2.4); text-base because iOS Safari zooms
        // the viewport on focus for anything under 16px. tabular-nums so the
        // three boxes read as a column of figures — controller decision 1.1
        // moved money off mono, and this is the property mono provided.
        className={`min-h-14 rounded-md border px-3 text-base tabular-nums sm:min-h-0 sm:h-10 sm:text-sm ${
          derived ? "border-border bg-surface2 text-muted" : "border-border bg-surface text-text"
        }`}
      />
      {hint && <span className="text-[10px] uppercase tracking-wide text-muted">{hint}</span>}
    </label>
  );
}

function str(v: number | string | null | undefined) {
  return v === null || v === undefined ? "" : String(v);
}
function num(v: string) {
  if (v.trim() === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}
function round2(n: number) {
  return Math.round(n * 100) / 100;
}
