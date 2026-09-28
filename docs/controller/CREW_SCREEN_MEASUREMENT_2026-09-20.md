# CREW SCREEN MEASUREMENT — 2026-09-20 (America/New_York)

**Instrument:** the controller read Jacob's live Safari session on `os.structtek.com` through
the desktop link — full-resolution display capture plus the macOS accessibility tree. Read-only:
no click, no keystroke, no navigation by the controller. Jacob clicked once ("Open Field").

**Identity measured, not assumed:** org `ZZ SYNTHETIC Field Test (not a client, disposable)`,
subtitle reads `contractor workspace · role: field · 2026-09-20`. Sidebar holds exactly one
item, `Field`. This is a field-role member, not an owner session.

**Two screens covered:** the workspace home (`/w/<org>`) and the Field screen (`Open Field`).
That is the entire surface a `field` member can reach from a cold login. **Denominator: 2 of 2.**

**WHY THIS DOCUMENT EXISTS.** Track U refused twice in one week to score these screens from
source, and was right both times: *"a score from source would be the same derivation that missed
all four of today's findings."* Everything below was reachable only by looking.

---

## PART 1 — DEPLOYMENT STATE, ANSWERED FROM THE USER'S SIDE

**Commit `342f07b` is NOT in production.** Every string U rewrote on 2026-09-19 is still
rendering to the browser: "not void", "unfinished blocks", "schedule block", the office cards,
and the absent single-module redirect. This is measured at the surface, not inferred from a SHA.

**COMMITTED IS NOT MERGED · MERGED IS NOT DEPLOYED · DEPLOYED IS NOT EXERCISED.** The four
screenshot defects are fixed in source and fixed for nobody. Seventeen days to the pilot.

---

## PART 2 — WORKSPACE HOME, MEASURED

**(1) Three office cards built for a roofer.** `Schedule` · `Jobs` · `Materials and purchasing`.
The sidebar on the same render correctly shows one item. **The nav and the body of one page
disagree about what this person can reach.** Root cause already found by U (`loadHome` gating on
`entitled` rather than `ctx.visibleModules`); the point recorded here is that it is live.

**(2) THREE capability identifiers printed as prose, not two.**
- "Master work orders are not counted here — your role does not have **view_master_work_order**."
- "Estimates is not shown — your role does not have **view_estimates**."
- "contractor workspace · **role: field** · 2026-09-20"

U's sweep reported **0 capability identifiers in prose across 45 crew-reachable modules.** That
count is TRUE on `track-u` and FALSE in production. **A count without its container is not a
fact** — the container was the branch, and the branch is not what the roofer opens.

**(3) A screen says what the person can do, not what the system withheld.** Violated twice on
one card. A roofer is told, in a sentence, that a module he will never use is not shown to him.
The fix is deletion, not rewording — U already deleted `HomeData.hidden` and `HiddenSections`
on the branch.

**(4) Database vocabulary rendered to a roofer.** "1 trade work order **not void**" · "1 of 1
job has a trade work order **that is not void**" · "0 of 0 **unfinished blocks** start before
their materials are ready" · "**schedule block**". `void` is a row state. Nobody on a roof says
it.

**(5) `0 of 0` shown to a user.** "0 of 0 purchase orders in draft" · "0 of 0 unfinished blocks
start before their materials are ready." A denominator of zero has no information in it and
reads as a malfunction.

**(6) NEW — the search control says two different things to two different people.**
Visible placeholder: **"Search…"**. Accessible name: **"Not built yet."** A sighted person sees
a working search box; a screen reader announces that the feature does not exist. **This is the
first measured instance on this project of a surface whose sighted and assistive renderings
disagree** — and it is invisible to every instrument we own except looking at both.

**(7) `+ Add` is live for a field member** in the top bar, on both screens. What a `field` role
is being offered to create is UNMEASURED — the controller holds read-only access and did not
click it. Recorded as unanswered, not guessed.

**(8) No single-module redirect.** Exactly one module is visible and `/w/<org>` rendered the
home page anyway.

---

## PART 3 — THE FIELD SCREEN, MEASURED

This is the only screen a roofer opens on a phone at 6:40 a.m. It contains, in full:
a one-word toggle, the word "Today", the date, and one empty card.

**(9) "No jobs scheduled" — with 1 job and 1 live trade work order on record.** The home screen
one click earlier reported `1 schedule block on record`, `0 on site today · 0 upcoming ·
1 finished`, and `1 of 1 job has a trade work order that is not void`. **Whether the Field
screen is empty because the block is finished, or because nothing surfaces here at all, cannot
be determined from outside.** Recorded as unanswerable rather than resolved. Track U answers it.

**(10) "Jobs appear here once coordination schedules a crew."** `coordination` is a MODULE NAME
rendered as if it were a person or a department. U's sweep covered capability identifiers; this
is a module identifier, a category the sweep did not cover. **The sweep's axis was too narrow,
and it passed.**

**(11) An unexplained toggle is the most prominent control on the crew's only screen.**
Accessibility role: `AXCheckBox/AXToggle`. Label: **"Outdoor"**, one word, centered above the
day heading. Nothing states what it changes or whether it is currently on. The person who needs
it most is squinting at a phone in direct sun, which is the one condition in which guessing is
most expensive.

