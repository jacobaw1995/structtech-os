# PATH SURFACE — what RLS does **not** mediate

**Tasks:** A-PATH.0 (2026-08-30, enumeration) · **A-PATH.1 (2026-08-31, the revoke + behavioural proof)**
**Project:** `structtech` (`ejlhrykcdfcyeooooodx`) · **Server:** PostgreSQL 17.6.

> ### WHAT THIS FILE DOES NOT COVER — read this before citing it
> It covers **`public` only**, for **`anon` and `authenticated` only**, as of the date on each row.
> It does **not** cover: the other five reachable schemas (`auth`, `graphql`, `graphql_public`,
> `realtime`, `storage` — §1.1), the `service_role` / `postgres` roles (both `rolbypassrls`),
> application logic inside a correctly-granted definer RPC (§5.3), PostgREST project settings (§5.5),
> or **cross-tenant identity** — whether a caller with a valid JWT for org A can act on org B.
> That last one is the largest uncovered surface and is a separate audit, not a gap in this one.
> Full list in §5.

---

## 0 · WHY THIS FILE EXISTS

On 2026-08-29 `authenticated` was proved able to TRUNCATE 52 tables, demonstrated by destroying 948 rows
of real BMR PII with no JWT at all and restoring them. Those tables carried correct, org-scoped RLS write
policies throughout. The policies were irrelevant, because **RLS was never in the TRUNCATE path.**

> "What we have is evidence about the policies. What neither of us has is a standing instrument that would
> notice the day one changes." — Material Matrix controller, 2026-08-29

Generalised: **a policy audit only proves things about paths that RLS mediates.** This file is the
denominator — the list of paths — so that probing is done against a known surface rather than a remembered
one. It is not a findings report. Every count below is a **grant-table read**, which is a **proxy for
exercisability** (see §5).

---

## 1 · DENOMINATORS

### 1.1 · SCHEMA DENOMINATOR — measured 2026-08-31, `has_schema_privilege()`. **THERE ARE 11.**

**A-PATH.0's scope statement was wrong: it named three schemas and reasoned about eleven.** This table is
the correction. Independently reproduced against Material Matrix's own count of the same catalog.

| Schema | Owner | anon USAGE | anon CREATE | auth USAGE | auth CREATE |
|---|---|---|---|---|---|
| `auth` | supabase_admin | ✅ | ❌ | ✅ | ❌ |
| `graphql` | supabase_admin | ✅ | ❌ | ✅ | ❌ |
| `graphql_public` | supabase_admin | ✅ | ❌ | ✅ | ❌ |
| `public` | pg_database_owner | ✅ | ❌ | ✅ | ❌ |
| `realtime` | supabase_admin | ✅ | ❌ | ✅ | ❌ |
| `storage` | supabase_admin | ✅ | ❌ | ✅ | ❌ |
| `archive` | postgres | ❌ | ❌ | ❌ | ❌ |
| `extensions` | postgres | ❌ | ❌ | ❌ | ❌ |
| `pgbouncer` | pgbouncer | ❌ | ❌ | ❌ | ❌ |
| `supabase_migrations` | postgres | ❌ | ❌ | ❌ | ❌ |
| `vault` | supabase_admin | ❌ | ❌ | ❌ | ❌ |

**6 reachable, 5 not, CREATE nowhere for either role.**

> **THE SCOPE STATEMENT, IN ONE LINE.** This file covers **`public`**. It does **not** cover the other five
> reachable schemas — `auth`, `graphql`, `graphql_public`, `realtime`, `storage` — which are Supabase-managed,
> owned by `supabase_admin`, and not ours to alter (see §5.4 and the storage row in §3.1). `archive`,
> `extensions`, `pgbouncer`, `supabase_migrations` and `vault` are out of scope *because they are unreachable*,
> which is a measurement (C10, C9) rather than an assumption.

**CREATE-nowhere is load-bearing beyond schemas.** It is the reason `REFERENCES` turned out to be
unexercisable (§3, C16): a role that cannot create a table has nowhere to put a foreign key.

### 1.2 · OBJECT DENOMINATORS

**`public` holds 80 tables, not 104.** 104 is the count across `public` + `archive` + `supabase_migrations`,
and 24 of those 104 sit in schemas neither role can reach. Where a row below says "of 104" it is counting the
three-schema total; the **reachable** table denominator is **80**.

