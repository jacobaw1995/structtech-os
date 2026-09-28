"use client";

import { useState } from "react";
import { photoRefNote, rowHasDetail, type ScopeTableRow } from "@/lib/crm/scope-sheet";

// SECTION 5 AT 375px. Track U, U-W1.39, 2026-09-28. Shape only — not wired.
//
// SIX ROWS x FIVE COLUMNS (item · found · where/notes · count · photo) IS NOT A
// TABLE ON A PHONE. Five columns in 375px leaves ~60px each after gutters; the
// "where/notes" column is prose and would wrap to four lines beside a checkbox.
// A person standing on a roof, one thumb, in sun, cannot use that, and the
// paper version they are replacing is a clipboard they can rest on a knee.
//
// SO THE TABLE IS SIX ROWS OF QUESTIONS, NOT THIRTY CELLS. On a real roof most
// of the grid is empty — you fill the cells for what you actually saw.
//
// CORRECTED AGAINST THE SOURCE PDF, which I read after writing the first
// version of this file and which contradicted it. I had assumed all six rows
// ask "found / none" first. THEY DO NOT. On the paper only TWO of the six carry
// that question — "Decking concerns" and "Leaks / problem areas" — and the
// other four have an EMPTY found cell: they are "write what you saw", three of
// them with the unit already printed (OSB sheets · roof vents · pipe boots) and
// one with the notes cell pre-labelled "Flashing notes". Rendering a yes/no on
// all six would have put a question on the roof that the paper never asked, and
// an inspector would have had to answer four of them for nothing.
//
// AND THE WORDS ARE THE SHEET'S, NOT MINE: "None seen", not "None". It does not
// claim there are none — only that none were seen from where the inspector
// stood. That distinction is one this build keeps everywhere else, and it was
// in Jacob's paper before any of us wrote it down.
//
// AGAINST THE GRADING SCALE: the current intake row costs 2 taps MINIMUM per
// field before typing (tap the row to open, then commit). Six rows here, all
// clear, costs SIX taps total rather than twelve, and answers 30 cells rather
// than 6. A row that IS found costs the extra fields only when they exist.
//
// NEVER DISABLED (§2.8): "None" does not lock the detail away. Answering None
// after filling detail KEEPS what was typed and says so — same rule as the
// gate, for the same reason: on a roof the commonest cause of a flip is a
// mis-tap, and the second is learning something new.
export function ScopeTable({ rows: initial }: { rows: ScopeTableRow[] }) {
  const [rows, setRows] = useState(initial);
  const set = (key: string, patch: Partial<ScopeTableRow>) =>
    setRows((rs) => rs.map((r) => (r.key === key ? { ...r, ...patch } : r)));

  const asking = rows.filter((r) => r.asksFound).length;
  const answered = rows.filter((r) => r.asksFound && r.found !== null).length;

  return (
    <div className="flex flex-col gap-3" data-scope-table>
      {/* Only the rows that ASK can be counted as answered — counting the other
          four would report progress nobody made. */}
      <p className="text-base text-text">
        {asking === 0
          ? `${rows.length} things to note.`
          : answered === asking
            ? `Both checks answered.`
            : `${answered} of ${asking} checks answered.`}
      </p>

      {rows.map((row) => {
        const keptButNotFound = row.asksFound && row.found === false && rowHasDetail(row);
        return (
          <div
            key={row.key}
            data-row={row.key}
            data-found={row.found === null ? "unanswered" : row.found ? "yes" : "no"}
            className="flex flex-col gap-2 rounded-xl border border-border p-3"
          >
            <p className="text-base font-semibold text-text">{row.item}</p>
            {row.hint && <p className="text-sm text-muted">{row.hint}</p>}

            {/* THE ONE QUESTION — on the two rows that ask it. Two 56px targets,
                side by side, thumb-width. */}
            {row.asksFound && (
              <div className="flex gap-2">
                <button
                  type="button"
                  aria-pressed={row.found === false}
                  onClick={() => set(row.key, { found: false })}
                  className={`min-h-14 flex-1 rounded-lg border text-base font-medium ${
                    row.found === false ? "border-accent-strong bg-accent-soft text-accent-strong" : "border-border text-text"
                  }`}
                >
                  None seen
                </button>
                <button
                  type="button"
                  aria-pressed={row.found === true}
                  onClick={() => set(row.key, { found: true })}
                  className={`min-h-14 flex-1 rounded-lg border text-base font-medium ${
                    row.found === true
                      ? "border-[var(--warn-strong)] bg-warn-soft text-text"
                      : "border-border text-text"
                  }`}
                >
                  Yes
                </button>
              </div>
            )}

            {/* The detail cells: after "Yes" on a row that asks, and ALWAYS on a
                row that does not — those four rows exist to be written in. */}
            {(row.found === true || !row.asksFound) && (
              <div className="flex flex-col gap-2">
                <label className="flex flex-col gap-1">
                  <span className="text-xs font-medium uppercase tracking-wide text-muted">
                    {row.whereLabel ?? "Where"}
                  </span>
                  <input
                    defaultValue={row.where ?? ""}
                    placeholder="North slope, by the chimney"
                    className="min-h-14 rounded-lg border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent"
                  />
                </label>
                <label className="flex flex-col gap-1">
                  <span className="text-xs font-medium uppercase tracking-wide text-muted">
                    {row.countUnit ?? "How many"}
                  </span>
                  <input
                    inputMode="numeric"
                    defaultValue={row.count ?? ""}
                    className="min-h-14 w-28 rounded-lg border border-border bg-bg px-3 text-base tabular-nums text-text outline-none focus:border-accent"
                  />
                </label>

                {/* (d) THE FIFTH COLUMN — a CompanyCam id we cannot resolve.
                    R4: a reference not verified against the thing it references
                    is a name, and a name is not a control. So it is a NOTE.
                    NO thumbnail, no "photo attached", no camera icon, no tick,
                    no count — every one of those is a claim this reference
                    cannot support, read by somebody on a roof deciding whether
                    they still need to take the picture. Compare the QC photo
                    ref, which the database RESOLVES against a photo on this
                    work order and refuses when it does not match; nothing of
                    the sort is possible here, because we cannot ask
                    CompanyCam. */}
                <label className="flex flex-col gap-1">
                  <span className="text-xs font-medium uppercase tracking-wide text-muted">
                    CompanyCam ref
                  </span>
                  <input
                    defaultValue={row.photoRef ?? ""}
                    placeholder="If you noted one"
                    className="min-h-14 rounded-lg border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent"
                  />
                  <span data-photo-ref={photoRefNote(row.photoRef).kind} className="text-xs text-muted">
                    {photoRefNote(row.photoRef).kind === "recorded"
                      ? "Written down here. Nothing checks that the photo exists."
                      : "Nothing written down here."}
                  </span>
                </label>
              </div>
            )}

            {/* §2.8 — answering None never destroys what was already recorded. */}
            {keptButNotFound && (
              <p className="rounded-md bg-warn-soft px-3 py-2 text-sm text-text">
                Marked as none seen, but what was already written down is kept — tap Yes if that was a
                mis-tap.
              </p>
            )}
          </div>
        );
      })}
    </div>
  );
}
