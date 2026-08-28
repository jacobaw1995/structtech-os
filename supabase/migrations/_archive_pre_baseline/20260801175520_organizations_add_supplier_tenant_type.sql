-- StructTech OS — reconciled file for ledger row 20260801175520
-- `organizations_add_supplier_tenant_type`, applied 2026-08-01 with no repo file.
--
-- OWNERSHIP: this migration is recorded against the Material Matrix series, but it
-- alters `public.organizations` — a StructTech OS table and the root of the tenancy
-- model (§4.5, D1) — and inserts a row into it. Ownership follows the table, not the
-- author, so the file is ours. Material Matrix reviews it before it lands, because it
-- creates their org row and they are authoritative about its contents.
--
-- PROVENANCE: the body below is the EXECUTED SQL, recovered verbatim from
-- `supabase_migrations.schema_migrations.statements` (313 bytes), per §7.1 Rule 1 —
-- a reconciled file records what RAN, not what the schema should say today.
--
-- THE CHANGES ARE THE TWO IDEMPOTENCY GUARDS, AND NOTHING ELSE IS ADDED:
--   1. `if exists` on the constraint drop. The original was a bare DROP CONSTRAINT
--      and errored on statement one when replayed.
--   2. `where not exists` on the insert, KEYED ON THE LITERAL id. The original
--      INSERT was unguarded, so a replay created a SECOND 'Material Matrix' org with
--      a second id — which every org_id FK and `my_org_ids()` would then treat as a
--      distinct tenant. That is tenancy corruption, not a bookkeeping error.
-- One thing is REMOVED rather than added, and it is recorded so this header is not
-- itself a false claim: the original's trailing `RETURNING id` is gone, because
-- `insert … select … where not exists` is a different statement form from
-- `insert … values`. Nothing consumed that value — the ledger executed it as a bare
-- statement — so the removal is behaviourally inert, but it IS a divergence from the
-- executed text and is named here rather than folded into "only the guards changed."
--
-- WHY THE GUARD KEYS ON THE id AND NOT ON name + tenant_type (amended 2026-08-27,
-- on Material Matrix's review of the 2026-08-23 version, which keyed on name):
-- `name` IS MUTABLE. Material Matrix bought a domain on 2026-08-27, so a rename is
-- live rather than hypothetical. After a rename, a name-keyed guard MATCHES NOTHING
-- and silently creates the exact duplicate the guard exists to prevent — at the one
-- moment nobody is watching for it, since a guarded file reads as safe.
-- THE GENERAL RULE, because it outlives this file: SPECIFYING THE id LITERALLY
-- REPRODUCES THE ROW THAT ACTUALLY RAN. That is §7.1 Rule 1 applied to a VALUE
-- rather than to a FILE. The name-keyed version reproduces *a* Material Matrix org;
-- this one reproduces *theirs*. Only one of those is a historical record.
--
-- `created_at` IS DELIBERATELY NOT PINNED, AND THIS IS THE BOUNDARY ON RULE 1:
-- RULE 1 REPRODUCES WHAT RAN; IT DOES NOT FABRICATE A HISTORY THE REPLAY DOES NOT
-- HAVE. `created_at` is an audit field nothing references, and forcing
-- 2026-08-01 17:55:20.888922+00 into a clean restore asserts a history that restore
-- does not have. Pin identity and payload; let time be time. **ON REPLAY, THIS ROW'S
-- `created_at` WILL DIFFER FROM PRODUCTION'S, AND THAT IS INTENDED** — recorded
-- because a DOCUMENTED divergence is a fact, while an UNDOCUMENTED one trains people
-- to ignore differences. (Material Matrix's reasoning, adopted 2026-08-27.)
--
-- DELIBERATELY NOT ADDED (controller decision 2026-08-23, re-affirmed 2026-08-27):
-- no unique index, no new column, no ON CONFLICT. A unique index on
-- organizations.name would decide, inside an idempotency fix, that two tenants may
-- never share a company name — a product question on a pooled multi-tenant OS, where
-- two "Smith Construction"s in different states is not far-fetched. That question is
-- logged in the backlog as org identity (name uniqueness vs a slug/external_key) and
-- gets its own task. Material Matrix reached the same conclusion independently, from
-- tenancy-root product concerns; the controller reached it from "this does not belong
-- inside an idempotency fix."
--
-- NOT APPLIED FROM THIS FILE. The change is already live in production; this file
-- exists so the ledger row becomes addressable. Verified idempotent by running it
-- TWICE against a clean restore on local PostgreSQL 17.11 — see §10, 2026-08-27.
-- The 2026-08-23 proof does NOT carry forward: it exercised a different guard.

alter table organizations
  drop constraint if exists organizations_tenant_type_check;

alter table organizations
  add constraint organizations_tenant_type_check
  check (tenant_type in ('internal', 'contractor', 'supplier'));

insert into organizations (id, name, tenant_type)
select '1084baa8-0355-4298-9b98-b876a7581173', 'Material Matrix', 'supplier'
where not exists (
  select 1 from organizations
  where id = '1084baa8-0355-4298-9b98-b876a7581173'
);
