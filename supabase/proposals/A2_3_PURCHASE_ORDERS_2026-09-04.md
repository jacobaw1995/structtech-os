# A2.3 clause (1) — PURCHASE ORDERS · **PROPOSAL, NOT APPLIED**

**Track S · 2026-09-04 · for controller review before any migration exists.**
Nothing in this file has been run. There is no ledger row and no repo migration.

**Derived from the LIVE schema**, not from the task description. Every house pattern below was read
off `pg_policies` / `pg_proc` / `information_schema` today, and the two places where the directive's
own numbers were wrong are recorded in §0.

---

## 0 · WHAT I MEASURED FIRST, INCLUDING TWO CONTRADICTIONS

| Directive said | Measured 2026-09-04 | |
|---|---|---|
| `organizations` 3, all `policy='{}'` | 3, all `{}` | ✅ |
| `work_orders` 2, both masters, 0 trades | 2, `master=2`, 0 trades | ✅ |
| `material_items` 0 | 0 | ✅ |
| `schedule_blocks` 0 | 0 | ✅ |
| **members 4**, `role='field'` 0 | **5**, `field`=0 | ❌ **WRONG** |
| last migration `20260903213105`, **pushed at `1ccd5f8`** | version ✅; last push was **`6f45019`** | ❌ **WRONG** |
| advisors 229, 0 ERROR | 229, 0 ERROR | ✅ |

**The fifth member** is a `member`-role user in **Material Matrix**, added 2026-08-28 — the same real
outsider identity the 2026-09-01 cross-tenant audit used. Its `permissions` carries **no**
`manage_catalog` and **no** `view_financials` (both null). That matters here and is not cosmetic:
**it is the only live account that fails closed**, so it is the correct negative control for every
capability probe in §6. A design validated only against four manager-tier accounts would have had
no failing case at all — §6's checks would have been unable to fail.

**House patterns this proposal must match, read from the live database:**
- `products` write policies: `TO authenticated`, `org_id IN (SELECT my_org_ids()) AND has_capability(org_id, '<key>')`.
- `products` carries one **RESTRICTIVE** policy, `ALL TO authenticated USING (can_view_financials(org_id))`.
- `material_items` policies are still scoped **`{public}`** — the old shape, part of §6.9's 109. **New policies here are `TO authenticated`** (CLAUDE.md rule 8).
- Capability keys today, all nine: `add_notes · create_estimates · edit_leads · manage_catalog · schedule · view_estimates · view_field · view_financials · view_master_work_order`.
- `organizations.tenant_type` already admits **`supplier`**, and Material Matrix is one.

---

## 1 · ROLLBACK LIST — FIRST, BEFORE THE FORWARD DDL

Reverse order of creation. Safe to run against a database where the forward DDL has been applied.

```sql
-- RPCs
drop function if exists public.list_purchase_orders(uuid, uuid);
drop function if exists public.fetch_purchase_order(uuid);
drop function if exists public.delete_purchase_order_line(uuid);
drop function if exists public.update_purchase_order_line(uuid, numeric, date);
drop function if exists public.add_purchase_order_line(uuid, uuid, numeric, date);
drop function if exists public.delete_purchase_order(uuid);
drop function if exists public.update_purchase_order(uuid, text, uuid, text);
drop function if exists public.create_purchase_order(uuid, text, uuid);
drop function if exists public.recompute_material_item_ready_by(uuid);

-- Tables, children first
drop table if exists public.purchase_order_line_promises;
drop table if exists public.purchase_order_lines;
drop table if exists public.purchase_orders;

-- The one change to an existing table
alter table public.material_items drop column if exists ready_by_source;

-- The capability key, if §4's option A is taken
-- (re-derives every org_members.permissions row from the previous default)
--   <restore prior default_permissions_for_role body verbatim from pg_get_functiondef
--    BEFORE applying — it is not reproduced here because it must be captured at apply time,
--    not written from present intent. §7.1 Rule 1.>
```

> **The last entry is deliberately a placeholder and must not be filled in from this document.**
> §7.1 Rule 1: a rollback restores **what ran**, and the body to restore is whatever
> `default_permissions_for_role` holds at apply time — which is not knowable today.

---

## 2 · THE OBJECT MODEL, DERIVED FROM THE TWO PROPERTIES

The properties, restated as the constraints they are:

> **P1 — a PO goes to ONE supplier and may cover materials across SEVERAL TRADES on ONE JOB.**
> **P2 — a MATERIAL ITEM may be SPLIT across MORE THAN ONE PO.**