| | |
|---|---|
| Tables (`relkind='r'`) | **104** (80 in `public`, 23 in `archive`, 1 in `supabase_migrations`) |
| Views | **1** · Materialised views | **0** · Foreign tables | **0** |
| Sequences | **3** |
| Functions in `public` | **325**, of which **129** are SECURITY DEFINER |
| Schemas (non-system) | **11** total; **3** ours |
| Tables with RLS enabled | **80 of 104** (every table in `public`; the 24 without are `archive` + `schema_migrations`) |
| Tables with RLS enabled and **zero policies** | **16 of 80** |
| Tables with `FORCE ROW LEVEL SECURITY` | **0 of 104** |
| Large objects · foreign servers · FDWs · non-SELECT rules | **0 · 0 · 0 · 0** |

---

## 2 · THE PATH TABLE

`n of N` counts **objects carrying the grant**, out of the denominator for that object class.
**SOURCE** marks whether the directive named the path (`§2 Pn`) or it was derived from the catalogs (`CC-derived`).

| PATH | RLS MEDIATES? | GRANTED TO ANON | GRANTED TO AUTHENTICATED | HOW WE WOULD DETECT A REGRESSION | SOURCE |
|---|---|---|---|---|---|
| ~~**TRIGGER**~~ **CLOSED 8/31 (C13)** | **no** | 0 | **0 tables** (was 71: MM revoked their 19 on 8/30, we revoked our 52 on 8/31) · 1 of 1 view is MM's | `aclexplode` for `privilege_type='TRIGGER'`; and count `prorettype='trigger'` functions the role can EXECUTE | **CC-derived** |
| ~~**RLS on, zero policies, grant live**~~ **CLOSED 8/31 (C15)** | **no (vacuum)** | 0 of 16 | **0 of 16** (was 7; DML revoked 8/31) | `relrowsecurity AND NOT EXISTS(pg_policy) AND relacl→authenticated` | **CC-derived** |
| ~~**MAINTAIN**~~ **CLOSED 8/31 (C14)** | **no** | 0 | **0 tables** (was 52) · 1 of 1 view is MM's | `privilege_type='MAINTAIN'` | §2 P4 |
| ~~**REFERENCES**~~ **CLOSED 8/31 (C16)** | **no** | 0 | **0 tables** (was 52) · 1 of 1 view is MM's | `privilege_type='REFERENCES'` | §2 P3 |
| ~~**Sequence UPDATE**~~ **CLOSED 8/31 on our 2 (C17)** | **no** | 0 of 3 | **1 of 3** — `wh_order_number_seq`, **MM's** | `relkind='S'` + `privilege_type IN ('UPDATE','USAGE')` | §2 P2 |
| **Sequence SELECT** → `currval()` | **no** | **1 of 3 — `wh_order_number_seq`, MM's. Reported, not actioned.** | 3 of 3 | as above | §2 P2 |
| **EXECUTE on SECURITY DEFINER** — bypasses RLS by design | **no (by design)** | **2 of 129** | **126 of 129** | `prosecdef AND has_function_privilege(role,oid,'EXECUTE')` | §2 P6 |
| **`pg_default_acl`** — what the *next* object is born holding | n/a (future) | **full DML + TRUNCATE + REFERENCES + TRIGGER + MAINTAIN** on new tables in `public`; SELECT/UPDATE/USAGE on new sequences | identical | `pg_default_acl` for `defaclnamespace='public'` | §2 P8 |
| **TRUNCATE** | **no** | 0 of 104 tables · 0 of 1 view | **0 of 104 tables** · **1 of 1 view** | `privilege_type='TRUNCATE'`, **not filtered to `relkind='r'`** | §2 P1 |
| **Database `TEMPORARY`** — `CREATE TEMP TABLE` | **no** | **true** (via PUBLIC) | **true** (via PUBLIC) | `has_database_privilege(role,db,'TEMPORARY')` | **CC-derived** |
| **Views without `security_invoker`** — read as view owner | **no** | 0 of 1 | 0 of 1 | `relkind='v' AND reloptions NOT LIKE '%security_invoker=true%'` | §2 P5 |
| **Owner bypass via `FORCE RLS` off** | **no** | unreachable | unreachable | `relforcerowsecurity` + `pg_auth_members` for the owner role | §2 P10 |
| **Schema `CREATE`** — create objects you then own | **no** | 0 of 11 | 0 of 11 | `has_schema_privilege(role,s,'CREATE')` | §2 P9 |
| **Column-level grants** | partial | 0 | 0 | `pg_attribute.attacl IS NOT NULL` in our schemas | §2 P7 |
| **Triggers already installed w/ SECURITY DEFINER fns** | **no** | — | 9 of 11 triggers | `pg_trigger ⋈ pg_proc WHERE prosecdef` | §2 P11 |
| **Rules (`CREATE RULE`), non-SELECT** | **no** | 0 | 0 | `pg_rewrite WHERE ev_type <> '1'` | §2 P11 |
| **Large objects / foreign tables / FDW** | **no** | 0 | 0 | existence sweep | §2 P12 |
| **Extension surface in a reachable schema** | **no** | **188 of 190** anon-EXECUTEable fns in `public` are `btree_gist` | — | `pg_depend`→`pg_extension` + `has_function_privilege` | §2 P12 |
| **Role membership / `SET ROLE`** | **no** | none | none | `pg_auth_members WHERE member IN (anon,authenticated)` | **CC-derived** |
| **`BYPASSRLS` role attribute** | **no** | false | false | `pg_roles.rolbypassrls` | **CC-derived** |
| **`pg_parameter_acl` / `ALTER SYSTEM`** | **no** | 0 | 0 | `pg_parameter_acl` is empty | **CC-derived** |
| **Type / language `USAGE` grants** | **no** | 0 | 0 | `pg_type.typacl`, `pg_language.lanacl` | **CC-derived** |

