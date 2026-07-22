// Client-safe: no server-only imports.
//
// Postgres `numeric` columns come back over PostgREST as JSON — and
// whatever scale the value was stored at (e.g. a quantity inserted/updated
// as "32.0000") is preserved verbatim, so a raw `{item.quantity}`
// interpolation can print "32.0000" or "1.00" on a document a customer
// reads. Coercing through Number() before display drops the trailing
// zeros for free (Number("32.0000").toString() === "32") — this is the fix
// for every raw numeric hitting the page, not just quantity.
export function formatQty(value: number | string | null): string {
  if (value == null) return "—";
  const n = typeof value === "string" ? Number(value) : value;
  if (!Number.isFinite(n)) return String(value);
  return n.toString();
}

// estimate_date/valid_until are Postgres `date` — no time, no offset.
// new Date("2026-09-01") parses that as UTC midnight, then
// .toLocaleDateString() renders it in the browser's LOCAL timezone — west
// of UTC that rolls back to Aug 31. Same bug, same fix as coordination's
// formatDateOnly (src/lib/coordination/stage.ts): split the string and
// build a Date with the LOCAL constructor instead of the ISO-string one,
// so there's no UTC round-trip to shift. Only for genuine date-only
// columns — timestamptz columns (presented_at, signed_at, created_at)
// already carry a real offset and must keep using new Date(iso) directly;
// running THIS function on one would double-apply a timezone shift.
export function formatDateOnly(value: string | null): string {
  if (!value) return "—";
  const [year, month, day] = value.split("-").map(Number);
  return new Date(year, month - 1, day).toLocaleDateString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}