P1 alone would permit `material_items.purchase_order_id` — a PO with many items. **P2 forbids it:**
one column cannot hold two POs. P1 and P2 together are a **many-to-many**, so the join is an object
in its own right and is where the per-delivery facts live.

**Three tables, and each earns its place:**

```
purchase_orders            one supplier, one job, a status          (the commitment)
  └─ purchase_order_lines  PO × material_item, with quantity        (the many-to-many, P2)
       └─ ..._promises     append-only: every promised date ever    (ruling 1's history)
```

**`quantity_ordered` lives on the LINE and is not `material_items.quantity`.** The directive is
explicit that ordered ≠ needed, and that difference is load-bearing: it is the shortfall A2.5
detects. Storing only one number destroys it. Twenty sheets now and ten next week is two lines
against one material item, each with its own promised date.

### 2.1 · Forward DDL

```sql
-- ---------------------------------------------------------------------------
-- STATUS: four values. There is deliberately NO `received`.
--
-- A2.5 OWES THE TERMINAL STATE. `received` without a receipt concept would mean
-- "somebody clicked a button" — a status naming an event this system cannot
-- observe. A PO resting at `confirmed` forever is ugly and honest, and that is
-- the better trade. CLAUDE.md rule 4 makes CHECK values expensive to change,
-- which is the reason to leave the gap rather than fill it with a guess.
-- ---------------------------------------------------------------------------
create table public.purchase_orders (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid not null references public.organizations(id),
  job_id           uuid not null references public.jobs(id) on delete cascade,
  supplier_name    text not null,
  supplier_org_id  uuid null references public.organizations(id),  -- catalog-linked; null = free text
  status           text not null default 'draft'
                     check (status in ('draft','sent','confirmed','cancelled')),
  reference        text null,          -- the supplier's own PO/quote number, free text
  notes            text null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  created_by       uuid null references auth.users(id)
);

create index purchase_orders_org_id_idx  on public.purchase_orders(org_id);
create index purchase_orders_job_id_idx  on public.purchase_orders(job_id);

comment on column public.purchase_orders.status is
  'draft | sent | confirmed | cancelled. NO `received` — A2.5 owes the terminal state; a received
   status without a receipt concept would assert an event this system cannot observe.';
comment on column public.purchase_orders.supplier_org_id is
  'Set when the supplier is a tenant in this platform (organizations.tenant_type = supplier).
   NULL is the normal case: supplier_name is free text and always authoritative for display.';

-- ---------------------------------------------------------------------------
create table public.purchase_order_lines (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid not null references public.organizations(id),
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  material_item_id  uuid not null references public.material_items(id) on delete cascade,
  quantity_ordered  numeric not null default 1 check (quantity_ordered > 0),
  promised_date     date null,          -- §2.8: a line with no promise is legal and WARNS
  actual_date       date null,          -- RULING 1: A2.5 populates this. Nothing writes it today.
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index purchase_order_lines_po_idx   on public.purchase_order_lines(purchase_order_id);
create index purchase_order_lines_item_idx on public.purchase_order_lines(material_item_id);
create index purchase_order_lines_org_idx  on public.purchase_order_lines(org_id);

-- P2 IS ENFORCED BY THE ABSENCE OF A UNIQUE CONSTRAINT, AND THAT ABSENCE IS DELIBERATE.
-- There is NO unique index on (purchase_order_id, material_item_id) and NONE on
-- material_item_id alone: both would forbid the split the property requires.
-- Recorded because an absent constraint is invisible in a diff and someone will
-- add one later believing it is hygiene (CLAUDE.md rule 13's shape).

comment on column public.purchase_order_lines.actual_date is
  'NULL until A2.5 ships. Promise-vs-actual is promise-only today; this column exists so the
   history shape already holds the actual and A2.5 adds no schema.';
comment on column public.purchase_order_lines.quantity_ordered is
  'NOT material_items.quantity. Ordered is not needed; the difference IS the shortfall A2.5
   detects, and storing one number would destroy it.';

-- ---------------------------------------------------------------------------
-- APPEND-ONLY. "This supplier has moved the date three times" is the signal a PM
-- needs, and it needs no receipt concept at all. Ruling 1.
create table public.purchase_order_line_promises (
  id                     uuid primary key default gen_random_uuid(),
  org_id                 uuid not null references public.organizations(id),
  purchase_order_line_id uuid not null references public.purchase_order_lines(id) on delete cascade,
  promised_date          date null,
  recorded_at            timestamptz not null default now(),
  recorded_by            uuid null references auth.users(id)
);
create index po_line_promises_line_idx on public.purchase_order_line_promises(purchase_order_line_id);
create index po_line_promises_org_idx  on public.purchase_order_line_promises(org_id);

-- ---------------------------------------------------------------------------
-- WHO OWNS material_items.ready_by. See §3 — this column is the whole point.
alter table public.material_items
  add column ready_by_source text not null default 'manual'
    check (ready_by_source in ('manual','purchase_order'));

comment on column public.material_items.ready_by_source is
  'Which writer last set ready_by. A2.0''s lesson as a column: two writers to one field is how two
   answers to one question arise. This records WHICH, so the fact is inspectable instead of implied.';
```