**(12) The office chrome is wrapped around the field screen** — `+ Add`, notifications bell,
search box, org switcher `StructTech ▾`. None of it belongs to a roofer's morning.

**(13) Everything below roughly the top third of the viewport is blank.**

**(14) THE ACCEPTANCE FINDING.** Five Field items are graded `planned` in the Build module while
S, U and X each report the spine built: daily objective per trade WO · crew acknowledgment ·
QC items · office roof-data/photo upload · per-role file permissions. **Not one of them is
reachable from this screen.** Whatever exists server-side, the crew surface is one empty card.

> **STANDING RULE, ADDED TODAY: A SPINE IS NOT A SURFACE, AND THE BUILD MODULE CANNOT TELL THE
> DIFFERENCE.** An item whose tables, policies and functions exist and whose screen shows
> nothing is `planned` from the roofer's side and `shipped` from the database's side. Before
> 7 October, a Field item is accepted on the RENDERED SCREEN or it is not accepted.

---

## PART 4 — WHAT THIS SAYS ABOUT THE METHOD

**A POLICY-READING METHOD IS SOUND FOR WHAT A POLICY GOVERNS AND BLIND TO WHAT A PERSON SEES.**
Every finding above sat behind correct policy. The database refused nothing it should have
allowed and allowed nothing it should have refused. The defects are entirely in what the screen
chose to say.

**A SWEEP IS ONLY AS WIDE AS THE AXIS IT WAS WRITTEN ON.** U's prose sweep keyed on capability
identifiers and returned 0. Production holds three capability identifiers and one module
identifier. The sweep was correct on its axis, run on the wrong container, and passed.
**The rule is not the asset; the instrument is — and an instrument has an axis.**

**MEASUREMENT ROUTE OF RECORD.** The controller reads Jacob's live browser through the desktop
link. Safari is granted read-only, so Jacob clicks and the controller looks. No extension
install, no terminal step. Cost to Jacob on 2026-09-20: one approval and one click.

---

# PART 5 — RE-MEASURED AFTER DEPLOY, same day, 13:05 EDT

**Deployed SHA confirmed by the controller's own instrument, not from a report:**
`GET https://os.structtek.com/api/health` → `{"ok":true,"sha":"41c4c6f52b5f1639d9c52481f20ebba3782b13b4","env":"production"}`.
Track S merged `f6f1b1b` (track-u) and `2d735b1` (track-x) as `41c4c6f`, live 12:45:52 EDT.
No migration ran. X's `qc_items` proposal correctly left unapplied.

**Same crew account, same browser, same two screens.**

## CLOSED — all four, by measurement

**The single-module redirect fires.** Signing in landed the crew member directly on Field,
where before the fix it landed on the workspace home behind a blue button. Confirmed a second
way: pressing the browser **Back** button did not reach the home screen — the forward arrow
armed and the page stayed on Field. **`/w/<org>` is now unreachable for a member with one
visible module**, which takes the three office cards, both capability identifiers in prose
(`view_master_work_order`, `view_estimates`) and the "not void" / "unfinished blocks" /
"schedule block" vocabulary off this person's screen with them.

Recorded honestly: the office cards and the prose are closed **by the route becoming
unreachable**, which is the intended design, not by each string being separately proved gone on
a rendered page. A member who gains a second visible module reaches that home again.
**Closed by design is not the same as closed by measurement, and the distinction is owed to
whoever grades this next.**

## STILL LIVE — the Field screen is unchanged, and correctly so

U's fix was to `loadHome`. The Field screen is a different surface and nothing about it moved.
Every finding in Part 3 stands: `coordination` rendered as a noun, the unlabelled **Outdoor**
toggle, the office chrome (`+ Add`, bell, search) wrapped around a roofer's morning, and the
blank two-thirds of the viewport.

## THE FINDING THAT GREW

Track S answered Part 3 §9 decisively: the Field screen is empty because the single schedule
block ran **2026-09-17 → 2026-09-19** and New York today is the **20th**; `fetch_field_jobs`
drops it on `end_date >= today`, 1 of 1 candidate rows, and only on that test.

**So the screen is CORRECT and it is still the wrong product.** A crew member who finished a
job yesterday opens the app and sees a blank page that says nothing ever happened — no
"nothing scheduled today", no yesterday, no what is next. **On 7 October that is the entire
application for every person not working that exact date.** This is not a defect in
`fetch_field_jobs`; the query does what it says. It is a missing surface, and it is now the
highest-value Field item on the board.

## INSTRUMENT NOTE, for whoever runs this next

Safari can only be granted at **read** tier through the desktop link: the controller sees the
rendered screen and cannot click it. Clicking requires the Claude-in-Chrome extension, and
Jacob does not use Chrome. **The working arrangement is therefore fixed and is not a
negotiation: Jacob clicks, the controller looks.** Budget one click per screen and name the
click exactly. Cost on 2026-09-20 for a full two-screen measurement, twice: two approvals and
three clicks.
