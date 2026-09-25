# The advisor snapshot, object level

`security_snapshot.tsv` is the Supabase **security** advisor's findings at a point in time, one row per
`lint · level · schema · object`, sorted, with the total in the header. It is committed **so that tomorrow's
session can diff against an object list instead of against a number in yesterday's report.**

## Why it exists

On 2026-09-22 Track S measured 308 at session start against its own 305 at the close the night before and
**could not attribute the three**, because the only object-level snapshot lived in a session scratchpad that
is wiped between sessions. In a database taking roughly 66 migrations in nine days — about half of them
Material Matrix's, with no file we can read — an unattributable delta is the normal case, not the exception.
A count is not attribution. `authenticated_security_definer_function_executable: 184` tells you nothing about
*which* 184.

## How to regenerate it

The advisor is only reachable through the Supabase MCP tool (`get_advisors`, type `security`); there is no
SQL view for it and the Management API refuses this account (2026-09-18). So:

1. Call `get_advisors` for project `ejlhrykcdfcyeooooodx`, type `security`.
2. Flatten every `lints[].findings[]` to `lint · level · schema · metadata.name` (falling back to `detail`).
3. Sort, write with the header, commit **in the same commit as the migration that moved it**.

## What a diff of this file proves

- **That an object appeared or disappeared, by name.** "`is_qc_attester` is new" is attribution; "+2" is not.
- **Whose it is**, by the naming convention this database already enforces: `wh_*` is Material Matrix's, and
  everything else is ours. That is what makes "reported, not investigated" (CLAUDE.md rule 9) actionable —
  you can say whose half moved without reading their code.
- **That a fix landed**, when an entry you expected to remove is gone.

## What it does NOT prove

- **Not that the database is safe.** The advisor is a change detector, not a safety measure (rule 9). Zero
  movement means nobody opened a new door of the kind it watches; it says nothing about the doors already
  open, and nothing at all about the six classes it does not check.
- **Not that an entry is a defect.** Most `authenticated_security_definer_function_executable` rows are the
  application's own call path and are supposed to be there. The advisor flags a shape, not a verdict.
- **Not when something changed.** Between two snapshots, an object can appear and disappear and the diff
  shows nothing. The snapshot is only as fine-grained as its cadence — one per working session.
- **Not who changed it.** The name tells you which project by convention, not which migration. Pair a
  surprising delta with `select version, name from supabase_migrations.schema_migrations order by version desc`.
