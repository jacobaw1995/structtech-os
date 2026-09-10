import {
  formatDate,
  formatMoney,
  isStructTechOwner,
  ownerLabel,
  parseLevels,
  progressOf,
  riskTone,
  type Level,
  type Milestone,
  type RoadmapRow,
  type Tone,
} from "@/lib/roadmap/model";

/**
 * The public client roadmap. A contractor opens this from a link, on a
 * phone, with no login and no surrounding context — so it is built as a
 * document, not as a view of a table: masthead, the diagnosis that justifies
 * the plan, then the plan itself with each commitment attributed to the side
 * that owns it.
 *
 * Deliberately a pure server component with no client JS. There is nothing
 * to interact with — the milestone state is StructTech's to change, not the
 * reader's — and a public page that renders as static HTML is the fastest
 * and least breakable thing to hand someone on site data.
 *
 * Every affordance here is inert on purpose: there are no checkboxes the
 * reader could tick that would not save, and nothing labelled as an action
 * that is not one.
 */

// --warn-strong is derived from --warn by exactly the rule that produces
// --accent-strong from --accent (same chroma and hue, lightness 0.55 → 0.42).
// It exists because --warn on --warn-soft measures ~3.3:1, which fails AA for
// the small text in the risk chip; at 0.42 it is ~5.3:1. Scoped to this
// surface rather than added to :root so a public page cannot shift the
// palette the rest of the app is built on.
const SURFACE_VARS = { "--warn-strong": "oklch(0.42 0.15 45)" } as React.CSSProperties;

const TONE_CHIP: Record<Tone, string> = {
  critical: "border-warn bg-warn-soft text-[var(--warn-strong)]",
  high: "border-warn bg-warn-soft text-[var(--warn-strong)]",
  moderate: "border-border bg-surface2 text-text",
  good: "border-accent bg-accent-soft text-accent-strong",
  neutral: "border-border bg-surface2 text-muted",
};

const TONE_METER: Record<Tone, string> = {
  critical: "bg-warn",
  high: "bg-warn",
  moderate: "bg-muted",
  good: "bg-accent",
  neutral: "bg-muted",
};

function Stat({
  label,
  children,
  note,
}: {
  label: string;
  children: React.ReactNode;
  note?: string | null;
}) {
  return (
    <div className="flex-1 border-b border-border px-5 py-4 last:border-b-0 sm:border-b-0 sm:border-r sm:last:border-r-0">
      <div className="text-[11px] font-semibold uppercase tracking-[0.08em] text-muted">
        {label}
      </div>
      <div className="mt-2">{children}</div>
      {note ? <div className="mt-1.5 text-xs text-muted">{note}</div> : null}
    </div>
  );
}

