/**
 * Client roadmap — the content model for the public viewer at
 * /roadmap/[token].
 *
 * Everything here is shaped by what `fetch_roadmap_by_token(text)` actually
 * returns (12 columns; deliberately NOT token, lead_id or org_id) and by what
 * the nine live `client_roadmaps` rows actually contain. The `levels` column
 * is untyped `jsonb`, so it is parsed defensively rather than cast: measured
 * across all 9 rows / 27 levels / 119 milestones on 2026-09-02 —
 *
 *   · levels is an array of 3 on every row; 3, 5 or 6 milestones per level
 *   · level keys: title, why, milestones, and `area` on only 22 of 27
 *   · milestone keys: id, label, owner, done, done_at, and `win` on 3 of 119
 *   · owner is 'jacob' or 'client' today — treated as open, not as an enum
 *   · `why` carries a literal "Why:" prefix on 3 of 27 (one roadmap)
 *   · risk_level is free text: HIGH, CRITICAL, HIGH RISK, MODERATE, OPTIMIZED
 *   · company and trade are empty strings on one row
 *
 * None of those shapes is guaranteed by a constraint, so none of them is
 * assumed. A level with no milestones, a milestone with no label, an
 * unrecognised owner and an unrecognised risk level all have to render.
 */

export type RoadmapRow = {
  id: string;
  client_name: string;
  company: string;
  trade: string;
  crew_size: number;
  score: number;
  risk_level: string;
  revenue_leak_monthly: number;
  levels: unknown;
  status: string;
  created_at: string;
  updated_at: string;
};

export type Milestone = {
  key: string;
  label: string | null;
  owner: string | null;
  done: boolean;
  doneAt: string | null;
  isWin: boolean;
};

export type Level = {
  key: string;
  title: string | null;
  why: string | null;
  milestones: Milestone[];
};

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

/** A trimmed string, or null. Empty string is data, not a value to print. */
function str(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const t = v.trim();
  return t.length > 0 ? t : null;
}

function bool(v: unknown): boolean {
  return v === true;
}

/**
 * One roadmap carries "Why:\n…" inside the prose itself. The section is
 * already labelled on the page, so the prefix would read as a stutter.
 * Stripped for display only — the stored value is never touched.
 */
function stripWhyPrefix(v: string | null): string | null {
  if (v === null) return null;
  const stripped = v.replace(/^\s*why\s*:\s*/i, "").trim();
    return stripped.length > 0 ? stripped : null;
}

export function parseLevels(raw: unknown): Level[] {
  if (!Array.isArray(raw)) return [];

  return raw.flatMap((entry, levelIndex) => {
    if (!isRecord(entry)) return [];

    const rawMilestones = entry.milestones;
    const milestones: Milestone[] = Array.isArray(rawMilestones)
      ? rawMilestones.flatMap((m, msIndex) => {
          if (!isRecord(m)) return [];
          // Milestone ids are unique within a level on every live row, but
          // not proven unique across levels — so the level index is part of
          // the key, and the position is the fallback when id is missing.
          const id = str(m.id);
          return [
            {
              key: `l${levelIndex}-${id ?? `m${msIndex}`}`,
              label: str(m.label),
              owner: str(m.owner),
              done: bool(m.done),
              doneAt: str(m.done_at),
              isWin: bool(m.win),
            },
          ];
        })
      : [];

    return [
      {
        key: `level-${levelIndex}`,
        title: str(entry.title),
        why: stripWhyPrefix(str(entry.why)),
        milestones,
      },
    ];
  });
}

export type Progress = { done: number; total: number };

export function progressOf(levels: Level[]): Progress {
  const all = levels.flatMap((l) => l.milestones);
  return { done: all.filter((m) => m.done).length, total: all.length };
}

/**
 * Who owns a milestone, in the client's language. The stored values are
 * 'jacob' and 'client'; the roadmap copy itself already speaks about
 * "StructTech" in the third person, so that is the label the reader sees.
 *
 * An owner this function does not recognise is shown as written rather than
 * dropped or relabelled — a value we cannot interpret is still a value the
 * reader is entitled to see.
 */
export function ownerLabel(owner: string | null, clientLabel: string): string | null {
  if (owner === null) return null;
  const key = owner.toLowerCase();
  if (key === "jacob" || key === "structtech") return "StructTech";
  if (key === "client") return clientLabel;
  return owner;
}

export function isStructTechOwner(owner: string | null): boolean {
  if (owner === null) return false;
  const key = owner.toLowerCase();
  return key === "jacob" || key === "structtech";
}

export type Tone = "critical" | "high" | "moderate" | "good" | "neutral";

/**
 * `risk_level` is free text with no CHECK constraint behind it — five
 * distinct spellings across nine rows. Matched by substring so that
 * "HIGH" and "HIGH RISK" land in the same place, and anything unrecognised
 * renders neutral rather than being forced into a bucket.
 */
export function riskTone(risk: string | null): Tone {
  if (risk === null) return "neutral";
  const r = risk.toUpperCase();
  if (r.includes("CRITICAL") || r.includes("SEVERE")) return "critical";
  if (r.includes("HIGH")) return "high";
  if (r.includes("MODERATE") || r.includes("MEDIUM")) return "moderate";
  if (r.includes("OPTIMIZED") || r.includes("LOW") || r.includes("HEALTHY")) return "good";
  return "neutral";
}

export function formatMoney(n: number | null): string | null {
  if (n === null || !Number.isFinite(n)) return null;
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 0,
  }).format(n);
}

/**
 * This project runs on America/New_York (CLAUDE.md). Rendering a timestamp in
 * the server's zone would show the wrong calendar day for anything stamped
 * after 8 PM Eastern — the same rollover that has already mis-dated this
 * build's own records twice.
 */
export function formatDate(iso: string | null): string | null {
  if (iso === null) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  return new Intl.DateTimeFormat("en-US", {
    month: "long",
    day: "numeric",
    year: "numeric",
    timeZone: "America/New_York",
  }).format(d);
}
