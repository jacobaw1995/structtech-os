// WHAT GOES WHERE ON THIS ROOF, AND WHAT IS DIFFERENT ABOUT IT.
// Track U, U-W1.35, 2026-09-25. Client-safe: no server imports.
//
// MVP IS A STRUCTURED LIST. Graphical roof and trim maps are deferred to
// November — there is no canvas here, no image, no coordinates, and none of
// this file assumes any.
//
// THE PROPERTY IT SERVES: a crew arriving at a job reads, from ONE list, what
// goes where and what is different about this roof. So a callout is not a
// sentence somebody typed — it is a PLACE plus WHAT GOES THERE, which is what
// makes it a list you can scan from the truck instead of a paragraph you have
// to read.
//
// WHAT EXISTS TODAY, measured 2026-09-25: production_packets.callouts is jsonb
// holding `{ id, label, detail }` — free text, no place, 0 rows in the whole
// database, 0 packets. The office types a sentence and the crew reads it.
//
// UNWIRED, AND NOT MOUNTED. Track S is deriving the structured data in its own
// session; nothing has landed on main. So this is the SHAPE — and `parseRoofCallouts`
// is deliberately TOLERANT of the existing free-text rows, so that when the
// derived data arrives with places on it, the same parser picks them up and the
// rows that never had a place still render rather than vanishing. The place
// vocabulary below is the surface's proposal and has to be reconciled with S's
// when it lands; it is not a contract yet, and this file says so rather than
// letting a later reader assume it was agreed.

export type RoofPlace = { code: string; label: string };

/** In the crew's words — what a roofer points at, not what a table calls it. */
export const ROOF_PLACES: RoofPlace[] = [
  { code: "panels", label: "Panels" },
  { code: "ridge", label: "Ridge" },
  { code: "hips", label: "Hips" },
  { code: "valleys", label: "Valleys" },
  { code: "eaves", label: "Eaves / drip edge" },
  { code: "rakes", label: "Rakes / gable ends" },
  { code: "sidewall", label: "Where the roof meets a wall" },
  { code: "headwall", label: "Headwall" },
  { code: "pipes", label: "Pipe boots" },
  { code: "vents", label: "Vents" },
  { code: "chimney", label: "Chimney" },
  { code: "skylights", label: "Skylights" },
  { code: "gutters", label: "Gutters" },
  { code: "trim", label: "Trim / fascia" },
];

export function roofPlaceLabel(code: string | null): string | null {
  if (!code) return null;
  return ROOF_PLACES.find((p) => p.code === code)?.label ?? null;
}

export type RoofCallout = {
  id: string;
  /** null = recorded without a place. Rendered, never dropped. */
  place: string | null;
  /** What goes there, as the office recorded it: "Charcoal", "26ga", "2in". */
  what: string;
  note: string | null;
  /** Different from the usual on this job — surfaced first. */
  unusual: boolean;
};

/**
 * THREE ANSWERS, the same three the QC panel learned to give: we read it, we
 * read it and it is empty, or we could not read it. An unreadable list must
 * never render as "nothing special about this roof" — that is the sentence a
 * crew would act on by doing the ordinary thing.
 */
export type RoofCalloutRead = { state: "ok"; callouts: RoofCallout[] } | { state: "unreadable" };

/** Tolerant by design — see the note at the top. Never throws mid-render. */
export function parseRoofCallouts(value: unknown): RoofCallout[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((c): c is Record<string, unknown> => typeof c === "object" && c !== null && !Array.isArray(c))
    .map((c) => ({
      id: typeof c.id === "string" ? c.id : "",
      place: typeof c.place === "string" && c.place.length > 0 ? c.place : null,
      // `label` is the existing free-text field; it carries the "what" until the
      // derived data replaces it.
      what: typeof c.what === "string" ? c.what : typeof c.label === "string" ? c.label : "",
      note: typeof c.note === "string" ? c.note : typeof c.detail === "string" ? c.detail : null,
      unusual: c.unusual === true,
    }))
    .filter((c) => c.id.length > 0 && c.what.length > 0);
}

/** The places this roof says nothing about. A state, not an absence. */
export function placesNotSpecified(callouts: RoofCallout[]): RoofPlace[] {
  const spoken = new Set(callouts.map((c) => c.place).filter((p): p is string => p !== null));
  return ROOF_PLACES.filter((p) => !spoken.has(p.code));
}

/** Ordered for a person arriving at a job: what is different first, then the roof top-down. */
export function orderedCallouts(callouts: RoofCallout[]): RoofCallout[] {
  const rank = (c: RoofCallout) => {
    const i = ROOF_PLACES.findIndex((p) => p.code === c.place);
    return i === -1 ? ROOF_PLACES.length : i;
  };
  return [...callouts].sort((a, b) => Number(b.unusual) - Number(a.unusual) || rank(a) - rank(b));
}
