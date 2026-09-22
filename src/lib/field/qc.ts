// QC items — what a crew must prove before the day closes.  Track X, X-W1.20,
// 2026-09-19. A4.3: "Required photo by intersection type, countable checks, sweep
// confirmations; blocking vs advisory."
//
// A REQUIREMENT THAT WAS NOT DONE IS A STATE, NOT AN ABSENCE. The list below is
// what the screen renders, one row each, so "no photo yet" is a row that says so.
// A requirement that does not apply to this trade renders too, in its own section,
// saying it does not apply — because "not photographed" and "not required here"
// are different facts and a crew on a roof must not have to infer which they are
// looking at.
//
// WHERE THESE CAME FROM. The Build Tracker note on the QC item (#b1735208):
// "Skipped rivets in Sidney; missing ridge-cap rivets holding payment on a
// completed job." Plus the module text: photos by intersection, countable checks,
// magnet sweep. They are CODE, not config, for the pilot; the per-tenant config
// belongs with the rest of the field config and is a later item. Every key matches
// ^[a-z_]{1,40}$, the shape qc_items accepts.
//
// BLOCKING IS ADVISORY TODAY (SCOPE §2.8: never block the user). `blocking` only
// decides how the row reads. Nothing here prevents a check-in being saved.

export type QcKind = "photo" | "count" | "confirm";

export type QcRequirement = {
  key: string;
  label: string;
  kind: QcKind;
  /** Loud when outstanding: the ones that have cost money or held up payment. */
  blocking: boolean;
  /** Trades this applies to. `null` = every trade. */
  trades: string[] | null;
  /** What to photograph or count, in the crew's words. */
  help: string;
};

export const QC_REQUIREMENTS: QcRequirement[] = [
  {
    key: "valley_flashing",
    label: "Valley flashing",
    kind: "photo",
    blocking: true,
    trades: ["roofing"],
    help: "One photo down the valley before it is covered.",
  },
  {
    key: "penetration_flashing",
    label: "Penetration flashing",
    kind: "photo",
    blocking: true,
    trades: ["roofing"],
    help: "Each pipe, vent or curb after flashing.",
  },
  {
    key: "eave_detail",
    label: "Eave / drip edge",
    kind: "photo",
    blocking: false,
    trades: ["roofing"],
    help: "One photo along the eave showing the drip edge.",
  },
  {
    key: "ridge_cap",
    label: "Ridge cap",
    kind: "photo",
    blocking: false,
    trades: ["roofing"],
    help: "One photo along the finished ridge.",
  },
  {
    key: "wall_flashing",
    label: "Wall / step flashing",
    kind: "photo",
    blocking: false,
    trades: ["roofing", "siding"],
    help: "Where the roof meets a wall.",
  },
  {
    key: "ridge_cap_rivets",
    label: "Ridge-cap rivets",
    kind: "count",
    blocking: true,
    trades: ["roofing"],
    help: "How many rivets went in the ridge cap. A missed count held up payment on a finished job.",
  },
  {
    key: "magnet_sweep",
    label: "Magnet sweep",
    kind: "confirm",
    blocking: true,
    trades: null,
    help: "Confirm the ground was swept before leaving.",
  },
];

export function isQcKey(v: unknown): v is string {
  return typeof v === "string" && QC_REQUIREMENTS.some((r) => r.key === v);
}

export function requirementByKey(key: string): QcRequirement | undefined {
  return QC_REQUIREMENTS.find((r) => r.key === key);
}

/** Applies when the requirement names this trade, or names none. */
export function appliesToTrade(req: QcRequirement, trade: string | null): boolean {
  if (req.trades === null) return true;
  if (!trade) return false;
  const t = trade.toLowerCase();
  return req.trades.some((x) => t.includes(x));
}

/** One live qc_items row, as the app reads it. */
export type QcRow = {
  requirement_key: string;
  kind: string;
  photo_ref: string | null;
  count_value: number | null;
  occurred_at: string;
};

export type QcState =
  | "satisfied" //      recorded, and its evidence is still there
  | "photo_removed" //  recorded with a photo that has since been deleted
  | "outstanding" //    applies to this trade, nothing recorded
  | "not_required"; //  does not apply to this trade

export type QcLine = {
  requirement: QcRequirement;
  state: QcState;
  row: QcRow | null;
};

/**
 * One line per requirement — never a filtered list, because a filtered list is
 * how "not required" and "not done" end up looking the same.
 * `photoRefs` are the refs of the photos that exist on this job right now.
 */
export function qcLines(trade: string | null, rows: QcRow[], photoRefs: Set<string>): QcLine[] {
  return QC_REQUIREMENTS.map((requirement) => {
    const row = rows.find((r) => r.requirement_key === requirement.key) ?? null;
    if (!appliesToTrade(requirement, trade)) return { requirement, state: "not_required" as const, row };
    if (!row) return { requirement, state: "outstanding" as const, row: null };
    if (requirement.kind === "photo" && (!row.photo_ref || !photoRefs.has(row.photo_ref))) {
      return { requirement, state: "photo_removed" as const, row };
    }
    return { requirement, state: "satisfied" as const, row };
  });
}

export function outstandingBlocking(lines: QcLine[]): QcLine[] {
  return lines.filter((l) => l.requirement.blocking && (l.state === "outstanding" || l.state === "photo_removed"));
}

// ── What the screen says about each result. Codes on the URL, never text. ──────
export type QcResult =
  | "recorded"
  | "cleared"
  | "not_enabled"
  | "needs_check_in"
  | "photo_too_large"
  | "photo_failed"
  | "count_invalid"
  | "refused"
  | "unconfirmed";

export const QC_RESULT_COPY: Record<QcResult, { tone: "info" | "warn"; text: string }> = {
  recorded: { tone: "info", text: "Recorded." },
  cleared: { tone: "info", text: "Cleared — that check is outstanding again." },
  // 2026-09-21: was "The QC checklist isn't switched on for this workspace yet, so
  // nothing was recorded." Two faults: it told a crew member about a feature flag,
  // and the panel showed it when nothing had been TRIED, asserting an outcome for
  // an action that never happened. The panel no longer renders at all when the
  // checklist is off; this code now arises only when a save is attempted and the
  // checklist has gone away underneath it, and it says what to do.
  not_enabled: {
    tone: "warn",
    text: "That wasn't saved. Refresh the page and try again.",
  },
  needs_check_in: {
    tone: "warn",
    text: "Start today's check-in first — a QC photo is saved onto it.",
  },
  photo_too_large: { tone: "warn", text: "That photo was too large to save even after shrinking. Nothing was recorded." },
  photo_failed: { tone: "warn", text: "The photo didn't save, so the check wasn't recorded. Try again." },
  count_invalid: { tone: "warn", text: "Enter a whole number of 0 or more. Nothing was recorded." },
  refused: { tone: "warn", text: "That wasn't recorded — your role can't record it on this job." },
  unconfirmed: {
    tone: "warn",
    text: "We couldn't confirm that was recorded. Check the list below before recording it again.",
  },
};

export function isQcResult(v: unknown): v is QcResult {
  return typeof v === "string" && Object.prototype.hasOwnProperty.call(QC_RESULT_COPY, v);
}