### 2.1 · The four rows that matter, in plain words

**TRIGGER (71 of 104).** `CREATE TRIGGER` requires the TRIGGER privilege on the table — **not ownership** —
and RLS has no involvement whatsoever. The privilege alone is inert without a function to attach; it is not
inert here. `public` holds **12** trigger-returning functions, `authenticated` can EXECUTE **11** of them, and
**8** of those are SECURITY DEFINER. Neither role can create a *new* function (no schema `CREATE`, §2), so the
path is "attach an existing definer function to a table of your choosing, firing on other users' writes."
`anon` can execute **0** of the 12, so this is an `authenticated`-only path.

**RLS on / zero policies / grant live (7 of 16).** `estimate_number_counters`, `structtech_state`, and the five
`migration_bmr_*_raw` tables have RLS enabled, **no policies at all**, and `authenticated` holding
SELECT/INSERT/UPDATE/DELETE. Today a read returns zero rows. **That is Rule 11 Form 2 on `authenticated` — and
the R11 amendment says Form 2 there is usually the architecture. Here it is not.** On the other 71 tables the
barrier is an org-scoped policy that was written on purpose. On these 7 the barrier is that *nobody has written
a policy yet*. Per Rule 13 the reopening change is **"somebody adds a permissive policy"** — the ordinary way to
make a table usable — and the blast radius is the 948 rows of raw homeowner PII that 8/29 already destroyed and
restored once. **8/29 revoked the `anon` grant on these tables. It did not revoke the `authenticated` grant.**

**MAINTAIN / REFERENCES (52 of 104).** MAINTAIN postdates the advisor rule set, so no lint knows it exists. Its
risk here is **availability, not disclosure**: CLUSTER and REINDEX take ACCESS EXCLUSIVE locks, so a caller with
MAINTAIN on `deals` can lock the application out of it. That is the same *shape* as TRUNCATE — a destructive
capability the reachability lints do not measure. **REFRESH MATERIALIZED VIEW is moot: there are 0 matviews in
the entire database**, so that sub-question of §2 P4 has no object to apply to.

**`pg_default_acl` — the regression engine.** For `defaclnamespace='public'`, `defaclrole=postgres`,
`defaclobjtype='r'`, the pending grant to `anon` is **INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES,
TRIGGER, MAINTAIN** — and identically to `authenticated`. Our migrations run as `postgres`. **The next table we
create in `public` is born with the full set on both roles unless the migration revokes it.** This is CLAUDE.md
rule 8 stated as a catalog fact rather than a remembered incident, and it is mechanically why `products` came
out `anon=arwdDxtm` on 8/25. New sequences are likewise born with `anon` holding SELECT/UPDATE/USAGE — i.e.
**`setval` on any sequence created from here on.**

