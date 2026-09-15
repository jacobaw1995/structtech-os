import Link from "next/link";
import type { HomeData } from "@/lib/home/load";
import type { AttentionItem, Section } from "@/lib/home/model";

// Presentational only — no data access, so a fixture can render it against
// measured payloads. The data and every gate live in lib/home/load.ts.

const SHOWN_PER_SECTION = 5;

// Dates go in mono and never break across a line. Measured at 375px: the
// first render wrapped "2026-10-05" at its hyphen, which reads as two numbers.
const DATE = /(\d{4}-\d{2}-\d{2})/;
function WithDates({ text }: { text: string }) {
  return (
    <>
      {text.split(DATE).map((part, i) =>
        i % 2 === 1 ? (
          <span key={i} className="whitespace-nowrap font-mono tabular-nums">
            {part}
          </span>
        ) : (
          part
        )
      )}
    </>
  );
}

export function HomeSummary({ data }: { data: HomeData }) {
  const needsYou = data.sections.reduce((n, s) => n + s.items.filter((i) => i.needsYou).length, 0);
  const unreadable = data.sections.filter((s) => s.state === "unavailable");
  const entered = data.sections.filter((s) => s.state !== "none_entered" && s.state !== "unavailable");

  // FOUR HEADLINES, NEVER MERGED. "Nothing needs you" is only said when every
  // section was READ, and at least one of them has something on record.
  let headline: string;
  let detail: string | null = null;
  if (needsYou > 0) {
    headline = `${needsYou} ${needsYou === 1 ? "thing needs" : "things need"} you`;
  } else if (unreadable.length > 0) {
    headline = "Some of this could not be read";
    detail = "Nothing below needs you, but that is not a clean bill — part of the page did not load.";
  } else if (data.sections.length === 0) {
    headline = "Nothing here for your role";
    detail = "None of the areas this workspace has are ones your role can see.";
  } else if (entered.length === 0) {
    headline = "Nothing has been entered yet";
    detail = "There is nothing on record in any area below, so there is nothing to need you.";
  } else {
    headline = "Nothing needs you right now";
    detail = "Everything on record below was checked.";
  }

  return (
    <div data-home-headline={needsYou > 0 ? "needs-you" : unreadable.length > 0 ? "unavailable" : entered.length === 0 ? "none-entered" : "clear"}>
      <p className="text-lg font-semibold text-text">{headline}</p>
      {unreadable.length > 0 && needsYou > 0 && (
        <p className="mt-1 text-sm text-[var(--warn-strong)]">
          {unreadable.length === 1 ? "One area" : `${unreadable.length} areas`} could not be read, so this may not be everything.
        </p>
      )}
      {detail && <p className="mt-1 text-sm text-muted">{detail}</p>}
    </div>
  );
}

export function HomeSectionCard({ section }: { section: Section }) {
  const needs = section.items.filter((i) => i.needsYou);
  const fyi = section.items.filter((i) => !i.needsYou);
  const ordered = [...needs, ...fyi];
  const shown = ordered.slice(0, SHOWN_PER_SECTION);
  const more = ordered.length - shown.length;

  return (
    <section
      data-home-section={section.id}
      data-state={section.state}
      className="rounded-lg border border-border bg-surface"
    >
      <header className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1 border-b border-border px-4 py-3">
        <h2 className="text-base font-semibold text-text">{section.title}</h2>
        {section.onRecord !== null && section.onRecord > 0 && (
          <span className="text-xs tabular-nums text-muted">{section.onRecordLabel} on record</span>
        )}
      </header>

      <div className="px-4 py-3">
        <StateLine section={section} needs={needs.length} />

        {shown.length > 0 && (
          <ul className="mt-2 flex flex-col">
            {shown.map((item) => (
              <ItemRow key={item.key} item={item} />
            ))}
          </ul>
        )}
        {more > 0 && (
          <p className="mt-2 text-sm text-muted">
            and <span className="font-mono tabular-nums">{more}</span> more
          </p>
        )}

        {section.notes.length > 0 && (
          <ul className="mt-3 flex flex-col gap-1 border-t border-border pt-3">
            {section.notes.map((n) => (
              <li key={n} className="text-xs tabular-nums text-muted">
                <WithDates text={n} />
              </li>
            ))}
          </ul>
        )}
      </div>
    </section>
  );
}

function StateLine({ section, needs }: { section: Section; needs: number }) {
  switch (section.state) {
    case "unavailable":
      return (
        <p className="text-sm text-[var(--warn-strong)]">
          Could not be read. This is not the same as there being nothing here.
        </p>
      );
    case "none_entered":
      return <p className="text-sm text-muted">Nothing entered yet.</p>;
    case "clear":
      return (
        <p className="text-sm text-text">
          Nothing needs you — <span className="tabular-nums">{section.onRecordLabel}</span> on record, checked.
        </p>
      );
    case "attention":
      return needs > 0 ? (
        <p className="text-sm font-medium text-text">
          <span className="font-mono tabular-nums">{needs}</span> {needs === 1 ? "needs" : "need"} you
        </p>
      ) : (
        <p className="text-sm text-text">Nothing needs you. For your information:</p>
      );
  }
}

function ItemRow({ item }: { item: AttentionItem }) {
  const body = (
    <>
      <span
        className={`mt-1.5 h-2 w-2 shrink-0 rounded-full ${item.needsYou ? "bg-warn" : "bg-border"}`}
        aria-hidden="true"
      />
      <span className={`min-w-0 flex-1 text-sm ${item.needsYou ? "text-text" : "text-muted"}`}>
        {item.needsYou && <span className="sr-only">Needs you: </span>}
        <WithDates text={item.text} />
      </span>
      {item.href && (
        <span aria-hidden="true" className="text-muted">
          ›
        </span>
      )}
    </>
  );

  return (
    <li className="border-b border-border last:border-0" data-needs-you={item.needsYou ? "true" : "false"}>
      {item.href ? (
        <Link href={item.href} className="flex min-h-14 items-start gap-3 py-3 sm:min-h-0">
          {body}
        </Link>
      ) : (
        <div className="flex min-h-14 items-start gap-3 py-3 sm:min-h-0">{body}</div>
      )}
    </li>
  );
}

export function HiddenSections({ hidden }: { hidden: HomeData["hidden"] }) {
  if (hidden.length === 0) return null;
  const names: Record<string, string> = { estimates: "Estimates", pipeline: "Pipeline" };
  return (
    <p data-home-hidden className="text-xs text-muted">
      {hidden.map((h) => `${names[h.id] ?? h.id} is not shown — ${h.because}.`).join(" ")}
    </p>
  );
}
