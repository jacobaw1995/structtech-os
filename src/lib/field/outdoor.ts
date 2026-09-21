// OUTDOOR MODE'S STORED PREFERENCE — one name for both sides. Track U, U-W1.26,
// 2026-09-21. Client-safe on purpose: no server imports, so the server pages and
// the client toggle read the SAME constant. (A constant imported from a
// "use client" module into a server component arrives as a client reference,
// not a string — so it cannot live in FieldShell.tsx.)
//
// WHY A COOKIE AND NOT ONLY localStorage. Measured 2026-09-21, with the mode
// saved as ON: every in-app navigation INSERTED the next screen with
// data-outdoor="false" and switched it to "true" in a second commit, from a
// useEffect — which the browser may paint between. And a full reload shipped
// server HTML with data-outdoor="false" (curl). A crew member in bright sun got
// a white screen on every tap before the dark one arrived. localStorage cannot
// fix that: the server cannot read it. A cookie the server CAN read lets the
// first render already be the right one.

export const OUTDOOR_COOKIE = "stos_field_outdoor";

/** The legacy key, still read once so nobody who already turned it on loses it. */
export const OUTDOOR_LEGACY_STORAGE_KEY = "stos.field.outdoor";

/** `null` = no cookie yet, which is not the same as "off": the client then checks the legacy key. */
export function parseOutdoorCookie(value: string | undefined): boolean | null {
  if (value === "1") return true;
  if (value === "0") return false;
  return null;
}