---

## 3 · PATHS CONFIRMED CLOSED

**This section is the point of the file.** Each row is a path a future session can re-check in one query
instead of rediscovering the question. "Closed" here means *measured closed today*, with the Rule 13 test
applied: the named reopening change is a statement about a reviewable object, not an absence.

| # | Path | Measured | Proving query |
|---|---|---|---|
| C1 | **TRUNCATE on tables** (the 8/29 control) | **0 of 104** for both roles | `select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace, lateral aclexplode(c.relacl) a where n.nspname in ('public','archive','supabase_migrations') and c.relkind='r' and a.privilege_type='TRUNCATE' and pg_get_userbyid(a.grantee) in ('anon','authenticated');` |
| C2 | **Views bypassing RLS** | 1 of 1 view is `security_invoker=true`; 0 matviews | `select relname, reloptions from pg_class c join pg_namespace n on n.oid=c.relnamespace where relkind in ('v','m') and n.nspname in ('public','archive','supabase_migrations');` |
| C3 | **Schema `CREATE`** | false for both roles on all 11 schemas | `select s, has_schema_privilege('anon',s,'CREATE'), has_schema_privilege('authenticated',s,'CREATE') from unnest(array[...]) s;` |
| C4 | **Column-level grants in our schemas** | **0**; the only 17 in the cluster are stock `pg_catalog.pg_subscription` | `select count(*) from pg_attribute at join pg_class c on c.oid=at.attrelid join pg_namespace n on n.oid=c.relnamespace where at.attacl is not null and n.nspname in ('public','archive','supabase_migrations');` |
| C5 | **Role membership / `SET ROLE` to an owner** | **0 rows** — neither role is a member of anything; `rolbypassrls=false` for both | `select * from pg_auth_members am join pg_roles r on r.oid=am.member where r.rolname in ('anon','authenticated');` |
| C6 | **`FORCE RLS` off ⇒ owner bypass** | `FORCE` off on 104 of 104, **but** owner is `postgres` on all of them and C5 proves it is unreachable | combine C5 with `select relforcerowsecurity, pg_get_userbyid(relowner) from pg_class …` |
| C7 | **Large objects, foreign tables, foreign servers, FDWs, matviews** | **0, 0, 0, 0, 0** cluster-wide | `select (select count(*) from pg_largeobject_metadata), (select count(*) from pg_class where relkind='f'), (select count(*) from pg_foreign_server), (select count(*) from pg_foreign_data_wrapper), (select count(*) from pg_class where relkind='m');` |
| C8 | **Non-SELECT rules** | **0** in `public` | `select count(*) from pg_rewrite rw join pg_class c on c.oid=rw.ev_class join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and rw.ev_type <> '1';` |
| C9 | **`http` / `pgcrypto` / `pg_stat_statements` reachability** | installed in `extensions`; **neither role holds USAGE on that schema** | `select has_schema_privilege('anon','extensions','USAGE'), has_schema_privilege('authenticated','extensions','USAGE');` |
| C10 | **`archive` + `supabase_migrations`** (23 RLS-off backup tables + `schema_migrations`) | **no USAGE on the schema AND no object grants** — closed twice over | `select has_schema_privilege('anon','archive','USAGE'), has_schema_privilege('authenticated','archive','USAGE');` |
| C11 | **SECURITY DEFINER `search_path` hijack** (chains with the live `TEMPORARY` grant) | **0 of 129** definer functions lack a pinned `search_path` | `select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and (p.proconfig is null or not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%'));` |
| C12 | **`pg_parameter_acl` / type / language grants** | **0** rows for both roles | `select count(*) from pg_parameter_acl;` + `typacl`/`lanacl` sweeps |

### 3.1 · CLOSED BY A-PATH.1, 2026-08-31 — **PROVED BY BEHAVIOUR, NOT BY DIFF**

Migration `20260831184958`, repo file md5-identical to `supabase_migrations.statements`
(`b2b504edc89425de6da077a71c024790`). Every row below was attempted **as `authenticated`** in a
**rolled-back transaction**, with **positive controls in the same transaction** so a refusal cannot be an
empty instrument: reading `deals` with a real BMR owner JWT returned **191 rows**, `estimates` **4**,
`org_members` **2**. Each refusal is graded by **message**, per rule 11, and named.

