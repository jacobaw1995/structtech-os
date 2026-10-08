// The one place that knows what an unreadable Vercel value looks like.
// Track X, 2026-10-06.
//
// FACTORED, NOT COPIED, AND THE REASON IS THE BUG ITSELF. A Vercel variable typed
// Sensitive is WRITE-ONLY: the dashboard, the API and `vercel env pull` all refuse
// to return it, and the pull writes the literal `[SENSITIVE]` in its place. Three
// separate checks in this repo now have to recognise that string. Three copies of
// a literal is three chances for one of them to drift and start reporting a
// placeholder as a real value — which is exactly the false red that cost two days
// on 2026-10-05 (CLAUDE.md rules 28 and 29).
//
// KEYED ON THE LITERAL, NEVER ON ITS SHAPE. `[SENSITIVE]` happens to be 11
// characters with no lowercase letter and no "true" substring, and the first
// version of this check matched on those properties. They are coincidences of one
// string: `DEVELOPMENT` is also 11 uppercase characters and IS a genuinely wrong
// value. Comparing the literal also fails CLOSED — if Vercel ever rewords the
// placeholder, the comparison stops matching and the caller falls through to its
// ordinary "wrong value" branch, which is the safe direction.
export const SENSITIVE_PLACEHOLDER = '[SENSITIVE]';

/** The value `vercel env pull` writes when it will not tell us the real one. */
export function isUnreadable(value) {
  return value === SENSITIVE_PLACEHOLDER;
}

/**
 * The sentence every caller says about it.
 *
 * IT NAMES THE FIX, AND THE FIX IS NOT "EDIT THE VALUE". A sensitive variable's
 * value cannot be read back or corrected in place; it has to be removed and
 * recreated as a normal variable. A message that says "wrong value" sends someone
 * to a settings page to do the one thing that cannot work — which happened three
 * times to the same person on the same variable.
 */
export function unreadableMessage(name) {
  return `${name} is typed SENSITIVE in Vercel, so its value cannot be read back and this check CANNOT say whether it is correct. `
    + `THE FIX IS NOT TO EDIT THE VALUE — a sensitive variable cannot be read or corrected in place. `
    + `Remove it and recreate it as a normal (non-sensitive) variable, then redeploy.`;
}

/** Strip the quoting `vercel env pull` may add, so callers compare what the app compares. */
export function envValue(line, key) {
  return line.slice(key.length + 1).trim().replace(/^["']+|["']+$/g, '');
}