---

## 3 · THE HARD PART — `material_items.ready_by` NOW HAS TWO WRITERS

**This is the real design decision in A2.3 and I am flagging it rather than burying it.**

`ready_by` is set today by hand, through `add_material_item(p_ready_by)` /
`update_material_item(p_ready_by)`. A2.3 clause (1) says *"a PO's committed date sets
`material_items.ready_by`"* — a second writer. **Two writers to one field is precisely the shape
A2.0 spent a whole task deleting** (two capability functions answering one question differently).

Three options, and I am proposing the third:

| | Shape | Why not / why |
|---|---|---|
| A | PO promises become the sole source; retire hand entry | **Violates §2.6 and §2.8.** A user could not set a ready-by without first creating a PO. Isaac's sentence applies verbatim |
| B | Both write it, last writer wins | **This is the A2.0 defect.** Two answers, no record of which, and no way to tell a stale manual date from a fresh promise |
| **C** | **One stored fact plus `ready_by_source`; the PO path recomputes, the manual path stamps `'manual'`** | The field keeps one value; **the column records which writer produced it**, so the two can never silently disagree |

**The rule, stated so it can be argued with:**
- `add/update_material_item(p_ready_by => …)` sets `ready_by` and stamps `ready_by_source='manual'`.
- Any PO-line write recomputes `ready_by` as **`max(promised_date)`** over all lines for that item
  whose PO is **not `cancelled`**, and stamps `ready_by_source='purchase_order'`.
- **RULING 2 IS SATISFIED BY `max()`, and it agrees with the layer above by construction:**
  `add_schedule_block` already takes `max(ready_by)` across a trade's items. Latest-wins at the line
  level and latest-wins at the trade level are the same operator, so the two cannot drift.
- If every line for an item is deleted or cancelled, `ready_by` is left **as it stands** and the
  source flips to `'manual'`. **It is not nulled.** Nulling would silently unblock a schedule.

---

## 4 · RLS — EVERY POLICY, WITH THE ROLE IT APPLIES TO

All `TO authenticated` (rule 8). All three tables get `enable row level security` in the same
statement block that creates them — never retrofitted (the A2.1 pattern).

```sql
-- READ: any member of the org.
create policy "member read own purchase_orders" on public.purchase_orders
  for select to authenticated using (org_id in (select my_org_ids()));
create policy "member read own purchase_order_lines" on public.purchase_order_lines
  for select to authenticated using (org_id in (select my_org_ids()));
create policy "member read own po_line_promises" on public.purchase_order_line_promises
  for select to authenticated using (org_id in (select my_org_ids()));

-- WRITE: org + capability. INSERT/UPDATE/DELETE stated separately, never FOR ALL.
-- FOR ALL is what took the Material Matrix storefront down on 2026-08-20.
create policy "purchaser insert own purchase_orders" on public.purchase_orders
  for insert to authenticated
  with check (org_id in (select my_org_ids()) and has_capability(org_id, 'manage_purchasing'));
create policy "purchaser update own purchase_orders" on public.purchase_orders
  for update to authenticated
  using       (org_id in (select my_org_ids()) and has_capability(org_id, 'manage_purchasing'))
  with check  (org_id in (select my_org_ids()) and has_capability(org_id, 'manage_purchasing'));
create policy "purchaser delete own purchase_orders" on public.purchase_orders
  for delete to authenticated
  using (org_id in (select my_org_ids()) and has_capability(org_id, 'manage_purchasing'));
-- …the identical three on purchase_order_lines.

-- PROMISES ARE APPEND-ONLY, AND THAT IS ENFORCED BY THE ABSENCE OF POLICIES:
-- insert is granted, UPDATE and DELETE have NO policy at all, so they are refused
-- for every authenticated caller. Rule 13 asked what would reopen this: "somebody
-- adds an UPDATE policy" — which is a statement about THIS table, reviewable in the
-- diff that makes it, rather than an absence with no owner.
create policy "purchaser insert own po_line_promises" on public.purchase_order_line_promises
  for insert to authenticated
  with check (org_id in (select my_org_ids()) and has_capability(org_id, 'manage_purchasing'));
```