| # | Path | BEFORE (measured, not inferred) | AFTER | Rule 13: what would reopen it |
|---|---|---|---|---|
| C13 | **TRIGGER** on our 52 | `CREATE TRIGGER` on `public.products` **SUCCEEDED** — the capability was real, not merely catalog-present | `42501 permission denied for table deals` — **FORM 1 (target)** | somebody grants `authenticated` TRIGGER on the table. A statement about the table, visible in the diff. |
| C14 | **MAINTAIN** on our 52 | `ANALYZE public.deals` **SUCCEEDED** | `REINDEX TABLE public.deals` → `42501 permission denied for table deals` — **FORM 1 (target)** | as C13, for MAINTAIN |
| C15 | **The 7 N2 tables** (`estimate_number_counters`, `structtech_state`, 4 × `migration_bmr_*_raw`, `migration_bmr_id_map`) | read returned **0 rows, no error** — **FORM 2**, i.e. the grant was intact and RLS's *policy vacuum* was the only barrier | all 7 → `42501 permission denied for table <t>` — **FORM 1 (target)** | somebody grants `authenticated` the table — **no longer "somebody adds a policy"**, which was an absence with no owner |
| C16 | **REFERENCES** on our 52 | **NOT EXERCISABLE EVEN BEFORE THE REVOKE.** A temp-table FK to `public.deals` returned `42P16 constraints on temporary tables may reference only temporary tables`, and CREATE is denied on all 11 schemas — so there was nowhere to put a foreign key | grant removed regardless | somebody grants CREATE on a schema **or** REFERENCES on the table. Revoking converts an accidental closure into a reviewable one. |
| C17 | **Sequence UPDATE** on our 2 (`tg_agenda_card_id_seq`, `tg_agenda_contact_id_seq`) | — | `setval()` → `42501 permission denied for sequence` — **FORM 1**. **`nextval()` still returns a value (control: → 3): the insert path is intact.** | somebody grants UPDATE on the sequence |
| C18 | **TRUNCATE** (8/29's fix, re-proved today rather than assumed) | — | `TRUNCATE public.deals` → `42501 permission denied for table deals` — **FORM 1** | somebody grants TRUNCATE |

**What was deliberately left open, and why.** `SELECT/INSERT/UPDATE/DELETE` on the 52 are **load-bearing**;
the barrier there is **deliberately RLS** (rule 11 amendment). The 191-row control above is that design
working. Revoking them would break the product, not an attacker.

### 3.2 · TWO INSTRUMENTS THAT LIE, BOTH CAUGHT TODAY

Recorded because in both cases the *first* reading was wrong and was only caught by re-running with a control.

1. **`ANALYZE` IS AN EMPTY INSTRUMENT FOR GRADING MAINTAIN.** After the revoke landed, `ANALYZE public.deals`
   as `authenticated` **still returned success** — which read as "the revoke failed." It had not.
   `has_table_privilege('authenticated','public.deals','MAINTAIN')` was already **false**.
   **Proved on a disposable table:** with `revoke all` and *zero* privileges of any kind, `ANALYZE`
   **still succeeded**, while `REINDEX` on the same table in the same transaction returned
   `42501 permission denied`. PostgreSQL's `ANALYZE` **silently skips relations the caller cannot access**
   and reports success. **This is rule 11 Form 2 wearing a success message instead of an empty result set.**
   **Grade MAINTAIN with `REINDEX`, never with `ANALYZE` or `VACUUM`.**
2. **A PROBE OBJECT IS BORN CONTAMINATED.** The first `setval` probe created a sequence, ran
   `grant usage, select`, and concluded `setval` works without UPDATE. It does not. The probe sequence was
   **born holding `authenticated=rwU` from `pg_default_acl`** — UPDATE was already there and had never been
   withheld. **The instrument was contaminated by the exact mechanism this file documents in §2.** Re-run with
   an explicit `revoke update`, `setval` returned `42501` and `nextval` still worked.
   **Any probe on a freshly created object in `public` must explicitly revoke before it can test a denial.**

### 3.3 · MONITORED — REPORTED, NOT ACTIONED (storage; **not ours**)

`storage.objects`, `storage.buckets` and `storage.buckets_analytics` are owned by `supabase_storage_admin`.
`anon` holds **TRUNCATE** on `storage.objects` and `storage.buckets`; `authenticated` holds
INSERT/UPDATE/DELETE/TRUNCATE/TRIGGER on those and on `buckets_analytics`. **RLS is not in the TRUNCATE path.**
**We are not touching these** — a revoke risks the Storage API for both builds. Filed as a vendor report to
Supabase. The standing proving query, to be re-run and compared rather than reasoned about:

```sql
-- expect: the storage rows below are UNCHANGED. Any new row, or any row leaving, is the signal.
select c.relname, pg_get_userbyid(a.grantee) as grantee, a.privilege_type
from pg_class c join pg_namespace n on n.oid=c.relnamespace, lateral aclexplode(c.relacl) a
where n.nspname='storage'
  and pg_get_userbyid(a.grantee) in ('anon','authenticated')
  and a.privilege_type in ('TRUNCATE','TRIGGER','REFERENCES','MAINTAIN')
order by 1,2,3;
```

```sql
-- pg_default_acl: THREE grantors, only `postgres` is ours to alter. Wednesday's task; watch, do not change.
select defaclrole::regrole::text as grantor, defaclnamespace::regnamespace::text as sch,
       defaclobjtype, defaclacl::text
from pg_default_acl order by 1,2,3;
```

```sql
-- OUR standing check: these four must stay at zero for objects that are not `wh_%`.
select a.privilege_type, count(*) filter (where c.relname not like 'wh\_%') as ours_must_be_zero
from pg_class c join pg_namespace n on n.oid=c.relnamespace, lateral aclexplode(c.relacl) a
where n.nspname='public' and c.relkind in ('r','v','S')
  and pg_get_userbyid(a.grantee) in ('anon','authenticated')
  and a.privilege_type in ('TRUNCATE','REFERENCES','TRIGGER','MAINTAIN')
group by 1 order by 1;
```

**C11 is a chain, and it is the reason `TEMPORARY` is a table row rather than a closed row.** Both roles can
`CREATE TEMP TABLE` (via PUBLIC's database grant). A temp object plus a definer function with an *unpinned*
`search_path` is a classic definer hijack. The second ingredient measures **0**, so the chain is broken today —
but it is broken by a property of all 129 functions, and the reopening change is "one new definer function ships
without `set search_path`." That is exactly what CLAUDE.md rule 7 already requires, so the control has an owner.

---

## 4 · PATHS THAT CANNOT BE CHARACTERISED READ-ONLY

> **STATUS 2026-08-31 — FIVE OF SIX ROWS BELOW ARE NOW ANSWERED; SEE §3.1.**
> TRIGGER, the N2 tables, sequence `setval`, MAINTAIN and REFERENCES were all exercised as `authenticated`
> in rolled-back transactions and are closed. **Three of the five answers contradicted the guess in the row**:
> MAINTAIN could not be graded with `ANALYZE` at all (§3.2), REFERENCES turned out to be **unexercisable
> even before the revoke** (C16), and TRIGGER **actually succeeded** rather than merely appearing granted.
> **The one row still open is the last one, and one more that the exercise created:**
>
> | Still open | Why it is still open |
> |---|---|
> | **The 2 `anon` definer functions** (`create_wh_order`, `get_wh_order`) | Material Matrix's. Reported, not investigated (rule 9 refinement). |
> | **CROSS-TENANT IDENTITY** — *newly sharpened, not newly created* | All **8** `authenticated`-EXECUTEable SECURITY DEFINER trigger functions were read on 8/31. **None checks the caller's org identity inside its body**; every one derives org from the ROW, and `auto_create_deal` hardcodes it to the first `internal` org. Closing TRIGGER removes the *attach* step, but says nothing about whether a valid JWT for org A can act on org B through the RPCs. **That is a separate audit with real identities on both sides of the boundary.** |

The rows below are kept as written, as the record of what was and was not known on 2026-08-30.

| Path | What the grant read cannot tell us | What Monday must do |
|---|---|---|
| **TRIGGER** | Whether `CREATE TRIGGER` actually **succeeds** as `authenticated` against a table it does not own, and whether the attached definer function then runs with the definer's rights on another tenant's write. The privilege is present; the *end-to-end* is inference. | On a **disposable tenant**, as a real `authenticated` JWT, attempt `CREATE TRIGGER` on an org-scoped table using one of the 11 EXECUTEable trigger functions. Record the refusal form (R11). |
| **RLS-on/zero-policy tables** | Whether the empty result is truly the policy vacuum and not something else in the path. Form 2 is indistinguishable from a correctly-scoped deny without knowing the policy set. | Read as `authenticated` **with a real JWT**, confirm 0 rows, then confirm via `pg_policy` that the reason is *no policy* rather than *no match*. Do **not** add a policy to test. |
| **Sequence `setval`** | Whether `setval` on `tg_agenda_card_id_seq` actually succeeds and what an insert does afterwards. UPDATE-on-sequence is documented to permit it; documented ≠ measured. | Disposable sequence in a disposable tenant. **Never** `setval` a sequence backing a live table. |
| **MAINTAIN** | Which verbs PG17 actually admits under MAINTAIN at runtime, and whether `REINDEX`/`CLUSTER` as `authenticated` really takes the lock. The verb list is from documentation, not from a catalog — **there is no catalog that lists it.** | `ANALYZE` (cheapest, non-locking) on a disposable table as `authenticated`; escalate to `REINDEX` only on a disposable object. |
| **REFERENCES** | Whether a FK created by `authenticated` against a table it cannot read leaks key existence through constraint-violation errors. | Disposable tenant, disposable child table. Directive §5 explicitly forbade doing this today. |
| **The 2 anon definer functions** | `create_wh_order` / `get_wh_order` are **Material Matrix's**. `get_wh_order(order_number, email)` is an anonymous lookup keyed on two guessable-ish values. | **Not ours to investigate** (Rule 9 refinement: a delta in the other project's half gets *reported*, not diagnosed). Report the observation to the MM controller. |

---

## 5 · WHAT THIS ENUMERATION DOES **NOT** COVER

Stated explicitly so the file is not read as broader than it is.

1. **It is a grant-table read, which is a proxy for exercisability (R-PROXY).** 8/29 proved the two differ:
   49 tables held the full `anon` grant and were nonetheless unreadable, because a *policy helper's* EXECUTE bit
   stopped the call. A grant present here may not be exercisable; a grant absent here is genuinely absent.
   **The proxy's failure mode is over-reporting, not under-reporting** — with one exception, next item.
2. **It does not cover the `service_role` key or the `postgres` role.** Both carry `rolbypassrls=true`. They are
   out-of-band credentials, not roles reachable from a browser, and every statement above is scoped to
   `anon`/`authenticated`. A leaked service key defeats everything in this file.
3. **It does not cover application-layer logic.** A definer RPC that *is* correctly granted but checks the wrong
   org internally is invisible to every query here. §2 P6 asked "is the caller's org identity checked INSIDE the
   body" for 126 functions; that is a body-by-body read, not an enumeration, and it is not done here.
4. **It does not cover Supabase-managed schemas** (`auth`, `storage`, `realtime`, `graphql`, `vault`) beyond
   noting that both roles hold USAGE on five of them. `anon` holds TRUNCATE on `storage.buckets`,
   `storage.buckets_analytics` and `storage.objects` — **Supabase's own defaults, not ours**, listed here so the
   next reader does not meet them as a surprise.
5. **It does not cover PostgREST's own surface** — which schemas are exposed, what `db-extra-search-path` is set
   to, or whether the GraphQL endpoint is enabled. Those are project settings, not catalog state.
6. **It is a point-in-time measurement.** §2's `pg_default_acl` row is the standing reason it will drift.
7. **The advisors were not used as evidence** (R9). They were read once, at the end, for a delta record.

---

## 6 · ADVISOR CROSS-CHECK (record only, per R9)

Read once at the end. **Not evidence.** Recorded because every count reconciled against an independent catalog
measurement, which is a check on *this file*, not on the database.

| Lint | Count | Independent measurement | Agrees |
|---|---|---|---|
| `authenticated_security_definer_function_executable` | 126 | 126 of 129 | ✅ |
| `pg_graphql_authenticated_table_exposed` | 72 | 71 tables + 1 view | ✅ |
| `rls_enabled_no_policy` (INFO) | 16 | 16 of 80 | ✅ |
| `pg_graphql_anon_table_exposed` | 16 | 16 `wh_*` tables anon-SELECT | ✅ |
| `anon_security_definer_function_executable` | **2** | 2 of 129 | ✅ |
| `extension_in_public` | 1 | `btree_gist` | ✅ |
| `auth_leaked_password_protection` | 1 | project setting, unrelated | — |

`anon_security_definer_function_executable` moved **3 → 2** since 2026-08-26. The 8/26 increment was Material
Matrix's `wh_reject_retired_color_link()`; it is no longer anon-executable. **That delta is theirs, and under the
Rule 9 refinement it is reported, not investigated.** `pg_graphql_anon_table_exposed` moved **68 → 16**, which is
the 8/29 sweep landing.

**The advisors registered nothing at all about TRUNCATE, MAINTAIN, TRIGGER, REFERENCES, sequences, or
`pg_default_acl` — exactly as R9 predicted.** The eight-rule set measures *reachability*, not *capability*.
Four of the paths in §2 are invisible to it by construction.

---

## 7 · CORRECTIONS TO THE RECORD

### 7.1 · Corrections made 2026-08-31 (A-PATH.1)

- **"104 tables in `public`" is WRONG.** `public` holds **80** tables, 1 view, 3 sequences. 104 is the
  three-schema total, and 24 of the 104 are in `archive`/`supabase_migrations`, which **neither role can
  reach**. The directive for this task repeated the error; the measurement wins.
- **"`pg_default_acl` has two grantors" is WRONG — there are THREE:** `postgres` (ours, on `public` **and
  `storage`**), `supabase_admin` (on `public`, `extensions`, `graphql`, `graphql_public`, `realtime`) and
  **`supabase_auth_admin`** (on `auth`). Only `postgres` is ours to alter. Note our `postgres` grantor also
  carries a default ACL for the **`storage`** schema, not just `public`.
- **A-PATH.0's §2.1 and this task's directive both said "the five `migration_bmr_*_raw` tables."** Four are
  `_raw` (`activity`, `leads`, `notes`, `users`); the fifth is **`migration_bmr_id_map`**. The count of 5 is
  right, the name pattern is not.
- **The 71 TRIGGER grants split 19 / 52, and the 19 are gone.** Verified independently rather than taken on
  report: **zero** `wh_%` tables now carry TRIGGER (MM's `20260830165728`), and the 52 that remained were all
  ours. After `20260831184958`, ours is zero too.
- **The one object holding TRUNCATE is `public.wh_current_prices`, a Material Matrix VIEW** — so §4.5 of the
  directive resolved to *report and leave*. Likewise **`wh_order_number_seq`**, the only sequence carrying an
  `anon` grant, is MM's and is read by their SECURITY DEFINER `create_wh_order()`. Both reported, neither
  touched.
- **Rule 11 has a fourth message worth naming, on the WRITE side.** `insert into public.structtech_state`
  as `authenticated` returned `42501 new row violates row-level security policy for table "structtech_state"`
  — same SQLSTATE as Form 1, but it is **RLS refusing, not the grant**. Unlike reads (where RLS refusal is a
  silent empty set), **write-side RLS refusal is an error with a distinguishable message.** So write probes
  are gradeable by message where read probes are not.

### 7.2 · Corrections carried from A-PATH.0

- **`btree_gist` "adds operator classes only — there is no callable surface to revoke"** (directive §1,
  2026-08-21) is **wrong as written**. It contributes **188 anon-EXECUTEable functions** in `public` — 188 of the
  190 anon-executable functions there. The *conclusion* (no action owed) still looks right: they are GiST support
  routines taking `internal`-typed arguments, which PostgreSQL will not let a SQL caller invoke. But the stated
  reason was false, and "no callable surface" is not what the catalog says. **Exactly 2 non-extension functions in
  `public` are anon-executable**, and both are Material Matrix's.
- **The 8/29 TRUNCATE sweep filtered on `relkind='r'`.** `authenticated` still holds TRUNCATE on
  `public.wh_current_prices`, a **view**. `TRUNCATE` on a view is not executable, so this is hygiene rather than
  exposure — but it is the "sweep objects, not tables" lesson from the P0 addendum recurring in the very
  remediation that recorded it.
