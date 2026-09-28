# STRUCTTECH OS — DAILY OBJECTIVES · MON 21 → SUN 27 SEP 2026
**Read live from the Build module 2026-09-20.** One block per day for Arcane.

## WHERE WE ACTUALLY ARE

**Phase A: 42 items — 6 shipped · 9 in progress · 27 planned.**
**The pilot is 2026-10-07 — 17 days.** MVP live 31 October.

### THE MODULE UNDERSTATES US. FOUR FIELD ITEMS ARE MIS-GRADED.

Field (crew) reads **1 in progress / 7 planned**. That is not what exists:

| Item | Module says | Actually |
|---|---|---|
| Daily objective per trade WO | planned | **spine built 9/19 by S** — no screen |
| Crew acknowledgment | planned | **spine built 9/19 by S** — no screen |
| QC items | planned | **app side + 22/22 proposal built 9/19 by X** — table not applied |
| Office roof-data / photo upload | planned | **built by X, policies live** — waiting on `ORG_FILES_ENABLED` |
| Per-role file permissions | planned | **policies applied and proved 4/4** — waiting on the same flag |
| Crew/person model | in progress | **15 RPCs + office roster screen shipped** |

**Five of eight Field items have their spine and are missing a SCREEN.** That changes what
this week is: not "build field," but **surface what is already built, then close the four
that genuinely aren't.**

### ALSO DUE A REGRADE — SIGNING

Four Signing items read `in_progress`. As of today Jacob sent SYN-1 from the office UI,
opened it on a phone unauthenticated, and signed it. Transactional email was proven
2026-09-16 with three messages to a real inbox. **These are shipped or close to it and the
module has not caught up.** Password reset is the exception — it works only for Jacob
until Supabase custom SMTP is configured.

**A module that understates progress is as misleading as one that overstates it.**
Regrade Monday, off found objects, not off reports.

---

## MON 2026-09-21 — REGRADE, THEN SURFACE THE SPINES

- **Track S** — regrade Phase A against found objects: Signing items, the four Field
  items above, the dashboard. Move an item only because you found the object. Then
  **Class B provenance** — the 7 activity-row functions, scheduled for this week since
  2026-09-17.
- **Track U** — **daily objective + crew acknowledgment screens.** S's functions are
  ready and there is no surface for either. Plus today's four crew-copy defects: no
  capability identifiers in crew copy, no internal vocabulary, the crew lands on their
  work rather than the office dashboard.
- **Track X** — confirm `ORG_FILES_ENABLED` is live in production, then finish A4.7:
  a crew member sees office-uploaded files on their work order and cannot reach a
  master's. **Measured, not reasoned.**

---

## TUE 2026-09-22 — A4.2 SPECIAL TRIPS

The exception log with reason codes. A crew's day that went sideways is data, not a
free-text blocker box.

- **Track S** — the log: reason codes, who, when, which work order. A reason is a code,
  never free text.
- **Track U** — **two taps.** SCOPE §2.4 and the module both say it: a crew member logs
  a special trip in two taps, with gloves on, in the sun.
- **Track X** — hand S the `qc_items` migration; it has been proved 22/22 with both
  mutants caught since 9/19.

---

## WED 2026-09-23 — A4.3 QC ITEMS

- **Track S** — apply X's `qc_items` proposal. Read X's fixture results before applying.
- **Track U** — the QC panel on the crew screen. **A requirement not met is a STATE, not
  an absence.** "No photo" and "photo not required here" never render the same.
- **Track X** — A4.8 adoption counters. What we could not tell Jacob on pilot day was a
  seven-item list; close what `field_events` now makes answerable.

---

## THU 2026-09-24 — PACKET v2 (THE CALLOUT LIST) + WHAT'S LEFT

**The MVP line is explicit: graphical roof and trim maps are DEFERRED to November. MVP
ships a structured callout list.** Do not build maps.

- **Track S** — packet v2 data behind the callout list.
- **Track U** — render it at phone width, in the crew's words.
- **Track X** — re-run pilot readiness and report what moved and what did not.