**NO RESTRICTIVE FINANCIAL POLICY, AND THE REASON IS THAT THERE IS NO MONEY HERE.**
§5.2 defines A2.3 as *"Supplier (free-text or catalog-linked), `committed_date`, promise-vs-actual
history, status."* **No price, no cost, no total.** So no cost column is proposed — filling that
gap in code is exactly what §0 of the directive forbids. **If the controller wants cost on a PO
line, it is one column plus one RESTRICTIVE `can_view_financials(org_id)` policy copied from
`products`, and it should be a stated decision rather than something I inferred from the word
"purchasing".**

### 4.1 · The capability key
`manage_purchasing` is a **new** key — committing money to a supplier is not the same act as
maintaining an item list, and reusing `manage_catalog` would silently grant purchasing to everyone
who can edit a product. Mapping proposed identical to `manage_catalog`: **manager tier TRUE,
`office` TRUE, everything else FALSE** — including `field`, `client_portal_viewer` and the legacy
`member`. Cost, stated plainly: it re-seeds every `org_members.permissions` row and edits
`default_permissions_for_role`, exactly as A2.1c did, and A2.0b's trigger carries it through role
changes for free. **Alternative if the controller prefers no tenth key: reuse `manage_catalog` and
accept the over-grant.** My recommendation is the new key; the decision is not mine.

---

## 5 · THE WRITE PATH

SECURITY DEFINER, `set search_path to 'public'`, called as `authenticated` — the standing pattern.
Every one closes with `revoke execute … from public, anon` (rule 7), keeping `authenticated`
because a server action **is** the call path. `recompute_material_item_ready_by(uuid)` is the one
exception: nothing outside the database calls it, so it is revoked from `authenticated` too —
rule 7's carve-out, answered per function, as `tenant_enforces_stage_gating` was yesterday.

| RPC | Notes |
|---|---|
| `create_purchase_order(p_job_id, p_supplier_name, p_supplier_org_id)` → uuid | status defaults `draft` |
| `update_purchase_order(p_po_id, p_supplier_name, p_supplier_org_id, p_status)` | jsonb-free, coalesce-patch, as `update_schedule_block` does |
| `delete_purchase_order(p_po_id)` | §2.6 |
| `add_purchase_order_line(p_po_id, p_material_item_id, p_quantity_ordered, p_promised_date)` → uuid | inserts the first promise row; recomputes `ready_by` |
| `update_purchase_order_line(p_line_id, p_quantity_ordered, p_promised_date)` | **appends a promise row only when the date actually changes**; recomputes |
| `delete_purchase_order_line(p_line_id)` | recomputes |
| `fetch_purchase_order(p_po_id)` · `list_purchase_orders(p_org_id, p_job_id)` | rule 4 of the App Router patterns: single fetch by id goes through an RPC |

**CALLERS — NAMED FROM A SEARCH, NOT FROM EXPECTATION. There are ZERO today.** `src/` contains no
reference to any purchase-order RPC, because no UI exists. The callers *will* be new server actions
in **`src/lib/coordination/actions.ts`**, which is where `add_material_item` (line 173) and
`add_schedule_block` (line 310) already live; the catalog equivalent is
`src/lib/catalog/actions.ts:54`. **Naming a caller that does not exist yet would be the same error
class as the directive's "four members".**

### 5.1 · §2.8 — where this WARNS and does not refuse
- A line with **no `promised_date`** saves. It contributes nothing to `max()`, so `ready_by` is unchanged.
- A PO with **no lines** saves. A `draft` with a supplier and nothing else is a real intermediate state.
- **Status does not enforce a state machine.** `draft → confirmed` without passing `sent` is allowed;
  so is going backwards. A PM who phoned the supplier is ahead of the software, not wrong.
- A promised date **in the past**, or **after** the trade's scheduled start, saves and surfaces the
  existing `ready_by_conflict` warning. **The only refusals are structural** — a line pointing at a
  material item in another org, a PO on a job the caller cannot see, `quantity_ordered <= 0`.

---

## 6 · PROVING QUERIES — AND WHAT WOULD HAVE MADE EACH ONE FAIL

