# Pre-baseline migrations — SUPERSEDED, NOT DELETED

These 52 files were `supabase/migrations/` before A1.0 took a baseline on
**2026-08-23**. They are **superseded by `../20260823143943_baseline.sql`, not
deleted** — the baseline reproduces the schema they built, so replaying them is
neither necessary nor safe, but they remain the readable record of *how* it was
built and they stay under version control.

## Do not

- **Do not replay these.** They assume a database state that no longer exists, and
  several were never a complete history in the first place — the ledger's own
  `statements` column is the authority on what ran (directive §4.7.2).
- **Do not move them back** into `supabase/migrations/`. The CLI would try to
  reconcile them against the baseline.
- **Do not edit them to match today's schema.** Standing rule §7.1 Rule 1: *a
  reconciled file records what RAN, not what the schema should say today.*

## Two files were renamed on the way in

Both previously carried the synthetic version `20260726120000`, so they collided
with each other and replay order between them was undefined. They are now named
for the version the database actually recorded, which also restores their true
chronology — **a day apart, `fix_null_authorization_gap` first**:

| was | now | ledger-recorded time |
|---|---|---|
| `20260726120000_fix_null_authorization_gap.sql` | `20260722024727_fix_null_authorization_gap.sql` | 2026-07-22 02:47:27 |
| `20260726120000_build_tracker_module.sql` | `20260723154733_build_tracker_module.sql` | 2026-07-23 15:47:33 |

`build_tracker_module`'s header also carried a false claim — *"NOT APPLIED.
Author-only migration file"* — corrected in the same pass. It **was** applied:
the ledger row exists and `roadmap_items` holds 161 live rows.

## What these files are NOT

**They are not a complete record of what was applied to production.** Of the 107
ledger rows, only 8 match a file here by version. The rest, and the 14 files here
that the ledger never recorded, are enumerated in **`../../\_KNOWN_DIVERGENCE.md`**.
The full source of every applied migration — recovered from the ledger's
`statements` column — is in
`backups/a1_0_pre_baseline_20260823/ledger_statements/`.

**One file here is known to differ from what ran:**
`20260817151709_a1_2_creation_rpc_split_job_and_trade.sql` is missing the
`drop function if exists` guards and both `comment on function` statements that
were actually applied, because it was written from `pg_get_functiondef()` rather
than from the applied text. Restoring it from `statements` is its own task
(directive §4.7.5). The other 51 were measured and carry **zero behavioural
drift**.

*Archived 2026-08-23 by A1.0. Authority: `docs/STRUCTTECH_OS_DIRECTIVE.md` §5.1, §4.7.*
