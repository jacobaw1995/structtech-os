# G5 acceptance case — assembled 2026-10-05, Track S

**G5 is "A4 Field Execution accepted", Tue Oct 6 — ONE day from today (Mon Oct 5).** Pilot Wed Oct 7,
two days. G6 Tue Oct 13, eight days. Computed from `TZ=America/New_York date` = `Mon Oct 5 14:01:31 EDT 2026`,
not taken from the directive.

Scope is the **CUT accepted 2026-10-01**: KEEP **A4.2**, **A4.6**, **A4.7**. MOVED TO NOVEMBER:
A4.1, A4.3's blocking clause, A4.4, A4.5, A4.8.

**Every Done-when below is quoted from §5.4 of `docs/STRUCTTECH_OS_DIRECTIVE.md`, read today, not from
the directive block that commissioned this file and not from memory.**

**RULE 17 APPLIES TO ALL THREE: a Field item is accepted on a rendered screen, and I render none.**
Where a verdict is MET it is met at the data and policy layer; where the Done-when's words require a
screen, that is said and the human act is named.

---

## A4.2 — Special trips

> **Done when:** logged in ≤2 taps and visible on the office dashboard the same day.

*(The item's own description, same line of §5.4: "Type (`tool`|`material`|`other`), reason code,
impact. The phase's primary leading indicator.")*

### What exists, measured from live objects

| | measured 2026-10-05 |
|---|---|
| `special_trips` rows | **0** |
| columns | `id, org_id, work_order_id, reason_code, occurred_on, note, recorded_by, recorded_at, created_at, client_token` |
| reason codes | 7, CHECK-constrained: `material_missing, material_wrong, access, weather, customer_change, rework, equipment` |
| indexes | 3; exactly 1 unique (`special_trips_pkey`), plus the partial `special_trips_client_token_uniq` added 2026-10-04 |
| crew surface | `SpecialTripPanel`, rendered at `field/[workOrderId]/page.tsx:263` |
| office surface | `coordination/[workOrderId]/page.tsx:140`, `.eq("work_order_id", …)` |

**Taps, counted from the component, with the axis stated (RULE 18):** `<details><summary>` "Log a
special trip" = **tap 1**; the reason button = **tap 2**. Nothing to type — the panel says so
("Tap the reason you came back. That is the whole thing — nothing to type."). **That is 2 taps from
an OPEN work order, and 3 from the job list**, which the Done-when does not disambiguate.

**The office half, PROVED end to end in one rolled-back transaction with a control:** the field
account logged a trip through the RPC the panel calls; **Jacob (`agency_admin`) then read it back the
same day** — `occurred_on = 2026-10-05`, author stamped as the field user — via the coordination
page's exact SELECT; **Isaac (`owner`) saw it too**, so the scope is the org and not the author; and
**a Material Matrix member saw 0**, which is the control that makes the read mean something.

### Verdict: **MET on the taps. NOT MET as written on the second clause.**

**There is no office dashboard.** Of the 21 routes under `src/app/w`, the only reader of
`special_trips` is the **per-work-order** coordination page, scoped by `work_order_id`. Neither
`w/[orgId]/page.tsx` nor `coordination/page.tsx` mentions special trips.

**The mechanism, and a case where it gives a different answer (RULE 21):** the office sees a trip
only by opening the specific work order it was logged against. With BMR's **one** live trade work
order that is indistinguishable from a dashboard. With two jobs, a trip logged on job B is invisible
to anyone looking at job A or at the coordination board — nobody is "told", they have to go and look.

**Second finding, which the Done-when's own axis cannot see:** the item describes **Type
(`tool`|`material`|`other`)** and **impact**. Neither column exists, and nothing in the Done-when
tests for them, so the item could be ticked with two of its three described fields missing.

### What would prove the rest
A human act on a rendered screen: **the crew taps a reason on a phone, and the office finds that trip
without being told which work order it was on.** Today that requires knowing the job first.

---

## A4.6 — Crew model

> **Done when:** the scheduler refuses to assign a crew with no vehicle to a job requiring transport.

### What exists, measured from live objects

| | measured 2026-10-05 |
|---|---|
| the refusal | `crew_has_no_vehicle` **PRESENT** in `assign_crew_to_work_order`'s body (`20261002025107`) |
| the gate | `tenant_enforces_stage_gating(org)` — BMR reads **false** |
| BMR crews / people / memberships / assignments | **1 / 1 / 1 / 1** |
| the one crew person | "Anderson Reyes", `has_vehicle = true`, not archived, on "Install Crew" |
| `crew_assignment_states` for BMR | `vehicle_state = has_vehicle`, `members = 1`, `availability_state = all_available`, linked to schedule block `5aa34bb4` |

**Re-proved today, not carried from 2026-10-01.** `scripts/pilot/crew-vehicle-fixture/run.sh` re-run:
**PHASE 1 PASS** (refused with hint `crew_has_no_vehicle` against what the database actually holds),
**PHASE 2 FAIL on the mutant** ("ASSIGNED with vehicle_state=no_vehicle"), **PHASE 3 mutant-reach
GONE** — and the mutant lands on the last file defining the function (RULE 20/22).

### Verdict: **MET, under the 2026-10-01 ruling, and the 10-01 caveat is now STALE.**

The ruling of record is that *"a 'never' and a 'must refuse' are reconciled by a SWITCH"*: the
Done-when tests that the refusal **exists and fires when a tenant turns `enforce_stage_gating` ON**,
and the shipped OFF default tests §2.8. Both hold.

**What has changed since 2026-10-01: the "capability, not a guarantee — crews = 0" note no longer
applies.** Crews, people, memberships and assignments are all **1**. The capability has met real
data — **on the happy path only**, because BMR's one crew member **has** a vehicle, so the refusal
**cannot be demonstrated against BMR's own rows.** That is the correct outcome, not a gap: there is
nothing to refuse.

**Two substitutions remain on the record and are unchanged.** Nothing anywhere records whether a job
"requires transport" (0 columns matching `transport|requires_vehicle|needs_vehicle`), so "every trade
work order requires transport" stands as a ratified substitution with its own trigger. And
`enforce_stage_gating` still drives both this refusal and A2.3's ready_by block — the November split,
triggered by the first tenant who turns it on.

### What would prove the rest
Nothing is owed for G5. **The screen act that would exercise the refusal does not exist in BMR's
data**: it needs a crew whose members all read `no_vehicle` AND the switch ON, and the ruling says
the switch stays off.

---

## A4.7 — Office-side upload + per-role file permissions

> **Done when:** roof data and photos load from the office and a crew role cannot delete them.

*(§5.4 also carries: **PROXY IN FORCE — REPLACE BY 2026-11-01**, controller 2026-09-17 —
`view_master_work_order` stands in for a file-write/delete capability and for check-in edit/delete.
The live policies and `delete_check_in()` carry that date as a comment.)*

### What exists, measured from live objects

| | measured 2026-10-05 |
|---|---|
| bucket | `org-files`, **private** |
| path shape | `<org_id>/<office-uploads｜work-order-docs>/<work_order_id>/<file>` |
| policies | **3** — SELECT requires `can_reach_work_order_files`; **INSERT and DELETE additionally require `can_view_master_work_order`** |
| **objects in `org-files`** | **0 — nothing has ever been uploaded, in any org** |
| office surface in `src` | upload-url route, `WorkOrderFiles.tsx`, `org-files.ts`, `paths.ts`, `work-order-file-actions.ts`, `work-order-files-states.ts` |
| crew surface | the field page passes `canManage={false}`; the upload control renders only under `canManage` |
| `ORG_FILES_ENABLED` | **SET in Vercel production, created 2026-10-03 23:47:30 EDT.** Type `sensitive`/secret — **its VALUE was not decrypted and is unverifiable from here**, and the code requires exactly `=== "true"` |

**Capabilities measured per REAL identity** — and the first attempt was an **empty instrument** I
caught: read as `postgres`, `has_capability` returned `false` for all three members because it keys on
`auth.uid()`. Re-run inside each identity:

| role | `view_master_work_order` (write/delete) | `can_reach_work_order_files` (read) |
|---|---|---|
| `agency_admin` (Jacob) | **true** | true |
| **`field` (Anderson)** | **false** | **true** |
| `owner` (Isaac) | **true** | true |

**EXERCISED, with a control that succeeds** (probe objects created and rolled back, RULE 14):

- **CREW INSERT REFUSED** — `42501 new row violates row-level security policy for table "objects"`.
- **OFFICE INSERT ACCEPTED** — the identical statement as `agency_admin`. So the refusal is about the
  **role**, not about the path.
- **CREW READ = 2 objects.** The block is specifically on **write**, not a blanket RLS wall — which is
  what the Done-when wants, since the crew must still see the roof data.

**AND THE DELETE COULD NOT BE EXERCISED AT ALL, which I report rather than paper over.** My first
probe deleted as the field account and got a refusal — and it was **the wrong refusal**:
`storage.protect_objects_delete` → *"Direct deletion from storage tables is not allowed. Use the
Storage API instead."* **That trigger fires for every role, including Jacob's.** Graded as a pass it
would have certified the policy from a barrier that has nothing to do with it — RULE 11's exact
failure. So the DELETE policy expression was **evaluated** per identity instead:
**`field` → false, `agency_admin` → true.** That is a statement about the predicate, **not** an
exercise of the path.

### Verdict: **"a crew role cannot delete them" — MET for INSERT (exercised), and CANNOT BE PROVED FROM HERE for DELETE.** **"roof data and photos load from the office" — CANNOT BE PROVED FROM HERE.**

Two reasons, both measurable: **`org-files` holds 0 objects**, so the office upload has never
happened; and **`ORG_FILES_ENABLED`'s value is secret**, so whether the surface is even switched on
cannot be read from here. The var exists — that ends the twelve-day absence `docs/GATES.md` records —
but **a variable existing is not a variable equal to `"true"`.**

### What would prove the rest, as human acts on a rendered screen
1. **Jacob opens `/w/<bmr>/coordination/d76d8664` and sees an upload control** rather than the warn
   sentence *"File storage for work orders isn't switched on yet. Roof data and photos can't be added
   here until it is."* — that single screen settles `ORG_FILES_ENABLED`.
2. **He uploads a roof plan or a photo** and the list shows it (*"File added. The crew can see it on
   this job."*).
3. **Anderson opens the same job on the phone, sees the file, and has no remove control** — and if a
   delete is forced, the screen shows *"That file wasn't removed. Ask the office to remove it."*
   **Step 3 is the only thing that exercises DELETE through the Storage API, which SQL cannot reach.**

---

## Can G5 be accepted tomorrow?

**No — not as the three Done-whens are written. Yes, on a cut of one clause.**

Two of the three are in hand. **A4.6 is MET** and was re-proved today by a mutation test that passes
on the real object and fails on the mutant; its 2026-10-01 caveat is now stale, because BMR has a real
crew. **A4.2 is MET on "≤2 taps" and on same-day office visibility, proved cross-identity with an
outsider control — but NOT MET on the word "dashboard"**, which does not exist: the office reads trips
per work order. **A4.7 is the cause, and it is not a build item.** Its write/delete half is as good as
SQL can make it — the crew's INSERT is refused with a control that succeeds, and the DELETE predicate
evaluates false for `field` — but **`org-files` holds 0 objects and `ORG_FILES_ENABLED`'s value is
secret, so "roof data and photos load from the office" has never been observed by anyone.**

**THE SMALLEST REMAINING SET, and all three acts are Jacob's, on a rendered screen, ~10 minutes:**

| # | act | settles |
|---|---|---|
| 1 | open BMR's work order in the office and report whether an upload control or the "isn't switched on yet" sentence appears | `ORG_FILES_ENABLED`, A4.7 clause 1 |
| 2 | upload one roof plan or photo | A4.7 clause 1 |
| 3 | open the same job as Anderson on the phone: see the file, confirm no remove control | A4.7 clause 2, the DELETE half SQL cannot reach |

**PROPOSED CUT, raised the day it became visible rather than on Oct 6:** **A4.2's "office dashboard"
moves to November, and the clause is restated as "visible to the office the same day"** — which is
what shipped, what was proved today, and what the pilot actually needs at one job. A dashboard is a
new surface, not a fix; building one on the day before a gate, for a tenant with a single live work
order, is the shape of change that breaks pilots. **Trigger for building it: the day BMR runs two live
trade work orders at once**, which is the first moment per-work-order visibility and a dashboard differ.

**If that cut is accepted, G5 turns on nothing but Jacob's three screen acts, and the honest statement
of the gate is: not blocked on a build.** If it is not accepted, G5 slips — and the slip is one
surface, not a stage, so it is a day or two and not the three that would force a re-dating.
