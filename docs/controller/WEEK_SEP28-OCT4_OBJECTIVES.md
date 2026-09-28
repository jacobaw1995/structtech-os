# WEEK OF MON 2026-09-28 → SUN 2026-10-04

**This is the last full build week before the pilot.** Everything in it is judged by one
question: *does this make 7 October survivable?*

| | |
|---|---|
| **Thu 2026-10-01** | **REAL CREW ACCOUNT.** No account, no pilot. No pilot, no 31 October. |
| **Tue 2026-10-06** | **G5 — A4 Field Execution accepted. TRIPWIRE. The hard one.** Miss it and the pilot slips past 13 Oct with no recovery. |
| **Wed 2026-10-07** | **FIELD PILOT DAY 1.** Real crew, real BMR job. |

**Where we actually are.** Golden path run 1 completed steps 1–11 on 2026-09-27. Four zeros
that had stood for a month broke: `take_off_decisions`, `purchase_orders`,
`purchase_order_lines`, `production_packets`. The database holds its first signed-off master.
R4–R8 executed for the first time ever and R6/R7 hold — a real `field` member reaches zero
masters and zero estimates.

**Step 12 has never been run. `check_ins` 0. `qc_items` 0.** The crew's half of the chain is
the only part no human has looked at, and it is the half that decides the pilot.

---

## MON 09-28 — CLOSE THE CREW LOOP

**JACOB — 25 minutes, and it is the week's highest-value 25 minutes.**
1. **Step 12.** Sign in as the crew on the synthetic tenant, on a phone. Four questions:
   no master · no money · no pipeline · **can you record a check-in and a QC item.**
   Nobody has ever done the last one.
2. **`ORG_FILES_ENABLED`** in Vercel + redeploy. **Eleven days open.** Three minutes, and
   it is upstream of two readiness checks that cannot move without it.

- **Track S** — **A4.2 special trips: the log.** U built the surface unwired on 09-25;
  the schema does not exist. Reason codes, who, when, which work order. **A REASON IS A
  CODE, NEVER FREE TEXT.**
- **Track U** — **"Today" is the wrong word.** `fetch_field_jobs` filters `end_date >= today`
  with no upper bound: it returns *work not yet finished*, which is why the crew sees a job
  two days before it starts. The function is right; the heading lies. Rename to what it
  returns and show each job's dates. Then **mount the special-trip panel** once S lands.
- **Track X** — **run the adoption counters against real data for the first time.**
  `field_events` went from one event kind to four on 09-27. Three counters that had never
  fired have fired. Say which zeros are still unmeasurable and which are now real.

## TUE 09-29 — THE SCREEN A SALESPERSON USES IN A DRIVEWAY

**JACOB — Stripe. It was due 25 September and it is now four days late.** Verification runs
days to weeks against G11 on 18 October. Thirty minutes. Also: **Supabase Pro, $25** — 66
migrations in nine days on a plan with no backups, holding a client's data.

- **Track U** — **rebuild the New Lead intake.** Measured 09-27: **38 fields across 6 stages,
  11 on New Lead, 2 taps minimum per field, 22+ taps and 11 server round trips to fill one
  screen** — and **four different commit behaviours** (Enter works on single inputs, not on
  the address block, not on textareas; selects commit instantly). **Carry that measurement
  into the acceptance criterion; a criterion without a before-measurement is not one.**
- **Track S** — **the unit refusal, narrowly.** 21 of 27 line items have no unit and the 6
  that do use five spellings for three units. A lump-sum line legitimately has none.
  **RULED: a quantity other than 1 with no unit is meaningless — that is the case to refuse.**
  Do not constrain the column; six values in one tenant is not a denominator.
- **Track X** — **`ORG_FILES_ENABLED` and the measurement it has owed since 09-16:** a crew
  member sees an office-uploaded file on their own work order and does **not** see a
  master's. **On the rendered screen where you can.**

## WED 09-30 — THE CREW MODEL IS NOT WIRED TO THE CREW SCREEN

