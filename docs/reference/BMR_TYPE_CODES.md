# BMR TYPE CODES — canon

**Supplied by Jacob 2026-09-28 as standing gospel.** Source of record:
*BMR Job Numbering (Sold)* — https://app.notion.com/p/3df0e3289bba81899ff1d900e83a5c17

**This file is Jacob's, not the controller's reading of Jacob's.** Where it disagrees with
`docs/SCOPE_SHEET_SPEC.md`, this wins.

---

## The 17 codes

| Code | System / service |
|------|------------------|
| `DLSS` | Doublelock Standing Seam |
| `SLSS` | Snaplock Standing Seam |
| `TRMR` | Tough Rib Metal Roofing |
| `AARF` | Architectural Asphalt Roofing |
| `SAGU` | Seamless Aluminum Gutters |
| `MMGG` | Micro Mesh Gutter Guards |
| `MSFA` | Metal Soffit and Fascia |
| `BBMS` | Board and Batten Metal Siding |
| `SMSD` | Smart Siding |
| `TRMS` | Tough Rib Metal Siding |
| `CCAR` | Custom Carpentry |
| `CFAD` | Custom Framing/Addition |
| `ASRS` | Aluminum Snow Rail System |
| `SKYL` | Skylight Installation |
| `CHFL` | Chimney Flashing/Modification |
| `GRRP` | General Roof Repair |
| `CRPJ` | Custom Roof Project |

## Job number format

```
MM-YY-###-LastName-TYPE-##
01-26-001-Baker-DLSS-01
```

**Assigned when SOLD.** The job scope sheet is pre-sale and pre-price, so a scope sheet carries
a TYPE selection but not a job number.

---

## What these codes ARE, and the distinction that matters

**They name what BMR SELLS AND INSTALLS.** They are the system going on the building. They live
in `tenant_modules.config` beside the existing field definitions.

**THEY ARE NOT PRODUCTS.** They do not touch `products` or any `wh_*` table. Catalog and
Material Matrix remain out of this build.

**THEY ARE NOT THE SAME AXIS AS `roof_type_requested`.** Measured 2026-09-28 by Track S: the live
config carries **14 roof types**; this list holds **17 system codes**. *"Not a rename, not a
superset — two vocabularies."* A sales-stage roof type describes what a homeowner asked for in a
homeowner's words; a TYPE code is what was sold, coded, and becomes part of an identifier.

**THE OPEN QUESTION, narrowed and still Jacob's:** when a job is sold, does the TYPE code
REPLACE the requested roof type, or do both persist — one recording what was asked for, one
recording what was sold? **Two facts or one field.** This build has ruled the same shape four
times (`ready_by` vs the PO promise, the human-typed vs system-derived value, first vs latest
attestation) and every time the answer was *two facts*. **That precedent is not a ruling here and
must not be treated as one** — a job with one trade may genuinely collapse them, and only Jacob
knows whether "they asked for standing seam and bought Doublelock" is a distinction BMR needs.

**VERIFIED AGAINST THE PDF, Track S 2026-09-28:** all seventeen codes and all seventeen labels
match page 2 of `BMR_Job_Scope_Initial_Inspection.pdf` exactly — 6 + 6 + 5 across its three
columns. Nothing added, nothing renamed, nothing missing.

**A job can carry MORE THAN ONE TYPE.** The format's trailing `-##` and the scope sheet's own
structure — roof, soffit and fascia, siding, gutters, snow rail, other, each independently gated
— say a single job routinely sells several systems. **Any model that assumes one code per job is
wrong before it is built.**

**AND A QUESTION UNDER THAT ONE, raised by Track S rather than settled** — because the shape
differs and the canon says the shape is the executor's to derive. The PDF's own sentence is
*"TYPE is the panel system checked in **3A Roof details** — one of the 17 locked codes"*:
**singular, and sourced from one section.** So the trailing `-##` has two readings, and they
produce different models:

- **(a) one job, several codes**, `-##` distinguishing them → a set of codes on the job.
- **(b) one job NUMBER per sold system**, `-##` a sequence within the job → a child row per
  system, each with its own number.

**The canon's conclusion holds either way** — a model with one code per job is wrong under both.
What differs is whether the second system gets a *column* or a *row*, and that is worth one
sentence from Jacob before anything is built. **For the SCOPE SHEET the uncertainty does not
bite**: six independently gated sections each select their own code regardless. It bites at the
job number, which is assigned later and is not this build.
