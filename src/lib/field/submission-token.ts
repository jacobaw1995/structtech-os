// ONE TOKEN = ONE ATTEMPT TO RECORD SOMETHING. Track U, U-W1.53, 2026-10-04.
//
// S's 20261004213144 added `check_ins.client_token` and a partial unique index
// on (org_id, client_token). The function treats NULL as "no token sent, never
// deduplicated" — so until a caller sends one, the dedup exists and does
// nothing. This is the caller's half.
//
// crypto.randomUUID() needs a secure context and Safari 15.4+. A crew's phone
// is the one device in this build we cannot choose, so there is a fallback
// rather than an exception thrown on a roof. getRandomValues is older and
// universally present; the last resort is not cryptographic and does not need
// to be — this value's only job is to be unlikely to collide with the other
// submissions of the same org, and it is scoped to one org by the index.
export function newSubmissionToken(): string {
  const c: Crypto | undefined = typeof crypto !== "undefined" ? crypto : undefined;
  if (c && typeof c.randomUUID === "function") return c.randomUUID();
  if (c && typeof c.getRandomValues === "function") {
    const b = c.getRandomValues(new Uint8Array(16));
    return Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
  }
  return `t${Date.now().toString(36)}${Math.random().toString(36).slice(2, 14)}`;
}
