# GOLDEN PATH RUN 1 — DEFECT LIST

**Run: 2026-09-26 evening → 2026-09-27 02:00 EDT. Jacob driving, ZZ SYNTHETIC tenant.**
Steps 1–9 completed. Step 10 (schedule) and step 12 (crew view) pending Sunday morning.
Step 11 (production packet) **could not be attempted** — see D8.

**LISTED IN THE ORDER HE HIT THEM, because the order is the data.** It says what a person
runs into first, which is not the same as what is most broken.

**Nine defects from nine steps.** Every one found by a person looking at a screen. Not one
was reachable from the database, and several sit behind correct policy.

---

## D1 · STEP 2 — the intake form fights the person filling it
**Owner: U** · Hit first, and it is the screen a salesperson uses in a driveway.

> *"whenever I opened the lead up and fill out the scope and all of the questionnaires it's
> very clunky it saves after every input and you have to hit tab for it to save you can't hit
> [enter] just go onto the next thing"*

Per-field autosave, commit on blur only, Enter does not advance. Sixteen scope fields.
**BEFORE-MEASUREMENT OWED:** how many fields, how many interactions per field today.

## D2 · STEP 3 — every UNIT is a dash and every QTY is 1
**Owner: S to establish cause, then U** · Five estimate lines, all `qty 1`, all `unit —`,
the whole price in RATE. A lump-sum estimate is legitimate — but it means the take-off has
**no quantities to derive from**, which is probably why D5/D6's material decisions all had to
be made by hand. Establish whether the unit is absent in the data or dropped in the render
before touching either.

## D3 · STEP 4–5 — "Outdoor mode" is on the customer's signed estimate
**Owner: U** · A crew feature on a homeowner's document. Small, embarrassing, one line.

## D4 · STEP 5 — after signing, the estimate is a dead end
**Owner: U**

> *"after I presented the estimate and signed it, there's no navigation no way to go back no
> nothing"*

The most important action in the application leaves the operator stranded. No back, no next,
no return to the job.

## D5 · STEP 8 — "Decided by a person whose name is not recorded on 2026-09-27."
**Owner: S** · Rendered to the user, in those words.

## D6 · STEP 8 — "Unknown changed a material after sign-off" × 5
**Owner: S** · Five consecutive lines, every one beginning "Unknown".

**D5 and D6 are the same defect and it is the headline of this run.** The system correctly
detected that materials changed AFTER the homeowner signed — that is good design, and it is
exactly the dispute a contractor loses money on — and then it cannot say who did it.
**A change-after-sign-off log that cannot name the actor is evidence of nothing.**

This is Class B provenance: 7 activity-row functions, named 2026-09-19, **scheduled for the
week of 2026-09-21, never done.** It is now visible on a screen a person used.

## D7 · STEP 8 — seven all-clear rows read as a problem list
**Owner: U** · "Is this material? · Which trade? · The chosen trade was voided · Decided, no
material yet · Materials a person deleted · Materials whose estimate line is gone · Decided
not material." Every one reports that nothing is wrong. Only the last carries a number
(1 of 5). **Seven headings stacked read as seven things to fix.** Same family as the
redundant counters closed on 2026-09-22 — fixed in one place, alive in another.

## D8 · STEP 11 — THE OFFICE CANNOT CREATE A PRODUCTION PACKET
**Owner: U** · **This is a missing surface, not a missing click, and it stopped the run.**

The packet is reachable **only through the FIELD module**. The crew screen has a packet
button expecting a packet; the office — the people who would build one — have no route to
make it. `production_packets` holds **0 rows in the entire database**; none has ever existed.

The data layer is already there: `production_packets.callouts` jsonb, four RPCs, a parser, a
numbered display, an add form, a two-tap delete. **The office route is the whole gap.**

## D9 · STEP 11 — "File storage for work orders isn't switched on yet."
**Owner: Jacob, then X** · `ORG_FILES_ENABLED` absent from Vercel Production. Measured by X
on 09-23 and again on 09-25 — **NOT MOVED, 9 days.** Storage policies were applied and proved
4/4 against the real Storage API on 09-16, so the feature is built and dark.

---

## WHAT THE ORDER SAYS

**Four of the nine (D1, D3, D4, D7) are nobody-thought-about-the-person defects.** No policy
is wrong, no data is wrong, nothing is insecure. They are what a contractor hits in the first
ten minutes and they are why software gets abandoned.

**Two (D5, D6) are a real accountability hole** that the build already knew about and
scheduled and then did not do.

**One (D8) stopped the run outright**, and it stopped it at exactly the step that has never
had a row in it.

**Not one of these nine would have been found by reading the schema.**
