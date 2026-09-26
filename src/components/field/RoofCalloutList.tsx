import {
  orderedCallouts,
  placesNotSpecified,
  roofPlaceLabel,
  type RoofCalloutRead,
} from "@/lib/field/roof-callouts";

// WHAT GOES WHERE, IN ONE LIST. Track U, U-W1.35, 2026-09-25.
//
// NOT MOUNTED ON ANY SCREEN YET — the structured data does not exist (see
// lib/field/roof-callouts.ts). A list that looks like it describes this roof
// and is actually empty is worse than no list, because a crew would read the
// silence as "nothing unusual here".
//
// NO MAP, NO CANVAS, NO IMAGE. November.
//
// THREE SENTENCES, NEVER ONE:
//   · unreadable          "we could not read it"        — says nothing about the roof
//   · read, and empty     "nothing recorded yet"        — a fact about the record
//   · read, with places   the list, plus what is not specified
// The third is the QC lesson applied here: a place nobody specified is a STATE
// ("not specified for this roof"), not an absence, and it is said in one line
// at the foot rather than as fourteen empty rows that would bury the three that
// matter.
export function RoofCalloutList({ read }: { read: RoofCalloutRead }) {
  if (read.state === "unreadable") {
    return (
      <section className="flex flex-col gap-2 rounded-lg border border-border p-3 group-data-[outdoor=true]/field:border-white/30">
        <p className="text-sm font-semibold uppercase tracking-wide text-muted group-data-[outdoor=true]/field:text-white/80">
          What goes where
        </p>
        <p role="alert" data-callouts="unreadable" className="rounded-md bg-warn-soft px-3 py-2 text-sm text-text">
          This roof&apos;s details couldn&apos;t be read just now. That doesn&apos;t mean there is nothing
          unusual about it — pull down to reload, and ask the office before you start anything you are not
          sure about.
        </p>
      </section>
    );
  }

  const callouts = orderedCallouts(read.callouts);
  const notSpecified = placesNotSpecified(read.callouts);
  const different = callouts.filter((c) => c.unusual).length;

  return (
    <section
      data-callouts="ok"
      className="flex flex-col gap-3 rounded-lg border border-border p-3 group-data-[outdoor=true]/field:border-white/30"
    >
      <p className="text-sm font-semibold uppercase tracking-wide text-muted group-data-[outdoor=true]/field:text-white/80">
        What goes where
      </p>

      {callouts.length === 0 ? (
        <p data-callouts-empty className="text-sm text-text group-data-[outdoor=true]/field:text-white">
          Nothing has been recorded for this roof yet. Ask the office what goes where before you start.
        </p>
      ) : (
        <>
          {/* The count first: on a phone, "is anything odd here?" should not
              require scrolling the list. */}
          <p className="text-base text-text group-data-[outdoor=true]/field:text-white">
            {different === 0
              ? `${callouts.length} thing${callouts.length === 1 ? "" : "s"} recorded for this roof.`
              : `${different} thing${different === 1 ? " is" : "s are"} different on this roof.`}
          </p>

          <ul className="flex flex-col gap-2">
            {callouts.map((c) => (
              <li
                key={c.id}
                data-place={c.place ?? "none"}
                data-unusual={c.unusual ? "true" : "false"}
                className={`flex flex-col gap-0.5 rounded-lg border p-3 ${
                  c.unusual
                    ? "border-[var(--warn-strong)] group-data-[outdoor=true]/field:border-white"
                    : "border-border group-data-[outdoor=true]/field:border-white/40"
                }`}
              >
                <div className="flex flex-wrap items-baseline justify-between gap-x-3">
                  <span className="text-base font-semibold text-text group-data-[outdoor=true]/field:text-white">
                    {roofPlaceLabel(c.place) ?? "No place recorded"}
                  </span>
                  {c.unusual && (
                    <span className="text-sm font-medium text-[var(--warn-strong)] group-data-[outdoor=true]/field:text-white">
                      Different here
                    </span>
                  )}
                </div>
                <span className="text-base text-text group-data-[outdoor=true]/field:text-white">{c.what}</span>
                {c.note && (
                  <span className="text-sm leading-relaxed text-muted group-data-[outdoor=true]/field:text-white/80">
                    {c.note}
                  </span>
                )}
              </li>
            ))}
          </ul>

          {notSpecified.length > 0 && (
            <p className="text-sm text-muted group-data-[outdoor=true]/field:text-white/80">
              Not specified for this roof: {notSpecified.map((p) => p.label).join(", ")}. Ask the office if you
              need one of them.
            </p>
          )}
        </>
      )}
    </section>
  );
}