---

## FRI 2026-09-25 — CLOSE THE TWELVE-ITEM LIST

Track U's own list of what a real crew person could not do stood at **8 still true** on
2026-09-19. Whatever is left after this week is what a crew hits on a roof on October 7.

- All three tracks work the remaining items, hardest first.
- Anything that cannot close this week is **named and dated**, not absorbed.

**JACOB — STRIPE ACCOUNT TODAY.** Under the StructTech entity. ~30 minutes, then days to
weeks of verification. G11 billing is due 2026-10-18 and verification is the long pole.

---

## SAT 2026-09-26 — 🔶 GOLDEN PATH · RUN 1

Lead → estimate → present → sign → job → master sign-off → trade work orders → materials
→ PO → schedule → crew view. **A real job, Jacob driving, all three tracks fixing live.**

It is a Phase A line item — *"one job, every table non-zero, run twice"* — and it has
never been run. Remote signing now works end to end, so the chain is finally whole.

**The defect list it produces, in the order it was hit, is next week.**

---

## SUN 2026-09-27 — RECONCILE + ACCEPT

- **Track S** — merge, then accept every Field item that closed **by re-deriving it from
  live objects**. A closure recorded from a report is not a closure.
- **U and X** — push first.
- Update the Build module to what was actually proved.

---

## JACOB'S DATES

| When | Item | Gates | Cost |
|---|---|---|---|
| **Mon** | Supabase Pro — $25 | backups on a client's business. **Day seven.** | 2 min |
| **Mon** | `ORG_FILES_ENABLED` = true in Vercel + redeploy | 2 Phase A field items | 2 min |
| **Fri 9/25** | **Stripe account under the StructTech entity** | **G11 · Oct 18** | 30 min + weeks |
| **Thu 10/1** | **Real crew account. No account, no pilot.** | **G6 · Oct 7** | ~2 hrs |
| Sat 9/26 | Drive the golden path | **the MVP date** | half a day |

---

## THE RISK, STATED PLAINLY

**Field is not as far behind as the module says — it is behind on SCREENS, not on
plumbing.** Five of eight items have working database functions and nobody can touch
them. That is a good problem and it is a solvable week.

**What is not solvable by CC:** a real crew account by October 1, and a Supabase plan
with backups. Both are Jacob's and neither has moved.

---

## STANDING RULE ADDED 2026-09-20 — owed to `claude/00_START_HERE.md` §6

**A POLICY-READING METHOD IS SOUND FOR WHAT A POLICY GOVERNS AND BLIND TO WHAT A PERSON SEES.**
Track U refused to re-score the twelve-item field list from source on 2026-09-20, second
refusal of the same kind in one week, both correct. Its stated reason is the rule: *"a score
from source would be the same derivation that missed all four of today's findings."* All four
screenshot defects were reachable only by looking — a card that should not have been built, a
sentence naming a capability, a section header for an empty section, a redirect that never
fired. Every one of them sat behind correct policy. **Deriving a screen from its policy proves
what the screen is permitted to show, never what it shows.** Acceptance of a Field item before
the 7 October pilot requires the rendered screen, measured, not the source that produces it.

**Root cause of all four, one clause** (`loadHome`, fixed in `342f07b`):
`if (entitled.has("coordination") || entitled.has("field"))` gated sections on what the ORG is
entitled to rather than on what the PERSON can open. A field member is entitled to `field`, so
the `||` built the office's three cards for a roofer. Now gated on `ctx.visibleModules`.
Sweep after the fix: **0 capability identifiers in prose across the 45 crew-reachable modules**
(was 3 strings in 2 modules).

**Measurement route decided 2026-09-20:** the controller measures the rendered screens itself
through Jacob's desktop link (Chrome must be OPEN and signed in as the crew account). The
Claude-in-Chrome extension install is the fallback, not the first ask — it is a step Jacob has
to run himself, and those are a last resort.
