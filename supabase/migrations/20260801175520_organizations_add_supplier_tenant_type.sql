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
-- THE ONLY CHANGES ARE THE TWO IDEMPOTENCY GUARDS. Nothing else is added:
--   1. `if exists` on the constraint drop. The original was a bare DROP CONSTRAINT
--      and errored on statement one when replayed.
--   2. `where not exists` on the insert, keyed on name + tenant_type. The original
--      INSERT was unguarded, so a replay created a SECOND 'Material Matrix' org with
--      a second id — which every org_id FK and `my_org_ids()` would then treat as a
--      distinct tenant. That is tenancy corruption, not a bookkeeping error.
--
-- DELIBERATELY NOT ADDED (controller decision 2026-08-23): no unique index, no new
-- column, no ON CONFLICT. A unique index on organizations.name would decide, inside
-- an idempotency fix, that two tenants may never share a company name — a product
-- question on a pooled multi-tenant OS, where two "Smith Construction"s in different
-- states is not far-fetched. That question is logged in the backlog as org identity
-- (name uniqueness vs a slug/external_key) and gets its own task. Guarding the file
-- is the whole job: this is a historical record replayed only during baseline
-- verification, never an ongoing insert path.
--
-- NOT APPLIED FROM THIS FILE. The change is already live in production; this file
-- exists so the ledger row becomes addressable. Verified idempotent by running it
-- TWICE against a clean restore on local PostgreSQL 17.11 — see §10, 2026-08-23.

alter table organizations
  drop constraint if exists organizations_tenant_type_check;

alter table organizations
  add constraint organizations_tenant_type_check
  check (tenant_type in ('internal', 'contractor', 'supplier'));

insert into organizations (name, tenant_type)
select 'Material Matrix', 'supplier'
where not exists (
  select 1 from organizations
  where name = 'Material Matrix' and tenant_type = 'supplier'
);