function MilestoneRow({
  milestone,
  clientLabel,
  isLast,
}: {
  milestone: Milestone;
  clientLabel: string;
  isLast: boolean;
}) {
  const owner = ownerLabel(milestone.owner, clientLabel);
  const byStructTech = isStructTechOwner(milestone.owner);
  const doneOn = formatDate(milestone.doneAt);

  return (
    <li className="relative flex gap-3 pl-0">
      {/* Marker column doubles as the timeline rail. A done milestone is
          marked, never struck through — the reader should still be able to
          read what was accomplished.

          A not-yet-done step is a small SOLID dot, not an empty ring. An
          empty ring beside a ticked one reads as an unchecked checkbox, and
          nothing on this page is tickable: the milestone state is
          StructTech's to change, not the reader's. Rendering an inert
          control that invites a tap is the visual form of labelling
          something with an intent the code does not implement. */}
      <div className="relative flex w-5 shrink-0 justify-center">
        {!isLast && (
          <span
            aria-hidden="true"
            className="absolute left-1/2 top-2 bottom-0 w-px -translate-x-1/2 bg-border"
          />
        )}
        {milestone.done ? (
          <span className="relative mt-0.5 flex h-5 w-5 items-center justify-center rounded-full bg-accent-strong text-[11px] leading-none text-white">
            ✓<span className="sr-only">Complete</span>
          </span>
        ) : (
          <span className="relative mt-[7px] flex h-1.5 w-1.5 items-center justify-center rounded-full bg-border">
            <span className="sr-only">Not started</span>
          </span>
        )}
      </div>

      <div className="min-w-0 flex-1 pb-6">
        <div className="mb-1.5 flex flex-wrap items-center gap-x-2 gap-y-1">
          {owner ? (
            <span
              className={`rounded-full border px-2 py-0.5 text-[11px] font-medium ${
                byStructTech
                  ? "border-accent bg-accent-soft text-accent-strong"
                  : "border-border bg-surface2 text-muted"
              }`}
            >
              {owner}
            </span>
          ) : null}
          {milestone.isWin ? (
            <span className="rounded-full border border-warn bg-warn-soft px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wide text-[var(--warn-strong)]">
              The win
            </span>
          ) : null}
          {doneOn ? (
            <span className="font-mono text-[11px] text-muted">
              Done {doneOn}
            </span>
          ) : null}
        </div>

        {milestone.label ? (
          <p
            className={`text-[15px] leading-relaxed ${
              milestone.done ? "text-muted" : "text-text"
            }`}
          >
            {milestone.label}
          </p>
        ) : (
          // The milestone exists; its text does not. Say that, rather than
          // rendering an empty row that reads like a layout bug.
          <p className="text-[15px] italic leading-relaxed text-muted">
            This step has no description yet.
          </p>
        )}
      </div>
    </li>
  );
}

function LevelCard({
  level,
  index,
  clientLabel,
}: {
  level: Level;
  index: number;
  clientLabel: string;
}) {
  const number = String(index + 1).padStart(2, "0");
  const done = level.milestones.filter((m) => m.done).length;

  return (
    <article className="overflow-hidden rounded-lg border border-border bg-surface">
      <div className="border-b border-border bg-surface2 px-5 py-4">
        <div className="flex items-baseline gap-2">
          <span className="font-mono text-xs font-semibold tracking-widest text-accent-strong">
            {number}
          </span>
          <span className="text-[11px] font-semibold uppercase tracking-[0.08em] text-muted">
            {level.milestones.length > 0
              ? `${done} of ${level.milestones.length} complete`
              : "No steps yet"}
          </span>
        </div>
        {level.title ? (
          <h2 className="mt-1.5 font-serif text-xl font-semibold leading-snug text-text">
            {level.title}
          </h2>
        ) : (
          <h2 className="mt-1.5 font-serif text-xl font-semibold leading-snug text-muted">
            Untitled level
          </h2>
        )}
      </div>

      {level.why ? (
        <div className="border-b border-border px-5 py-4">
          <div className="mb-1.5 text-[11px] font-semibold uppercase tracking-[0.08em] text-muted">
            Why this matters
          </div>
          <p className="whitespace-pre-line text-[15px] leading-relaxed text-text">
            {level.why}
          </p>
        </div>
      ) : null}

      <div className="px-5 pt-5">
        {level.milestones.length > 0 ? (
          <ol className="list-none">
            {level.milestones.map((m, i) => (
              <MilestoneRow
                key={m.key}
                milestone={m}
                clientLabel={clientLabel}
                isLast={i === level.milestones.length - 1}
              />
            ))}
          </ol>
        ) : (
          <p className="pb-5 text-[15px] text-muted">
            The steps for this level have not been written yet.
          </p>
        )}
      </div>
    </article>
  );
}