**JACOB — SPF at Wix.** X measured one `v=spf1` at the apex, not two. **Check before spending
the fifteen minutes; it may already be closed.** Also **Vercel Pro, $20**, before 7 October.

- **Track S + Track U together, and this is the day's whole point.** `fetch_field_jobs`
  reads neither the role, nor `view_field`, nor `crew_memberships`. **A crew member sees
  every scheduled trade job in the org.** `crew_memberships` holds 0 rows in every org and
  has no effect on what the function returns. At one job nobody notices. At five, every
  roofer sees all five — and that is the licensing story, not just the pilot.
  S owns the scoping; U owns what a person sees when a job is not theirs.
- **Track X** — **pilot readiness, seven days out.** Every item MOVED or NOT MOVED against
  `READINESS_LOG.md`, not memory. R4–R8 now execute; keep them honest.

## THU 10-01 — 🔴 THE CREW ACCOUNT. THIS IS THE GATE.

**JACOB — a real `field` account in Brothers Metal Roofing, for the person who will hold the
phone on 7 October.** ~2 hours including walking them through it.
**Measured, so the number is not a guess:** BMR has **0 field members**, **0 rows in
`crew_memberships`**, an owner who has not signed in since **2026-07-20**, and a trade work
order already scheduled for **2026-10-05 → 10-07**. The only `field` account in the entire
database belongs to the synthetic tenant.

- **All three tracks: the twelve-item field list, hardest first.** It stood at 8 still true
  on 09-19 and has not been re-scored since. **Whatever is left after today is what a crew
  hits on a roof next Wednesday.** Anything that cannot close is **named and dated**, never
  absorbed.

## FRI 10-02 — PACKET v2, END TO END

**JACOB — the Healthchecks grace-time test. 4 minutes. Open since 11 September — 21 days.**
Delivery is proven; **alerting has never been tested**, and a monitor whose alert path is
untested is a check that cannot fail.

- **Track S** — **derived callouts.** Measured: 2 of 3 live jobs would produce a non-empty
  list, **0 of 3 would produce a single "what is different about this roof" line** — and the
  reason is not empty fields. Across all 199 deals, `existing_roof_type` is set on 166 and
  `roof_type_requested` on 178. The three deals that reached a job are the three that skipped
  intake. **Built against any of the 166, the list populates immediately.**
- **Track U** — the office packet route shipped 09-27; **prove a packet built in the office
  arrives on the crew's screen.** That is the handoff the pilot runs on.
- **Track X** — pilot instrumentation armed, and **prove it by firing it**, not by reading it.

## SAT 10-03 — 🔶 GOLDEN PATH RUN 2 — CREW-DRIVEN

**The Phase A line is "one job, every table non-zero, run twice." Run 1 was Jacob-driven.**
**RUN 2 MUST BE DRIVEN BY THE CREW MEMBER OR IT PROVES NOTHING ABOUT ADOPTION.**
Hand them the phone. Do not narrate. Write down where they stop and what they say — **their
words, not a translation.**

- All three tracks fix live. The defect list, in the order it was hit, is Sunday's input.

## SUN 10-04 — RECONCILE, THEN THE G5 DRY RUN

- **Track S** — merge all three branches, deploy, and **re-derive every A4 *Done when* from
  live objects.** A closure recorded from a report is not a closure. **G5 is Tuesday.**
- **U and X** — push first, then supply the evidence S re-derives from.
- **Update the Build module to what was PROVED**, not what was reported. Seven Field items
  read `planned` and have not been touched since 07-23 or 08-16.

---

## THE FOUR THINGS THAT DECIDE THIS WEEK

1. **The crew account on Thursday.** Everything else is recoverable. This is not.
2. **Step 12, Monday.** Half the chain is unmeasured and it is the half a roofer uses.
3. **Crew scoping, Wednesday.** One job hides it; five jobs make it the licensing problem.
4. **Run 2 driven by the crew, Saturday.** If Jacob drives it again, we learn nothing we did
   not already learn on 27 September.

**And one that decides the month: Stripe. Four days late, verification measured in weeks,
G11 on 18 October.**
