# A1.0 PRE-BASELINE BACKUP — taken 2026-08-23 (America/New_York), task A1.0a

**Purpose.** A1.0 rewrites the migration ledger and the repo's migration files. It does **not**
touch user data. The irreplaceable artefact is therefore
`supabase_migrations.schema_migrations` itself — and specifically its `statements` column,
which turns out to hold **the full applied SQL of every migration, comments included**.
For the ~70 migrations that have no repo file, this ledger is **the only surviving copy of
their source**. Losing it is not a bookkeeping loss; it is the loss of the code.

**Nothing here was produced by, or required, a change to the database. Read-only throughout.**

## Artefacts

| File | Bytes | SHA-256 |
|---|---|---|
| `supabase_migrations_schema_full.sql` | 518,762 | `209e89a4b22302104d89ce8f2f8aae7fb4cb85e7dc72451f9c874f10dea31914` |
| `full_schema_only.sql` | 531,055 | `fa0479536aef9508db5bcf2dec83e62f771e4f1680595bac556f77193d854acc` |
| `ledger_statements_index.tsv` | 13,695 | `f0f9748155866e1d7439d8f3a7e7f075835c52c39ec46c38a7ad07ffe9da5b5e` |
| `ledger_statements/` | 107 files, 491,684 B | per-file sha256 in the index |

1. **`supabase_migrations_schema_full.sql`** — `pg_dump --schema=supabase_migrations`.
   Schema + data. **This is the primary artefact.** 107 rows, 107 statement arrays, 491,612
   characters of SQL.
2. **`full_schema_only.sql`** — `pg_dump --schema-only` of the whole database. Structure only,
   no rows. Secondary artefact: the fallback record of what the schema looked like.
3. **`ledger_statements/`** — the `statements` column exploded to one `.sql` file per migration,
   `NNN__<version>__<name>.sql`, ordered by version. Human-readable, greppable, diffable.
   **This is an EVIDENCE ARCHIVE, NOT a migrations directory. Do not point any tool at it and
   do not move it into `supabase/migrations/` — populating that directory from these files
   would be the backfill A1.0 explicitly decided against.**
4. **`ledger_statements_index.tsv`** — filename, version__name, byte count, sha256 prefix.

## How it was produced

- `pg_dump` / `psql` **18.3** (homebrew `libpq`) against server **PostgreSQL 17.6**.
- Connection: the **Session pooler** (`aws-1-us-east-1.pooler.supabase.com:5432`, IPv4) from
  `SUPABASE_DB_URL` in `.env.local`. Direct connection remains IPv6-only and unusable (§4.7).
- **No Docker. No Supabase CLI. No linked project.** The Supabase CLI is still authenticated
  to the wrong organisation and cannot see this project; it was not needed.

## RESTORE VERIFICATION — PROVEN, NOT ASSERTED

Restore target: **local PostgreSQL 17.11** (homebrew `postgresql@17`), a scratch cluster on
port 55432. Installed for this purpose; no Docker, no paid resource, no remote resource.

**Test 1 — the ledger, into a clean database.** Restored with `ON_ERROR_STOP=1`, exit 0, zero
errors. Verified **107 rows / 107 non-null statement arrays / 107 statements / 491,612
characters** — identical to live on every figure. Then checksum-compared: an aggregate MD5 over
every row's `version | name | md5(statements)` is
**`b613dbc1b8f13af3d0b5c525dbf9cab7`** on live and **the same** on the restored copy.
**Every row round-tripped byte-for-byte.**

**Test 2 — the full schema, into a clean database.** Restores to **77 public tables / 310 public
functions / 189 public policies**, matching live exactly on all three, with a **zero-line diff**
on the full policy list. 6 errors remain, all of them the three Supabase-proprietary extensions
that do not exist outside Supabase (`http`, `pg_graphql`, `supabase_vault`). With the `anon` /
`authenticated` / `service_role` roles pre-created, the error count falls **82 → 6** and every
remaining error is one of those three. No application object fails to restore.

**A defect this test caught, recorded because it is the reason the test exists.** The first
version of the ledger dump was taken with `--table=supabase_migrations.schema_migrations`.
It restores into nothing: `pg_dump --table` does **not** emit `CREATE SCHEMA`, so the restore
died with *schema "supabase_migrations" does not exist*. That backup looked complete, had the
right byte count, and was worthless. It was replaced with `--schema=supabase_migrations` and
re-verified. **A backup nobody has restored is a belief** — this one was a wrong belief for
about seven minutes.

## Known limitation, stated plainly

**There is no verified restore of user DATA, because no user-data dump was taken.** That is
deliberate and scoped: A1.0 does not touch user data. If a future task does, it needs its own
backup and its own restore proof, and this manifest does not cover it.

## ⚠️ THIS BACKUP IS NOT COMMITTED, AND THAT IS A DECISION SOMEONE HAS TO MAKE

`.gitignore:41` excludes `/backups/` with the comment *"database backups — schema + data
dumps, never committed."* That policy is sound for data dumps. **It was written before anyone
knew that `schema_migrations.statements` holds the source code of ~70 migrations that exist
nowhere else.**

As things stand, the only protection A1.0 has against destroying that code lives on **one
laptop**, untracked, with no off-machine copy.

**Recommended, but NOT done on this task's authority, because it contradicts a written policy:**
commit `ledger_statements/` (732 KB of plain SQL text), `ledger_statements_index.tsv` and this
`MANIFEST.md`. They contain **no user data whatsoever** — only DDL, function bodies and
comments that this team wrote. Committing them is not "committing a backup"; it is putting our
own source code under version control, which is what the repo is for. The two `pg_dump` outputs
(1 MB combined) can stay ignored — they are reproducible from the live database in seconds, and
`ledger_statements/` is not reproducible once A1.0 has run.

Until that is decided, **do not run A1.0 on a machine where this directory does not exist.**