export function RoadmapView({ roadmap }: { roadmap: RoadmapRow }) {
  const levels = parseLevels(roadmap.levels);
  const progress = progressOf(levels);

  const company = roadmap.company?.trim() || null;
  const clientName = roadmap.client_name?.trim() || null;
  const trade = roadmap.trade?.trim() || null;
  const risk = roadmap.risk_level?.trim() || null;
  const tone = riskTone(risk);

  // The company is the headline where there is one; otherwise the person.
  // Never a placeholder — an empty company is a fact about the record, not
  // something to paper over with "Unknown".
  const heading = company ?? clientName ?? "Operations Roadmap";
  // Named once, in the sentence that introduces the plan…
  const clientLabel = company ?? clientName ?? "your team";
  // …and addressed as "You" on every line after that. The chip repeats on
  // most milestones, and a long company name repeated a dozen times crowds
  // out the step it is labelling.
  const ownerChipLabel = "You";

  const subline = [
    company && clientName ? clientName : null,
    trade,
    Number.isFinite(roadmap.crew_size) ? `Crew of ${roadmap.crew_size}` : null,
  ].filter((v): v is string => v !== null);

  // formatMoney(null) returns the string "—", which is TRUTHY. Testing the
  // formatted string meant `leak ? … : "Not estimated"` always took the first
  // branch, so an unestimated roadmap rendered "—/mo" with a note reading
  // "$0 a year if nothing changes" — `null * 12` is 0, not null. The
  // "Not estimated" branch below had never once run. Test the NUMBER.
  const leakMonthly =
    typeof roadmap.revenue_leak_monthly === "number" &&
    Number.isFinite(roadmap.revenue_leak_monthly)
      ? roadmap.revenue_leak_monthly
      : null;
  const leak = leakMonthly === null ? null : formatMoney(leakMonthly);
  const leakAnnual = leakMonthly === null ? null : formatMoney(leakMonthly * 12);
  const score = Number.isFinite(roadmap.score) ? roadmap.score : null;
  const scorePct = score === null ? 0 : Math.max(0, Math.min(100, score));
  const updated = formatDate(roadmap.updated_at);
  const isArchived = roadmap.status?.trim().toLowerCase() === "archived";

  return (
    /* data-branch="ok" — the fourth value of the contract the front-door
       monitor asserts. The three failure branches stamp theirs in
       app/roadmap/[token]/page.tsx; this is the success one, and it lives here
       because this component IS the ok branch's wrapper. See that file for why
       the monitor asserts structure rather than a sentence. */
    <div data-branch="ok" style={SURFACE_VARS} className="min-h-dvh bg-bg">
      <div className="mx-auto w-full max-w-2xl px-4 py-8 sm:px-6 sm:py-14">
        {isArchived ? (
          <div className="mb-6 rounded-lg border border-warn bg-warn-soft px-4 py-3 text-sm text-[var(--warn-strong)]">
            <span className="font-semibold">This roadmap is archived.</span>{" "}
            It is kept here for reference and may not reflect the current plan.
          </div>
        ) : null}

        <header className="mb-8">
          <div className="mb-6 flex items-center gap-2">
            <span className="flex h-6 w-6 items-center justify-center rounded bg-accent-strong font-mono text-xs font-bold text-white">
              S
            </span>
            <span className="text-sm font-semibold tracking-tight text-text">
              StructTech
            </span>
          </div>

          <div className="text-[11px] font-semibold uppercase tracking-[0.1em] text-accent-strong">
            Operations Roadmap
          </div>
          <h1 className="mt-2 font-serif text-3xl font-semibold leading-tight tracking-tight text-text sm:text-4xl">
            {heading}
          </h1>
          {subline.length > 0 ? (
            <p className="mt-2 text-sm text-muted">{subline.join(" · ")}</p>
          ) : null}
        </header>

        {/* The diagnosis. This is the argument for the plan below it, so it
            comes before the plan and is the heaviest thing on the page. */}
        <section
          aria-label="Assessment"
          className="mb-8 overflow-hidden rounded-lg border border-border bg-surface sm:flex"
        >
          <Stat label="Operations score">
            <div className="flex items-baseline gap-1">
              <span className="font-mono text-3xl font-semibold leading-none tracking-[-0.03em] text-text">
                {score ?? "—"}
              </span>
              <span className="font-mono text-sm text-muted">/100</span>
            </div>
            <div
              className="mt-3 h-1.5 w-full overflow-hidden rounded-full bg-surface2"
              role="img"
              aria-label={`Operations score ${score ?? "unknown"} out of 100`}
            >
              <div
                className={`h-full rounded-full ${TONE_METER[tone]}`}
                style={{ width: `${scorePct}%` }}
              />
            </div>
          </Stat>

          <Stat label="Risk level">
            {risk ? (
              <span
                className={`inline-block rounded-full border px-2.5 py-1 text-sm font-semibold ${TONE_CHIP[tone]}`}
              >
                {risk}
              </span>
            ) : (
              <span className="text-sm text-muted">Not assessed</span>
            )}
          </Stat>

          <Stat
            label="Revenue leak"
            note={
              leakAnnual
                ? `${leakAnnual} a year if nothing changes`
                : null
            }
          >
            {leak ? (
              /* MONEY IS SANS — controller decision 1.1, 2026-09-03, which
                 overrides the "mono for money" line in CLAUDE.md's design
                 system. IBM Plex Mono gives the thousands comma a full
                 monospace advance, so at 3xl "$3,100" rendered as "$3 , 100"
                 and read as a typo in the client's own number. tabular-nums
                 keeps the digits column-aligned, which is the only property
                 mono was actually being used for here. Mono stays for IDs,
                 tokens, dates, counts and versions — the score beside this
                 is a count and keeps it. */
              <div className="flex items-baseline gap-1">
                <span className="text-3xl font-semibold leading-none tracking-[-0.02em] tabular-nums text-[var(--warn-strong)]">
                  {leak}
                </span>
                <span className="text-sm text-muted">/mo</span>
              </div>
            ) : (
              <span className="text-sm text-muted">Not estimated</span>
            )}
          </Stat>
        </section>

        <section aria-label="Progress" className="mb-8">
          <div className="mb-2 flex items-baseline justify-between gap-3">
            <h2 className="text-[11px] font-semibold uppercase tracking-[0.08em] text-muted">
              Progress
            </h2>
            <span className="font-mono text-xs text-muted">
              {progress.total === 0
                ? "No steps yet"
                : progress.done === 0
                  ? `Not started · ${progress.total} steps`
                  : `${progress.done} of ${progress.total} complete`}
            </span>
          </div>
          <div
            className="h-2 w-full overflow-hidden rounded-full bg-surface2"
            role="img"
            aria-label={`${progress.done} of ${progress.total} milestones complete`}
          >
            <div
              className="h-full rounded-full bg-accent-strong"
              style={{
                width:
                  progress.total === 0
                    ? "0%"
                    : `${(progress.done / progress.total) * 100}%`,
              }}
            />
          </div>
        </section>

        <section aria-label="The plan">
          <h2 className="mb-1 font-serif text-2xl font-semibold tracking-tight text-text">
            The plan
          </h2>
          <p className="mb-5 text-sm leading-relaxed text-muted">
            {levels.length > 0
              ? `${levels.length} ${levels.length === 1 ? "level" : "levels"}, in order. Every step is owned either by StructTech or by ${clientLabel} — the owner is named on each line.`
              : "The levels for this roadmap have not been written yet."}
          </p>

          {levels.length > 0 ? (
            <div className="flex flex-col gap-5">
              {levels.map((level, i) => (
                <LevelCard
                  key={level.key}
                  level={level}
                  index={i}
                  clientLabel={ownerChipLabel}
                />
              ))}
            </div>
          ) : null}
        </section>

        <footer className="mt-10 border-t border-border pt-5 text-xs leading-relaxed text-muted">
          <p>
            Prepared by StructTech
            {updated ? <> · Last updated {updated}</> : null}
          </p>
          <p className="mt-1">
            This link is private. Anyone who has it can read this roadmap.
          </p>
        </footer>
      </div>
    </div>
  );
}