**Every probe runs in a rolled-back transaction with a positive control in the same transaction.**
`material_items`, `schedule_blocks` and trades are all at **0 rows**, so every fixture must be
built inside the probe — and **a probe that returns zero here proves nothing unless the control
returns non-zero in the same transaction.** That is the empty-instrument rule and it applies to
literally every check below.

| # | Probe | Passes when | **What would have made it fail** |
|---|---|---|---|
| P1 | One PO, lines against material items on **two different trades** of one job | both lines insert | A `job_id`-vs-`work_order_id` anchor error, or any unique constraint on `(po, item)`. **Fails today if the PO were anchored to a trade** — which is why P1 exists |
| P2 | **Two** POs, both with a line against the **same** material item | both insert; the item shows 2 lines | Any unique index on `material_item_id`. This is the P2 property and the check that a "tidy" constraint would break |
| P3 | Two promises, `2026-10-01` and `2026-10-20` → `ready_by` | reads **2026-10-20** | `min()` instead of `max()`, or last-write-wins. Ruling 2 |
| P4 | Cancel the PO holding the later promise | `ready_by` falls back to **2026-10-01** | Forgetting the `status <> 'cancelled'` filter in the recompute |
| P5 | Move a promise 3× via `update_purchase_order_line` | promises table holds **4** rows (initial + 3) | Updating in place instead of appending — the "moved it three times" signal is the deliverable |
| P6 | Re-save a line with the **same** date | promise count **unchanged** | Appending unconditionally, which turns the history into noise and makes P5 meaningless |
| P7 | `update`/`delete` a promise row as `authenticated` | **refused, no policy** | Adding an UPDATE policy "for completeness". Read the message: a **missing-policy** refusal, not a grant refusal |
| P8 | **The 5th member** (MM `member`, no capabilities) attempts every write | all refused at RPC **and** at RLS | If it passed, `has_capability` is failing open. **This is the only live account that can fail this check** — see §0 |
| P9 | Cross-tenant: BMR caller adds a line pointing at a StructTech `material_item_id` | refused by name | Trusting `p_material_item_id` without re-deriving `org_id` from it |
| P10 | Crew (`role='field'`) reads POs | 0 rows | **CANNOT BE RUN TODAY — `field` count is 0.** A synthetic member must be created in the transaction, or this check could not have failed |
| P11 | Schedule a block before the PO-derived `ready_by` | `ready_by_conflict=true`, row **SAVED** | A2.3 clause (2) regressing; also proves the PO path feeds the gate |
| P12 | Same, with `enforce_stage_gating` on | **refused**, naming the date | The policy layer not reading the recomputed fact |
| P13 | `proacl` on all 9 new functions | no leading `=X/postgres` | Omitting the revoke — every new function in `public` is anon-executable from birth |
| P14 | Advisor delta | accounted by name | `manage_purchasing` appearing in `authenticated_security_definer_…` is expected and load-bearing; **an `anon` delta is not** |

**P10 is listed as a check that CANNOT CURRENTLY FAIL and is therefore not counted as a pass.**
It is written down precisely so it is not silently dropped, and the run must report *"13 graded, 1
ungraded, here is which"* — never 14/14.

---

## 7 · THE THREE THINGS I AM LEAST SURE OF

1. **`material_items.ready_by` having two writers (§3).** Option C keeps one value and records the
   writer, but it is still two code paths writing one field, and the `ready_by_source` column is a
   *record* of the conflict rather than a *removal* of it. A cleaner design might derive `ready_by`
   entirely and give manual entry its own column. I did not propose that because it changes a column
   `add_schedule_block` already reads, and that is a controller call, not mine.
2. **`job_id NOT NULL` on `purchase_orders`.** P1 says "on one job", so the anchor is derived. But it
   means a PO cannot be drafted before a job is chosen, and §2.8 is unforgiving about exactly that
   shape. If a PM wants to start a PO from a supplier phone call, this is wrong and the column should
   be nullable.
3. **Whether a PO carries money at all (§4).** §5.2 names no price, so I proposed none. If real POs
   carry costs — and most do — then this schema is half a table short and the RESTRICTIVE financial
   policy is missing with it. **I would rather be told than guess**, because adding a cost column
   later is cheap while getting the money-visibility gate wrong is the A2.1 crew-clause failure.

---

## 8 · NOT IN THIS PROPOSAL, ON PURPOSE

Receipts, deliveries, shortfall detection, stock (A2.4/A2.5/A2.6 — all out of A2 and unspecified);
supplier records as a first-class entity (`supplier_name` is free text plus an optional org link);
PO numbering (`reference` is the supplier's own, free text); PDF or email of a PO; any UI.
