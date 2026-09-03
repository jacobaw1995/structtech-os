// Catalog money is UNIT price, and unit price needs cents.
//
// `formatMoney` in @/lib/crm/stages is built for JOB money — a deal worth
// $12,000, an estimate total — and carries `maximumFractionDigits: 0`, which is
// right there and wrong here. A catalog is full of numbers where the cents ARE
// the number: ridge cap at $19.20/lf, a fastener at $0.85/ea. Through
// formatMoney those render "$19" and "$1".
//
// This is not theoretical. The A2 check-out script's own step 4 tells Jacob to
// enter cost 12 + markup 60 and SEE 19.20 — a value the shipped table could not
// display. The step would have failed on the display, not on the arithmetic,
// and the arithmetic is what it was written to test.
export function formatUnitPrice(value: number | string | null): string | null {
  if (value === null || value === undefined) return null;
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n)) return null;
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(n);
}

// Markup on the LIST is rounded to a whole percent. Seen on screen at 375px,
// "+102.38%" beside "$0.85" was the noisiest thing in the row and the two
// decimals carried no information a reader acts on — nobody sets 102.38%
// markup, they set a sell price and the derivation lands there. The exact
// stored value is unrounded and is shown, to the cent, in the edit form where
// it is authored.
export function formatMarkup(value: number | string | null): string | null {
  if (value === null || value === undefined) return null;
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n)) return null;
  return `${Math.round(n)}%`;
}
