# THIS IS AN EVIDENCE ARCHIVE, NOT A MIGRATIONS DIRECTORY.
# Pointing `supabase/migrations/` at it is the backfill A1.0 decided against.

## Why this exists

`supabase_migrations.schema_migrations` carries a `statements text[]` column
holding the **full executed SQL** of every migration — comments, headers and
authoring rationale included. **For roughly 70 of these migrations, that column
is the only surviving copy of their source.** They have no file in
`supabase/migrations/`, they never did, and nothing else in this repository
records what they ran.

**A1.0 rewrites that table.** Rewriting it without first capturing `statements`
destroys code rather than bookkeeping — and it would be silent, because the
schema would still be there and the application would still work.

So these 107 files are that capture: one per ledger row, named
`NNN__<version>__<name>.sql`, ordered by version, extracted read-only on
2026-08-23. They are tracked in git deliberately, against `.gitignore`'s general
exclusion of `/backups/`, because they are **our own source code and contain no
user data** — only DDL, function bodies, policies and comments this team wrote.

## What NOT to do with it

- **Do not copy these into `supabase/migrations/`.** That is a backfill. A1.0's
  decided method is a **baseline reset**: pull one new baseline from the live
  schema and archive the stale files. Backfill was rejected on its own merits
  and stays rejected (see §4.7 and §4.7.2 of `docs/STRUCTTECH_OS_DIRECTIVE.md`).
- **Do not treat these as the current schema.** They are history. Several
  describe objects that were later altered or dropped — `tmp_drop_http_after_verify`
  and `drop_bmr_tickets_schema` among them.
- **Do not edit them to match today's schema.** Standing rule (§7.1 Rule 1):
  *a reconciled file records what RAN, not what the schema should say today.*
  These files are a historical record that happens to be executable. Edit them
  to reflect current truth and they stop being either.

## Provenance and integrity

- Extracted via `psql` from `supabase_migrations.schema_migrations` on
  2026-08-23. Read-only; nothing was written to the database.
- 107 files, 491,684 bytes total.
- Per-file byte counts and SHA-256 prefixes are in `../ledger_statements_index.tsv`.
- The restore of the underlying dump was **verified, not assumed** — an aggregate
  MD5 over every row's `version | name | md5(statements)` matched live exactly.
  Full method and results in `../MANIFEST.md`.

## Known limits

- These are the migrations the **ledger** recorded. **14 migrations in
  `supabase/migrations/` were applied but appear nowhere in the ledger**, so they
  are not here — the divergence runs both ways (§4.7.2).
- Replayed in order into a clean PostgreSQL 17.11, the ledger alone reaches
  64/107; with those 14 repo files merged in, 88/121. The irreducible residue is
  four tables whose `CREATE TABLE` exists in neither the repo nor the ledger:
  **`structtech_state`, `audits`, `proposals`, `prospects`**.
