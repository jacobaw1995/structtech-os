# BROWSER CHECK-OUT — Catalog + Estimate picker
**For Jacob · prepared 2026-08-26 · NOT RUN by Claude Code · owed before A2 acceptance**

## Why this exists
On 2026-08-25 I flagged the catalog UI as the weakest thing shipped that day: **a table,
not a designed surface, and never looked at by a human.** Everything below has been proved
at the data layer by probe. **None of it has been seen in a browser.** Those are different
claims and this document exists so they do not get conflated.

**Where:** `os.structtek.com` → **Brothers Metal Roofing** tenant, signed in as Isaac
(`owner`) or yourself (`agency_admin`). Both carry `manage_catalog: true`.

**A note on residue:** every step here writes REAL rows to the BMR tenant. Step 12 cleans
up. Nothing in this script should touch a real BMR lead or estimate — step 8 says which
estimate to use and why.

---

## PART A — the catalog page

**1. Reach it.** Estimating → **"Product catalog"** (top right of the estimates list).
- **See:** a page headed *Product catalog* with the BMR name under it, an add row, and an
  empty state reading *"No active catalog items yet…"*.
- **FAIL IF:** the link is missing; the page 404s; you land on the estimates list.

**2. The empty state.** Read it before adding anything.
- **See:** it tells you what to do next and mentions pricing an estimate line.
- **FAIL IF:** a bare "No results" or an empty table with headers and no explanation.

**3. Add an item by SELL.** Name `CHECK Standing seam 24ga`, Category `Metal`, Unit `sq`,
Cost `310`, Sell `465`.
- **See:** as you type Sell, **Markup fills itself in with `50.00`**, and the Markup box
  goes grey with the word **CALCULATED** under it while Sell reads **ENTERED**.
- **FAIL IF:** markup stays blank; both look identical; you cannot tell which you typed.

**4. Add an item by MARKUP.** Name `CHECK Ridge cap`, Unit `lf`, Cost `12`, Markup `60`.
- **See:** **Sell fills itself in with `19.20`**, and now *Sell* is the grey CALCULATED one.
- **THIS IS THE WHOLE POINT OF STEP 1.** Yesterday this direction did not exist.
- **FAIL IF:** sell stays 0/blank, or typing markup does nothing.

**5. A zero-cost labour line.** Name `CHECK Tear-off labour`, Unit `sq`, Cost `0`, Sell `85`.
- **See:** it saves; **Markup shows `—`, not `0`**, and the field hint reads NEEDS A COST.
- **FAIL IF:** markup shows `0.00`, or `Infinity`, or the save errors.

**6. Edit, archive, restore, delete.**
- Edit `CHECK Ridge cap`, change Sell to `20`. **See:** markup recalculates to `66.67`.
- **Archive** it. **See:** it leaves the list; *Show archived items* brings it back with an
  **Archived** chip.
- **Restore**, then **Delete** it. **See:** it is gone.
- **FAIL IF:** any control is missing, or Delete silently does nothing.

**7. Judge it as a designed surface, not a passing test.** This is the step I cannot do.
- Does it look like the rest of the app, or like a spreadsheet someone bolted on?
- On your phone: does the table scroll horizontally **without the page itself scrolling
  sideways**?
- Is *Markup %* worth the width it takes, or would you rather see cost/sell only?
- **FAIL IF** your honest reaction is "this is a developer's table." Say so — it is the
  gate, and re-doing it is cheaper than shipping it.

---

## PART B — the estimate picker

**8. Open an editable estimate.**
**Production has NO editable estimate — all four are `signed` or `void`** (that is why the
probe had to build a draft and roll it back). So: pick a **synthetic** BMR lead, create an
estimate from it, and work there. **Do not use a real signed estimate.**
- **FAIL IF:** you cannot create one.

**9. The two add paths sit side by side.** Scroll to the line items.
- **See:** **`+ Add line item`** and, beside it, **`From catalog`**.
- **FAIL IF:** "From catalog" replaced the blank-row button (that would break §2.8 —
  an uncatalogued item must stay addable), or it is absent while the catalog has items.

**10. Pick from the catalog.** Click **From catalog**.
- **See:** an inline list **in the page — no modal, no drawer** — showing name, category ·
  unit, and price on the right. Click `CHECK Standing seam 24ga`.
- **See:** the list collapses and a **normal line item row** appears — description
  `CHECK Standing seam 24ga`, unit `sq`, rate `465.00`, qty 1 — editable and draggable like
  any other row.
- **FAIL IF:** a modal opens; the row looks different from the others; the picker stays open.

**11. THE SNAPSHOT — the most important step in this document.**
- Set that line's quantity to `12`. Note the total.
- In another tab, open the catalog and change `CHECK Standing seam 24ga`'s Sell to `999`.
- Come back to the estimate and **reload**.
- **SEE: the line is still `465.00` and the total has NOT moved.**
- **FAIL IF the line changed to 999.** That would mean a catalog edit can silently re-price
  a quote already given to a homeowner. **If this fails, stop and tell me — nothing else in
  Part B matters.**
- Then override that line's rate to `500` by hand. **See:** it saves and stays 500.

**12. Clean up.** Delete the test estimate, then delete the three `CHECK …` catalog items.
- `CHECK Standing seam 24ga` will **refuse to delete** while the test estimate's line still
  references it, **naming the count** — that is correct behaviour, not a bug. Delete the
  estimate first, or Archive the item instead.
- **See:** BMR back to **0 catalog items** and its original **4 estimates**.

---

## What I could NOT prepare you for
- **The crew view.** No `field` user exists in production, so you cannot log in as one.
  Every crew guarantee is probe-proved only. **The first real crew login is still the first
  time any of it runs outside a rolled-back transaction** — carried from A1.5's debt.
- **Live multi-user.** One browser, one session. Two people editing the same catalog item
  at once is untested.
