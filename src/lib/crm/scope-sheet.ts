// THE JOB SCOPE SHEET — the four field types that do not exist yet, and the
// four states a section can be in. Track U, U-W1.39, 2026-09-28.
// Client-safe: no server imports.
//
// DESIGNED, NOT WIRED. S's config numbers land tonight; nothing here is mounted
// on a screen, and the shapes below are the surface's proposal against the
// acceptance: JACOB FILLS THIS ON A PHONE, STANDING UP, FOR A REAL ROOF, AND IT
// IS FASTER AND CLEARER THAN THE PAPER.
//
// THE GRADING SCALE, re-measured today and unchanged since 2026-09-27:
//   38 fields defined in tenant config, 6 stages, 11 vital on New Lead
//   2 taps MINIMUM per field (the row is a closed button; tap opens the editor)
//   11 fields  ->  22+ taps and 11 server round trips for one screen
//   FOUR commit behaviours: blur-or-Enter (single inputs) · blur only
//   (textarea) · onChange, instantly (select) · form-level blur with NO Enter
//   handler (the 4-input address block)
// Anything below that costs MORE taps than the sheet it replaces has failed,
// however good it looks.

// ── (a) GATE ────────────────────────────────────────────────────────────────
// 2–4 mutually exclusive options that REVEAL or HIDE a whole section.
//
// SCOPE §2.8, and it is the whole design: A GATE REVEALS AND HIDES. IT NEVER
// DISABLES AND NEVER REFUSES A SAVE. Answering "No siding on this job" after
// siding lines are already filled KEEPS the lines and MARKS them. It does not
// delete them, and it does not stop the save.
//
// WHY KEPT-AND-MARKED RATHER THAN DELETED, stated because the cheap version is
// tempting: on a roof, the commonest reason a gate flips is that the person
// tapped the wrong one, and the second commonest is that they learned something
// new halfway through. Deleting on flip means the first mistake costs the work
// and the second costs it twice. Marking costs a sentence on screen.
export type GateOption = {
  code: string;
  label: string;
  /**
   * WHICH GROUPS THIS ANSWER OPENS — not a boolean.
   *
   * CORRECTED AGAINST THE SOURCE PDF (read 2026-09-28, page 2–3). A boolean was
   * wrong for half the gates on the sheet: 3B offers "Soffit and fascia ·
   * Soffit only · Fascia only · No", and the sheet's own instruction is
   * "Soffit only -> skip the fascia lines. Fascia only -> skip the soffit
   * lines." So a four-option gate reveals DIFFERENT SUBSETS of its section, and
   * an all-or-nothing model cannot express it. 3D is the same shape
   * ("Gutters and gutter guards · Gutters only · Gutter guards only · No"),
   * with its own warning printed on the sheet: "Guards are not included just
   * because gutters are."
   *
   * An empty list is the "No — not on this job" answer.
   */
  reveals: string[];
};

export type GateAnswer = {
  /** null = nobody has answered yet. NOT the same as any answer. */
  code: string | null;
};

/**
 * What a section's content is, given the gate. The third case is the one the
 * §2.8 rule exists for and the only one that needs words on screen.
 */
export type GatedContent = "open" | "closed_and_empty" | "closed_but_filled";

export function gatedContent(
  gate: GateAnswer,
  options: GateOption[],
  filledCount: number
): GatedContent {
  const chosen = options.find((o) => o.code === gate.code);
  // Unanswered reads as OPEN: a sheet that hides its own questions until you
  // answer a question you have not been shown is a sheet you cannot fill.
  if (!gate.code || !chosen || chosen.reveals.length > 0) return "open";
  return filledCount > 0 ? "closed_but_filled" : "closed_and_empty";
}

// ── (b) TYPE-CODE PICKER ────────────────────────────────────────────────────
// The sheet stores the CODE; the screen shows the WORDS. Nobody types a code
// and nobody reads one.
export type TypeCode = { code: string; label: string };

export function typeCodeLabel(codes: TypeCode[], code: string | null): string | null {
  if (!code) return null;
  return codes.find((c) => c.code === code)?.label ?? null;
}

/**
 * A code we do not recognise is SHOWN, not swallowed and not guessed at. Same
 * call as the ready-by source vocabulary: a value this build has never seen is
 * a future config or a bad write, and either way the person is told rather than
 * shown the nearest familiar word.
 */
export function unknownCodeNote(codes: TypeCode[], code: string | null): string | null {
  if (!code || typeCodeLabel(codes, code)) return null;
  return "This was recorded as a type this screen does not know. Ask the office.";
}

// ── (c) TABLE ROW ───────────────────────────────────────────────────────────
// Section 5 is 6 rows x 5 columns: item · found · where/notes · count · photo.
// The row model; the rendering decision is in ScopeTable.tsx and is the
// interesting part.
export type ScopeTableRow = {
  key: string;
  item: string;
  /** The small grey line under the item on the paper sheet. */
  hint?: string;
  /**
   * CORRECTED AGAINST THE SOURCE. Only TWO of the six rows carry the
   * found question on the paper — "Decking concerns" and "Leaks / problem
   * areas" — and its words there are "None seen" and "Yes", NOT "Found" and
   * "None". The other four rows have an EMPTY found cell: they are "write what
   * you saw", not a yes/no.
   *
   * "NONE SEEN" IS THE SHEET'S OWN WORDING AND IT IS BETTER THAN MINE. It does
   * not claim there are none — only that none were seen from where the
   * inspector stood. That is the same distinction this build keeps everywhere
   * else between what is true and what was observed, and it was already in
   * Jacob's paper before any of us wrote it down.
   */
  asksFound: boolean;
  /** null = not answered; only meaningful when asksFound. */
  found: boolean | null;
  where: string | null;
  /** Pre-printed on the paper for three rows: OSB sheets · roof vents · pipe boots. */
  countUnit?: string;
  count: number | null;
  /** Pre-printed label for the notes cell — "FLASHING NOTES" on the paper. */
  whereLabel?: string;
  photoRef: string | null;
};

/**
 * The six rows of section 5, transcribed from the PDF rather than invented.
 * Shape only — the live sheet reads these from tenant config.
 */
export const SECTION_5_ROWS: Omit<ScopeTableRow, "found" | "where" | "count" | "photoRef">[] = [
  { key: "decking_concerns", item: "Decking concerns", hint: "Rot, sag, soft spots", asksFound: true },
  { key: "decking_replace", item: "Decking to replace / custom carpentry", asksFound: false, countUnit: "OSB sheets" },
  { key: "leaks", item: "Leaks / problem areas", hint: "Pairs with Main issue", asksFound: true },
  { key: "flashing", item: "Chimney / skylights / walls / flashing", asksFound: false, whereLabel: "Flashing notes" },
  { key: "ventilation", item: "Ventilation", hint: "Existing, ridge vent, changes wanted", asksFound: false, countUnit: "Roof vents" },
  { key: "penetrations", item: "Penetrations noted", asksFound: false, countUnit: "Pipe boots" },
];

/** Is a group revealed by the current answer? Unanswered reveals everything. */
export function groupRevealed(gate: GateAnswer, options: GateOption[], group: string): boolean {
  const chosen = options.find((o) => o.code === gate.code);
  if (!gate.code || !chosen) return true;
  return chosen.reveals.includes(group);
}

export function rowIsAnswered(r: ScopeTableRow): boolean {
  return r.found !== null;
}

/** Only a row found on the roof carries detail worth reading back. */
export function rowHasDetail(r: ScopeTableRow): boolean {
  return Boolean(r.where || r.count !== null || r.photoRef);
}

// ── (d) EXTERNAL PHOTO REFERENCE ────────────────────────────────────────────
// A CompanyCam id we CANNOT resolve.
//
// R4: a reference not verified against the thing it references is a NAME, and a
// name is not a control. So this renders as a NOTE and never as evidence.
// Compare the QC photo_ref, which IS resolved — the database recomputes the
// hash and refuses one that does not match a photo on this work order. Nothing
// of the sort is possible here: we cannot ask CompanyCam, so the sheet knows
// only that somebody typed something.
//
// WHAT THAT FORBIDS ON SCREEN: no thumbnail, no "photo attached", no camera
// icon, no green tick, no count of photos. Every one of those is a claim the
// reference cannot support, and the person who would act on it is standing on a
// roof deciding whether they still need to take the picture.
export type PhotoRefNote = { kind: "none" } | { kind: "recorded"; raw: string };

export function photoRefNote(raw: string | null): PhotoRefNote {
  const t = (raw ?? "").trim();
  return t.length === 0 ? { kind: "none" } : { kind: "recorded", raw: t };
}

// ── TASK 3 — R1 ON THE SCREEN ───────────────────────────────────────────────
// Four states, and the fourth is not an error state — it is an honest one.
//
// A SECTION SOMEBODY DECLINED AND A SECTION NOBODY REACHED MUST NEVER LOOK THE
// SAME. `not_on_job` is a decision a person made; `unfilled` is work still to
// do; `unreadable` is us failing, and it says nothing at all about the roof.
// This is the QC panel's three-state discipline (2026-09-27) with the decision
// state added, and it is the reason the three cannot be collapsed into "empty".
export type SectionState = "not_on_job" | "unfilled" | "filled" | "unreadable";

export const SECTION_STATE_LABEL: Record<SectionState, string> = {
  not_on_job: "Not on this job",
  unfilled: "Nothing filled in yet",
  filled: "Filled in",
  unreadable: "Couldn't be read",
};

/** The sentence under the label. Empty where the label already says it all. */
export const SECTION_STATE_DETAIL: Record<SectionState, string> = {
  not_on_job: "Somebody answered that this job has none.",
  unfilled: "Nobody has answered this yet.",
  filled: "",
  unreadable: "That doesn't mean it is empty — reload before you rely on it.",
};
