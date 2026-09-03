# CROSS-TENANT ISOLATION ON `authenticated`

**Task:** A-PATH.2 · **Date:** Tuesday 2026-09-01 (America/New_York)
**Project:** `structtech` (`ejlhrykcdfcyeooooodx`) · **Server:** PostgreSQL 17.6
**Companion:** `docs/PATH_SURFACE.md` (A-PATH.0/.1). That file covers paths RLS does **not** mediate.
This one covers the path it **does** — and asks whether it mediates it *correctly across a tenant boundary*.

> ### WHAT THIS AUDIT DOES NOT COVER — read before citing it
> §7 is the full list. The four that matter most:
> **(1)** It measures the **database's** enforcement. Identity was asserted with `set local role authenticated`
> + `set_config('request.jwt.claims', …)`, which is what `auth.uid()` actually reads. It therefore says
> **nothing about PostgREST's JWT signature verification**, which is the layer above and was not exercised.
> **(2)** **15 of our 52 tables hold zero rows.** A cross-tenant zero on those is an empty instrument and is
> reported as UNTESTED, not as a pass.
> **(3)** It is `public` only, `authenticated` only, and it does **not** re-test the grant layer — that was
> A-PATH.1's subject and was deliberately not touched today.
> **(4)** It tests the **gates**. It does not test BMR's actual configuration, and it is **not** the §8
> crew-login risk closing.

---

## 0 · HEADLINE

**Table-level RLS holds across the tenant boundary. The SECURITY DEFINER RPC surface does not, in five
places, and one of them chains to real lead PII.**

| | |
|---|---|
| Tables probed | **52 of 52**, four operations, three identities, all in rolled-back transactions |
| Cross-tenant SELECT | **0 leaks.** 27 meaningful passes (positive control in the same transaction), 7 grant-refused, 3 own-org-only, 15 untestable |
| Cross-tenant INSERT | **0 accepted.** 44 `RLS-REFUSED`, 7 `FORM1-grant`, 1 re-probed |
| Cross-tenant UPDATE / DELETE | **0 rows reached.** The one non-zero was the outsider's own `profiles` row |
| SECURITY DEFINER RPCs | **114 in scope · 106 constrain · 8 do not · 8 probed** |
| **Confirmed cross-tenant reads through definer RPCs** | **5** — `crm_stage_config`, `crm_stage_entry`, `crm_follow_up_cadence_days`, `tracker_status_config`, `tracker_type_config` |
| **Confirmed unauthenticated-in-effect write + read chain** | **1** — `generate_roadmap_for_lead` → `fetch_roadmap_by_token` |
| **Privilege escalation, second role vocabulary** | **1** — any user can self-promote `profiles.role` to `manager` |

---

## 1 · THE WEDNESDAY GATE (§1) — READ-ONLY, FOR MATERIAL MATRIX

### 1.1 · The fraction

> **1 of 20 StructTech-OS table-creating migrations grants explicitly. 19 rely on the `pg_default_acl`
> default.**

**The container, stated because a count without one is not a fact (R-SCOPE):** the union of
`supabase/migrations/` (including `_archive_pre_baseline/`) and `supabase_migrations.schema_migrations`,
restricted to **StructTech OS** rows — excluding `wh_*` (Material Matrix), `tg_agenda_*` and `bmr_ticket*` —
counting a migration once if it issues at least one `CREATE TABLE … (` in `public`, and asking per created
table whether the *same* migration issues a `GRANT … ON <that table> TO authenticated` (and/or `service_role`).

| Sub-container | Table-creating migrations | Explicit grant | Rely on default |
|---|---|---|---|
| Ledger (`schema_migrations`), StructTech-OS rows | 16 | **1** | 15 |
| Repo `_archive_pre_baseline/`, **not in the ledger under any name** | 4 | **0** | 4 |
| Repo post-baseline (19 files) | 1 | **1** | 0 |
| **Union, de-duplicated** (7 archive files re-appear in the ledger; the post-baseline one is the same `a2_1`) | **20** | **1** | **19** |

The single explicit grantor is **`20260825125737_a2_1_tenant_product_catalog`** → `public.products`. That is
the migration written the day after CLAUDE.md rule 8 was learned, and it is the only one.

**Do not read the 16 against Material Matrix's 16.** MM counted their own corpus in their own container; ours
happens to land on the same ledger sub-total by coincidence and on **20** in the union. The comparable
statement is the *shape*, not the number: **both builds create tables into the default and almost never grant
explicitly**, so the Wednesday `ALTER DEFAULT PRIVILEGES` lands on two codebases with the same exposure.

### 1.2 · The finding §1 did not ask for, and it is larger than the fraction

**`supabase/migrations/20260823143943_baseline.sql` is a `pg_dump … WITH privileges` taken on 2026-08-23. It
hard-codes `GRANT ALL ON TABLE public.<t> TO anon;` for 71 tables — `deals`, `estimates`, `organizations`,
`audit_leads`, `client_roadmaps` among them.**

That file is **immune to Wednesday's change** — it grants explicitly, so a default-privilege revoke cannot
affect it. That is the good half. The bad half is that **it is now eight days stale, and replaying it would
re-grant every privilege that 8/29 and 8/31 removed**: the 49-table anon sweep, the TRUNCATE revoke, and
A-PATH.1's TRIGGER/MAINTAIN/REFERENCES closures. It is §7.1 RULE 1 working exactly as written — the file
records what ran on 8/23 — and simultaneously a live restore hazard, because nothing in the repo says so.

**Not fixed today** (§6 permits one migration and this is not it). Filed. The cheap fix is a comment header in
the baseline plus a follow-on file; the correct fix is to re-take the baseline after Wednesday lands.

### 1.3 · What role does the Supabase SQL Editor run as?

**Measured, for the transport it uses:** the Management API connection to this database authenticates as
**`postgres`**, `session_user = postgres`, `role` setting `none`. Confirmed twice — directly
(`select current_user, session_user`) and independently in `pg_stat_activity`, where that backend appears as
`usename = postgres, application_name = mgmt-api`.

**The honest boundary:** the dashboard SQL Editor posts to that same Management API endpoint, so this is
strong evidence rather than an assumption — but I could not press the button myself, and a newer read-only
toggle in the editor is documented to use a *different* role. So it is **measured for the mgmt-api path,
inferred for the button.** One query in the editor settles it:

```bash
echo "select current_user, session_user, current_setting('role') as role_setting;"
```

Until it is run, treat "the SQL Editor is `postgres`" as **very likely, not established.** It matters: if it
is anything other than `postgres`, Wednesday's `ALTER DEFAULT PRIVILEGES` on the `postgres → public` entry
misses everything created through that window — and reports success (this is directive §7.1 RULE 6's reason).

---

## 2 · THE ROLE DENOMINATOR (§2.1) — **IT IS CLOSED, AND THERE ARE TWO OF THEM**

**The directive asked for "the role denominator." There is no such thing in this schema. There are two
disjoint, simultaneously live role vocabularies, and every matrix in this file is built against the first.**

### 2.1 · Vocabulary A — `org_members.role`. The tenancy axis. **7 values.**

From `org_members_role_check`, verbatim:

`owner` · `admin` · `office` · `field` · `client_portal_viewer` · `agency_admin` · `member`

**In use today (5 rows in 3 orgs):** `owner` ×3, `agency_admin` ×1, `member` ×1. Four of the seven have never
been issued to anyone.

### 2.2 · Vocabulary B — `profiles.role`, type `pipeline_user_role`. The legacy pipeline axis. **2 values.**

`salesman` · `manager`. Column is `NOT NULL DEFAULT 'salesman'`. **In use: `manager` ×2, `salesman` ×2.**

These two vocabularies share no values, sit on different tables, and are read by different helpers —
`my_org_ids()`/`is_org_manager()`/`has_capability()`/`is_platform_admin()` read A; `is_pipeline_manager()`
and `is_pipeline_user()` read B. **A user is simultaneously a member of both.**

### 2.3 · Do the CHECK and the CASE agree? **Yes on outcome. No on explicitness, and the gap is open-by-default.**

`default_permissions_for_role(text)` names 6 of the 7 CHECK values explicitly — `owner`/`admin`/`agency_admin`
in one branch, `field`/`client_portal_viewer` in another, `office` in a third — and handles the seventh
(`member`) through an `else` branch whose own comment reads "`member` and anything future."

**So there is no unhandled role, and this is not a finding in the sense the directive anticipated.** But the
`else` branch is the *permissive* one — it returns `view_financials: true` and `view_master_work_order: true`.
Under Rule 13, the change that opens it is **"somebody adds a value to the CHECK constraint"**, and that
person gets financial visibility by default without touching the permissions function. Recommend the `else`
branch deny rather than permit, and `member` be named explicitly. **Not changed today.**

---

## 3 · THE IDENTITIES (§2.2–2.3)

### 3.1 · DEVIATION: no disposable tenant was created. A real second-org identity already existed.

**§2.3 assumed our mirror of Material Matrix's method was unavailable. It was not.**
`c62adbfc-6af2-436f-bb68-55266fef3804` is a **real, live auth user**, a `member` of the **Material Matrix**
org (`1084baa8-…`), with **no StructTech membership and no BMR membership**. That is the exact mirror of what
MM did with our BMR owner — a real person's real identity, outside the tenant under test.

**Using it is strictly better than the fixture the directive specified**, on the directive's own rules:

- **R-CONTAMINATION.** A disposable tenant is a fixture created inside the test and therefore born holding
  every ambient default. This identity was not created by me and inherits nothing from my transaction.
- **§2.3(a).** No `public.profiles` row was minted, so **there is no side effect for Material Matrix to
  find.** The `on_auth_user_created → handle_new_user` trigger was never fired.
- **§2.3(b).** Nothing was created, so the first `internal` organisation cannot have moved. **Verified anyway:
  the first `internal` org is StructTech (`034db6f4-…`, created 2026-07-11), unchanged.**

**Its starting state was asserted by measurement, not assumed** (R-CONTAMINATION): inside the probe
transaction, `auth.uid()` = `c62adbfc-…`, `my_org_ids()` = `{1084baa8-…}` and nothing else,
`org_members.role` = `member`, `profiles.role` = `salesman`.

### 3.2 · The four identities and what each proves

| Identity | Constructed how | What it proves | What it cannot prove |
|---|---|---|---|
| **OUTSIDER** — MM member `c62adbfc` | real user, real membership | the subject of the audit: a valid signed-in caller from another tenant | anything about a caller with no membership anywhere |
| **INSIDER** — BMR owner `d63871d2` (Isaac) | real user, real membership | **the positive control.** `deals` = 191, same figure as 8/31 | anything about StructTech-org-owned tables, where he correctly sees zero |
| **UNIVERSAL INSIDER** — `09a25143` (Jacob) | real user, member of all 3 orgs | the positive control on the tables the BMR owner cannot reach; **this is what lifted the controlled count from 19 to 27** | — |
| **FLOOR** — `authenticated`, no claims | `request.jwt.claims` empty | only that RLS refuses an identity-less caller. **The directive is right that we already knew this** | it is not an outsider and was not treated as one |

**The instrument's limit, stated plainly:** none of these is a *signed* JWT. Without the project JWT secret I
cannot mint one, and PostgREST — not Postgres — is what verifies signatures. Inside the database, identity
**is** `request.jwt.claims`, so this is the faithful instrument for everything below the API. It is the same
instrument A-PATH.1 used to measure 191 deals.

---

## 4 · THE PROBE MATRIX (§3)

**Denominator: 52 tables** — every `relkind='r'` in `public` that is not `wh_*` (Material Matrix, 22 + 1 view)
and not `tg_agenda_*` (6). **52 + 22 + 6 = 80 tables + 1 view = 81 relations.**

> **CORRECTION TO THE DIRECTIVE (§3).** "80 in `public` — 52 ours, 27 neither, 1 MM view" undercounts by one.
> It is **52 ours, 28 neither** (22 `wh_*` + 6 `tg_agenda_*`), **plus** the MM view — 80 tables, 81 relations.
> Note the `tg_agenda_*` six are counted as "neither" here to stay consistent with the 52, even though
> A-PATH.1 called their two sequences "our 2." Both usages are defensible; the inconsistency is ours and is
> recorded rather than silently resolved.

Every probe ran inside a transaction that was **ROLLED BACK**, with a positive control **in the same
transaction**. No exceptions.

### 4.1 · SELECT — 52 of 52 accounted for

| Outcome | n | Meaning |
|---|---|---|
| **PASS, with positive control** | **27** | table has rows · the universal insider sees rows · the outsider sees **zero** |
| **FORM 1 (grant), target** | **7** | `42501 permission denied for table <t>` — the N2 set, closed by A-PATH.1's revoke, not by RLS. Stronger than a pass |
| **Outsider saw rows — own org only** | **3** | `org_members` 2 of 5 · `organizations` 1 of 3 · `profiles` 2 of 4 |
| **UNTESTED — empty instrument** | **15** | the table holds **zero rows**. A cross-tenant zero here proves nothing and is not scored |
| | **52** | |

**The 3 that returned rows are not leaks, and this was verified by expression rather than by inference.** The
fractions are the first tell — 2 of 5, 1 of 3, 2 of 4 is partial visibility, not a bypass. `profiles` is
governed by `profiles_select_self_or_org`: `(id = auth.uid()) OR (id IN (SELECT om.user_id FROM org_members
om WHERE om.org_id IN (SELECT my_org_ids())))` — self, or someone who shares an org with you. The outsider saw
themselves and **Jacob Walker, who is the owner of their own Material Matrix org.** They did **not** see Isaac.
Correct behaviour.

**The 15 untestable tables are the most important row in this table**, and they are exactly the failure mode
Material Matrix lost six tables to. `52 − 37 non-empty = 15`. **No cross-tenant claim in this document applies
to any of them.** They are, in full:

> `audits` · `check_ins` · `lead_activity` · `lead_appointments` · `lead_notes` · `leads` · `material_items` ·
> `production_packets` · `products` · `proposals` · `schedule_blocks` · `ticket_messages` · `tickets` ·
> `work_order_activity` · `work_order_agreements`

Note what is in that list: **the entire `field` module** (`check_ins`, `production_packets`,
`schedule_blocks`), **the whole coordination tail** (`material_items`, `work_order_activity`,
`work_order_agreements`), **the tenant catalog** (`products`), and **the whole legacy lead funnel**
(`leads`, `lead_activity`, `lead_notes`, `lead_appointments`). Those are precisely the surfaces §5's Tier A
gates protect, and precisely the ones this audit could not exercise. **The next cross-tenant probe should be
run the week `check_ins` and `material_items` first carry production rows, not on a calendar.**

### 4.2 · INSERT — the gradeable write, 52 of 52

Constructed per table by filling every `NOT NULL`-without-default column with a type-appropriate value and
setting `org_id`, where the column exists, to **BMR's org id** — i.e. deliberately forging a row into the
victim tenant.

| Outcome | n |
|---|---|
| `42501 new row violates row-level security policy` — **RLS refused** | **44** |
| **FORM 1 (grant)** — `permission denied for table` | **7** |
| Re-probed separately (`lead_activity`, see below) | **1** |
| **ACCEPTED** | **0** |

**The positive control is what makes the 44 mean something.** In the same transaction, the *insider* running
the identical generated statements **succeeded on 4 tables** (`products`, `roadmap_projects`, `tickets`,
`tracker_projects`). The instrument can insert. It was refused.

**`lead_activity` was an instrument failure, not a result, and is recorded as such.** The generator emitted a
text literal for a `lead_activity_action` enum → `22P02`. Re-probed with a valid enum value, it returned
`42703 column "org_id" of relation "lead_activity" does not exist` — a second instrument failure, and one that
turned into the finding in §4.5.

### 4.3 · UPDATE and DELETE — 52 of 52 each

| Op | ZERO-ROWS | FORM 1 (grant) | ROWS REACHED |
|---|---|---|---|
| UPDATE (no-op self-assignment of the PK) | 44 | 7 | **1** — `profiles`, the outsider's **own** row |
| DELETE (unqualified, rolled back) | 45 | 7 | **0** |

**Controls, same transaction:** the insider's UPDATE matched rows on **13** tables including `deals` (191),
and the insider's DELETE removed rows from **2** before rollback. The instrument can update and can delete.
Against the outsider it reached nothing.

**One of those two DELETE controls is contaminated and is discounted.** The probe ran INSERT → UPDATE →
DELETE per table in sequence, so on `products` — which holds **zero** production rows — the insider deleted
the row its own INSERT had just created two statements earlier. **That is R-CONTAMINATION inside my own
control:** a fixture created by the test being counted as evidence about the database. The DELETE control
therefore rests on **`estimate_line_items` alone**, where the insider's INSERT was refused by a foreign key
and the 21 rows deleted were real production rows. One clean control is enough to say the instrument deletes;
two would have been better, and I am reporting one.

### 4.4 · FINDING — self-promotion in role vocabulary B

The one non-zero outsider write led somewhere. `pipeline_profiles_update_own` is
`FOR UPDATE TO authenticated USING (id = auth.uid())` with **no column restriction**, and `profiles.role` is
an ordinary writable column.

**Proved end-to-end, one rolled-back transaction:**

```
0. role before                 salesman
0. is_pipeline_manager before  false
1. self-promote to manager     ROWS=1
2. role after                  manager
2. is_pipeline_manager after   true
3. steal another user's id     REFUSED  42501 new row violates row-level security policy
4. edit someone else's profile ZERO-ROWS
5. deals visible after         0
5. leads visible after         0
```

**Any authenticated user can make `is_pipeline_manager()` return true for themselves.** They cannot take
another user's identity and they cannot edit anyone else's row — both refused, both shown above.

**Blast radius today: zero, and the zero was measured, not assumed.** `is_pipeline_manager()` and
`is_pipeline_user()` are referenced by **0 policies** and by **0 other functions** in `public`, and `src/`
never reads `profiles` outside generated types. Steps 5 above confirm behaviourally that promotion opened
nothing.

**Under Rule 13 this is NOT CLOSED.** The change that opens it is *"somebody writes a policy or an RPC that
trusts `profiles.role`"* — an absence standing in for a control, with no owner, no review and no alarm. That
is the same shape as the 49 tables on 8/29. **The remedy is one line** (a `WITH CHECK` that pins
`role = (select role from profiles where id = auth.uid())`, or moving `role` off the self-writable set), and
it is **not applied today** because §6 permits one migration and this is not it. Filed as P0 for the next
migration window.

### 4.5 · STRUCTURAL FINDING — 19 of our 52 tables have no `org_id` column at all

CLAUDE.md states "**Every domain table carries `org_id`.**" Measured, it is 33 of 52.

The 19 without: `audits` · `lead_activity` · `lead_appointments` · `lead_notes` · `leads` · the 5
`migration_bmr_*` · `organizations` · `pipeline_invites` · `profiles` · `proposals` · `prospects` ·
`staff_invites` · `staff_users` · `structtech_state` · `ticket_messages`.

Several are legitimate (`organizations` *is* the org; `profiles` is co-membership-scoped and verified above;
`ticket_messages` scopes through its ticket). The `leads`/`lead_*`/`pipeline_invites` family is the legacy
pipeline schema scoped on **role vocabulary B** rather than on org — which is why §4.4 and this row are the
same finding seen from two directions. **All 19 returned zero to the outsider**; **9 of them are in the
untestable-15**, so for those the zero is not evidence.

---

## 5 · THE DEFINER RPC SURFACE (§4) — WHERE THE BOUNDARY ACTUALLY FAILS

### 5.1 · The split

`public` holds **130** SECURITY DEFINER functions; **127** are `authenticated`-EXECUTEable.

> **CORRECTION TO THE DIRECTIVE (§4).** It carried 129/126 from 8/30. Measured today: **130/127.**
> The +1 is **`wh_set_unit_size`**, Material Matrix's, ledger row `20260831185218`, applied 8/31 after
> `PATH_SURFACE.md` §6 was written. **Reported to MM, not investigated** (R9 refinement).

Scope for the body-by-body read: 127 minus 9 trigger-returning functions minus MM's 4 remaining `wh_*`/
`get_wh_order` = **114 ours**.

| Tier | n | What it means |
|---|---|---|
| **A — constrains on a caller-derived org** | **96** | body calls `my_org_ids()`, `is_org_manager(p_org_id)`, `has_capability(p_org_id, …)`, `is_platform_admin()` or `assert_work_order_level()` |
| **B — self-scoped by construction** | **10** | no org parameter; everything derives from `auth.uid()` — the six `my_*` metrics, three `accept_*_invite`, `fetch_membership_context()` |
| **C — reaches no caller identity at all** | **8** | **the subject of the probes below** |
| | **114** | |

**Of the 23 functions taking an org/tenant parameter, 18 constrain on it** — the `is_org_manager()` shape,
verified line by line (`if p_org_id not in (select my_org_ids()) then raise exception 'not a member of
organization %'`). **Five do not.** Those five are Tier C.

**A note on method, because the first classifier was wrong.** A regex for `my_org_ids|auth.uid()` reported
**27** unconstrained functions. Reading them showed 15 constrain **transitively** through
`assert_work_order_level(work_order_id, kind)` — which does check `v_org_id not in (select my_org_ids())` —
and 3 through `is_platform_admin()`. **The mechanical test over-reported by more than 3×.** The tiering above
is a transitive closure plus a body-by-body read of every Tier B and C function.

### 5.2 · The 8, probed — all with `select count(*) from deals` = 0 as the control in the same transaction

| Function | Constrains? | Probe result as the OUTSIDER |
|---|---|---|
| `crm_stage_config(p_org_id)` | **no** — accepts any org | **RETURNED BMR's full pipeline stage configuration** |
| `crm_stage_entry(p_org_id, p_stage_key)` | **no** | **RETURNED** `{"key":"new_lead","label":"New Lead","outcome":null,"cancel_pending_follow_ups":false}` |
| `crm_follow_up_cadence_days(p_org_id)` | **no** | **RETURNED `{2,5}`** — and this is real config, see the caveat below |
| `tracker_status_config(p_org_id)` | **no** | **RETURNED StructTech's internal tracker status set** |
| `tracker_type_config(p_org_id)` | **no** | **RETURNED StructTech's internal tracker type set** |
| `generate_roadmap_for_lead(p_lead_id)` | **no** | **SUCCEEDED — minted a 32-char token for someone else's lead** |
| `create_engagement_from_roadmap(p_deal_id)` | **no** | refused — `P0001 no roadmap found for deal …`. **A data-shape refusal, not an authorisation one. Inconclusive; the function checks nothing** |
| `fetch_roadmap_by_token(p_token)` | n/a — token-scoped **by design** | see the chain below |

**Two probes were graded twice, and the first grade was wrong both times.**

1. **`crm_stage_entry` first returned `null`** and read as a refusal. It was not — I had passed
   `'lead_captured'`, and BMR's stage key is `'new_lead'`. **A wrong key produces the same null as a denial.**
   Re-run with the real key, it returned the row.
2. **`crm_follow_up_cadence_days` returned `{2,5}`, which is also the function's hardcoded fallback.** That
   probe proved nothing until the ground truth was checked: BMR's `tenant_modules.config` **does** carry
   `follow_up_cadence_days`, so the array is real configuration and the disclosure is real. Had it not, this
   row would read "inconclusive."

Both are R-EMPTY-INSTRUMENT: *before trusting a probe that passes, ask whether it could have failed.*

### 5.3 · THE CHAIN — the one finding with PII behind it

Run as the outsider, in one rolled-back transaction, with **both** controls showing zero:

```
CONTROL: outsider select on deals          0
CONTROL: outsider select on audit_leads    0     <- cannot read the leads table at all
generate_roadmap_for_lead(<real lead id>)  SUCCEEDED, token length 32
fetch_roadmap_by_token(<that token>)       FULL LEAD RECORD RETURNED
```

**A caller who cannot read one row of `audit_leads` wrote a `client_roadmaps` row for a real lead and read
the lead's record straight back** — name, company, trade, crew size, score, risk level, monthly revenue leak.
`generate_roadmap_for_lead` performs **no caller check of any kind**: it takes a lead id, reads the lead,
builds the roadmap and returns the token.

**The only thing standing in the way is knowledge of an `audit_leads.id` (a v4 UUID), which is not guessable
and which the outsider provably cannot enumerate through the table.** So this is **not** a live data breach.
It is an **authorisation check that does not exist**, sitting behind a secret that was never designed to be
one — and `client_roadmaps` tokens were already "treated as disclosed" once, on 8/28
(`20260828170627`). Any path that has ever emitted a lead id — a URL, a webhook payload, a log, a support
thread — is sufficient.

**Severity ranking of the six confirmed RPC findings:** the chain first (PII, plus an unauthorised write into
`client_roadmaps`); the five config readers second (per-tenant configuration disclosure — a competitor's
pipeline stages and follow-up cadence; no PII).

**Nothing was fixed.** §6 permits one migration and it is the documentation rule. All six are filed.

### 5.4 · What §4 asked for and what it got

- **Read in full:** all 114 in-scope function bodies were classified; every Tier B and Tier C body was read
  in full text; the 18 org-parameterised Tier A gates were read as source lines, quoted above.
- **Probed:** **8 of 8** Tier C functions — every function whose body does not constrain on a caller-derived
  org. The directive asked for "the ones whose body does not constrain"; that set turned out to be 8, not the
  126 it feared, so it was probed exhaustively rather than sampled.
- **Not probed:** the 96 Tier A and 10 Tier B functions, on the grounds that their gate was read and is the
  `is_org_manager()` shape. **That is a read, not a measurement, and it is the largest untested surface in
  this document.**

---

## 6 · ADVISORS — RECORD ONLY (R9)

Read once, at the end. **Not evidence.** **228 lints / 7 rules** (was 234 / 7 on 8/31).

| Lint | 8/31 | 9/01 | Δ | Whose, and accounted for how |
|---|---|---|---|---|
| `authenticated_security_definer_function_executable` | 126 | **127** | **+1** | **Material Matrix's** — `wh_set_unit_size`, ledger `20260831185218`. Reported, not investigated |
| `pg_graphql_authenticated_table_exposed` | 72 | **65** | **−7** | **Ours** — A-PATH.1's `20260831184958` landing. Reconciled independently: 64 tables now carry `authenticated` DML, + MM's `wh_current_prices` view = 65 ✅ |
| `rls_enabled_no_policy` (INFO) | 16 | 16 | 0 | — |
| `pg_graphql_anon_table_exposed` | 16 | 16 | 0 | all 16 Material Matrix's |
| `anon_security_definer_function_executable` | 2 | **2** | 0 | both Material Matrix's; **ours is zero** |
| `extension_in_public` · `auth_leaked_password_protection` | 1 · 1 | 1 · 1 | 0 | — |

> **CORRECTION TO YESTERDAY'S RECORD.** `PATH_SURFACE.md` §6 presents 72 as an end-of-day reading taken after
> the migration. It cannot have been: the migration removed `authenticated` DML from exactly 7 tables and the
> lint is now 65. **The 72 was a pre-migration read presented as a post-migration one.** The −7 is ours,
> expected, and reconciles to the catalog — but the label on yesterday's number was wrong.

**R9 restated:** the advisor is a change detector, not a safety measure. **It registered nothing about any of
the six cross-tenant findings in §5, or about §4.4's self-promotion.** All seven are invisible to a
seven-rule reachability lint by construction — they are *application logic inside correctly-granted objects*,
which is precisely what `PATH_SURFACE.md` §5.3 said no catalog query would find.

---

## 7 · WHAT THIS AUDIT DOES NOT COVER

1. **PostgREST's JWT verification.** Identity was asserted in-database. A forged or expired token is rejected
   above this layer and that layer was not tested.
2. **The 15 empty tables.** No cross-tenant claim here applies to them. They are the first thing to re-probe
   once production carries rows.
3. **The 96 Tier A + 10 Tier B definer functions.** Their gates were **read**, not exercised. A gate that
   reads correctly and is wired wrong is invisible to §5.
4. **`service_role` and `postgres`.** Both `rolbypassrls`. Out of band, and a leaked service key defeats
   everything above.
5. **Material Matrix's surface.** `wh_*`, `get_wh_order`, `create_wh_order`, `wh_set_unit_size` — observed,
   reported, not investigated.
6. **`tg_agenda_*` (6 tables).** Excluded from the 52 and not probed.
7. **BMR's actual configuration**, and the **§8 crew-login risk**. This audit tests gates. It is not that.
8. **A third tenant with data.** Every cross-tenant read was measured against BMR and StructTech as victims.
   A fourth org with a different module set could exercise paths none of the three do.
9. **Point in time**, 2026-09-01. `pg_default_acl` remains the standing reason it will drift.

---

## 8 · FILED, NOT FIXED — ORDERED

> **STATUS UPDATED 2026-09-02 BY TASK S-W1.1.** Findings 1, 2 and 3 are **CLOSED**, in two migrations
> (`20260902220001`, `20260902220225`), both applied via MCP with repo files **md5-verified against
> `supabase_migrations.statements`**. Finding 4 is **BOUNDED, NOT CLOSED**. Findings 5, 6 and 7 are
> untouched and remain open. Proof for each is in §8.1 below; nothing here was closed by reasoning.

| # | Finding | Where | Status | Rule 13: what would have to change for this to open? |
|---|---|---|---|---|
| **1** | `generate_roadmap_for_lead` → `fetch_roadmap_by_token` returns full lead PII to any authenticated caller holding a lead UUID; also an unauthorised write into `client_roadmaps` | §5.2 | ✅ **CLOSED 9/02** | somebody widens `audit_leads`' read policies without widening `generate_roadmap_for_lead`'s predicate to match — a **deliberate, documented coupling**, because a definer function owned by a `rolbypassrls` role cannot get an RLS-evaluated read |
| **2** | 5 definer config readers accept any `p_org_id` and return that tenant's configuration | §5.2 | ✅ **CLOSED 9/02** | somebody removes the `my_org_ids()` guard from an entry point, **or grants `authenticated` EXECUTE on one of the three new `_internal` cores** — both edits visible in the diff that makes them |
| **3** | Any user can self-promote `profiles.role` to `manager` | §4.4 | ✅ **CLOSED 9/02** | somebody drops the `WITH CHECK` on `pipeline_profiles_update_own`, or opens another write path to `profiles.role` |
| **4** | `20260823143943_baseline.sql` re-grants `anon` ALL on 71 tables if replayed | §1.2 | 🟡 **BOUNDED 9/02, NOT CLOSED** | somebody restores from the baseline **and the corrective block appended 9/02 is removed or is not reached** — and, unchanged, **Material Matrix's 20 tables / 1 sequence / 2 functions are deliberately still re-opened by a replay**, reported to them rather than revoked by us |
| **5** | `default_permissions_for_role`'s `else` branch is permissive, so a future 8th role gets financials by default | §2.3 | 🔴 OPEN | somebody adds a value to `org_members_role_check` |
| **6** | 19 of 52 tables carry no `org_id`; the `leads`/`lead_*` family is scoped on role vocabulary B, not on org | §4.5 | 🔴 OPEN | already the case — bounded today only because those tables are empty or unreferenced |
| **7** | `structtech_state`, `audits`, `proposals`, `prospects` have `CREATE TABLE` in neither repo nor ledger | directive §7.1 RULE 6 | 🔴 OPEN | — carried, unresolved |

---

## 8.1 · PROOF OF CLOSURE — S-W1.1, 2026-09-02

Every probe below ran in a **rolled-back transaction**, as the **same real second-org identity used on
2026-09-01** — Material Matrix `member` `c62adbfc-…`, holding **no StructTech and no BMR membership**, its
starting state re-asserted by measurement (`auth.uid()` = `c62adbfc-…`, `my_org_ids()` = `{1084baa8-…}`
and nothing else). Both controls ran **in the same transaction as every probe**:
`select count(*) from deals` = **0** and `select count(*) from audit_leads` = **0**.

### The five config readers — before and after

| Call, as the OUTSIDER | BEFORE (9/02, pre-migration) | AFTER (9/02, post-migration) |
|---|---|---|
| `crm_stage_config(BMR)` | **LEAKED** BMR's full stage array | `P0001 not a member of organization 9d32b5a9-…` |
| `crm_stage_entry(BMR,'new_lead')` | **LEAKED** `{"key":"new_lead",…}` | `P0001 not a member of organization 9d32b5a9-…` |
| `crm_follow_up_cadence_days(BMR)` | **LEAKED** `{2,5}` | `P0001 not a member of organization 9d32b5a9-…` |
| `tracker_status_config(StructTech)` | **LEAKED** StructTech's status set | `P0001 not a member of organization 034db6f4-…` |
| `tracker_type_config(StructTech)` | **LEAKED** StructTech's type set | `P0001 not a member of organization 034db6f4-…` |
| `crm_stage_config_internal(BMR)` — the new core, called directly | n/a (did not exist) | `42501 permission denied for function crm_stage_config_internal` |

**Refusal form (rule 11), named rather than coded.** The five entry points return **`P0001`, a
target-function refusal raised by the function itself** — the loudest available form, and the same message
18 of our 23 org-parameterised definers already raise. The three `_internal` cores return **rule 11 FORM 1
on the TARGET** (`permission denied for function <the function called>`, not a helper) — the privilege
layer, stronger than the guard.

**POSITIVE CONTROLS, same transaction.** The BMR owner (`d63871d2-…`, Isaac) sees **`deals` = 191** — the
same figure as 8/31 and 9/01 — and `crm_stage_config(BMR)`, `crm_stage_entry(BMR)` and
`crm_follow_up_cadence_days(BMR)` all **return normally**. `tracker_status_config` / `tracker_type_config`
return normally for a StructTech member. The refusals are about the caller, not about the functions.

### The roadmap chain — before and after

| | BEFORE | AFTER |
|---|---|---|
| `generate_roadmap_for_lead(<real lead id>)` as the outsider | **SUCCEEDED**, minted a 32-char token | `P0001 lead not found or not accessible: e7b6fb64-…` |
| `fetch_roadmap_by_token(<that token>)` | **RETURNED THE LEAD RECORD** (`Trigger Test \| Test Plumbing Co \| leak=7400`) | not reachable — no token is minted |

**POSITIVE CONTROL:** a **StructTech member** (`09a25143-…`) calling `generate_roadmap_for_lead` on the same
lead **still succeeds** (token length 32) and `fetch_roadmap_by_token` **still returns** the record. The
function works; it now asks who is calling.

**`fetch_roadmap_by_token` IS UNCHANGED, and that was verified rather than asserted:** same `sql` body, same
`STABLE`, same pinned `search_path`, same `proacl` `{postgres=X, authenticated=X, service_role=X}` —
**`anon` is still NOT granted EXECUTE**, and today's task deliberately did not grant it.

### `profiles` self-promotion — before and after

| Step, as the outsider | BEFORE | AFTER |
|---|---|---|
| `role` before | `salesman` | `salesman` |
| `is_pipeline_manager()` before | `false` | `false` |
| `update profiles set role='manager' where id = auth.uid()` | `ROWS=1` | `42501 new row violates row-level security policy for table "profiles"` |
| `is_pipeline_manager()` after | **`true`** | `false` |
| **POSITIVE CONTROL** — edit own non-role column | `ROWS=1` | **`ROWS=1`** |

**The positive control is the whole point of this row.** The first attempted fix — a plain subselect on
`profiles` inside the policy's `WITH CHECK` — *also* refused the self-promotion, and would have read as a
pass. It raised `42P17 infinite recursion detected in policy for relation "profiles"` on **every** profile
update, controls included: it was an outage wearing a fix's clothes. The shipped version uses a
SECURITY DEFINER helper, `my_pipeline_role()`, for the same reason `my_org_ids()` is one.

### THE HAZARD THIS TASK FOUND, AND THE CONTROL THAT PROVED IT

The directive's fix shape — put the membership guard in the five config readers — **would have taken the
public lead form down**, and that is measured, not predicted. `auto_create_deal` is `AFTER INSERT ON
audit_leads`, `audit_leads` carries an **`Allow anon insert`** policy, and the trigger calls
`crm_follow_up_cadence_days`. As `anon`, `auth.uid()` is NULL and `my_org_ids()` is empty.

| Control, one rolled-back transaction | Result |
|---|---|
| `auto_create_deal` pointed at the **GUARDED** name → anonymous lead-form insert | **FAILED — `P0001 not a member of organization 034db6f4-…`** |
| `auto_create_deal` pointed at the **`_internal` core** → anonymous lead-form insert | **SUCCEEDED** — 1 deal auto-created, 2 follow-ups scheduled, 3 days apart, i.e. StructTech's real configured `[2, 5]` |

Re-verified on the **shipped** code after applying: the anonymous insert succeeds, 1 deal, 2 follow-ups,
3 days apart.

**One instrument failure is recorded rather than hidden.** The first version of that probe used
`INSERT … RETURNING id`, which returned `42501 permission denied for table audit_leads` — `anon` holds
`INSERT` but not `SELECT`, and `RETURNING` needs `SELECT`. That is **CLAUDE.md rule 11's own worked
example**, walked into again. Re-probed without `RETURNING`.

### Finding 4 — the baseline, measured (task §3)

- **(a) Is it a row in `supabase_migrations.schema_migrations`? NO — zero rows.** It is the single
  permanent REPO-ONLY file, already recorded as such in `supabase/_KNOWN_DIVERGENCE.md`.
- **(b) Is anything verifying its md5 against `statements`? NO, and it cannot be** — there is no
  `statements` to verify against. The append was therefore safe and the controller's conditional applied.
- **(c) The count, reconciled.** "71" is **confirmed** as *table* grants to `anon` — all 71 name a
  `public.*` object, out of **76 tables the dump creates in `public`**. But only **67** are `GRANT ALL`;
  the other 4 (`wh_drivers`, `wh_order_line_items`, `wh_orders`, `wh_spec_files`) grant everything except
  SELECT. **And the directive's 71 undercounts the anon surface: there are 11 more anon grants it did not
  name — 7 on FUNCTIONS** (including `build_roadmap_levels`, `roadmap_playbook`, `protect_roadmap_columns`,
  `bmr_ticket_touch`, `touch_leads_updated_at` — exactly the five that `20260829142810` revoked),
  **3 on SEQUENCES** (two of them the `tg_agenda_*` pair revoked by `20260828170827`), and **`GRANT USAGE
  ON SCHEMA public TO anon`**. The dump also grants `ALL` on the same 71 tables to **`authenticated`**, so a
  replay undoes the 8/29 TRUNCATE revoke and all of A-PATH.1 as well. **A replay would undo five
  migrations, not three.**
- **What was done:** a **corrective block APPENDED** to the end of the file — nothing above it edited or
  deleted, proved by md5 over the original 485,928 bytes (`280426ee66d6bc29a2e30c5524975bc8`, unchanged).
  It covers **our 51** of the 71 tables (the 52nd, `products`, postdates the dump), our 2 sequences and our
  5 functions, and restores the posture as **measured from the live catalog**, not reconstructed from the
  migration texts. **Verified by execution:** running the block's statements against production in a
  rolled-back transaction changed **0 of 413 objects' ACLs** once ACL members are sorted — the same
  array-ordering artefact A1.0's axis 5 documented.
- **Deliberately NOT done:** Material Matrix's 20 tables, 1 sequence and 2 functions are left as the dump
  has them. Several of their anon grants serve a live storefront, and the 8/20 precedent is our migration
  causing their outage. **Reported, not revoked.** A replay still re-opens their objects.

---

## 9 · ADVISORS AFTER S-W1.1 — RECORD ONLY (R9)

**229 lints / 7 rules** (was **228 / 7** on 9/01).

| Lint | 9/01 | 9/02 | Δ | Accounted for |
|---|---|---|---|---|
| `authenticated_security_definer_function_executable` | 127 | **128** | **+1** | **Ours** — `my_pipeline_role`. Its `authenticated` EXECUTE is **load-bearing**: the policy is scoped `TO authenticated` and is evaluated as that role |
| `pg_graphql_authenticated_table_exposed` | 65 | 65 | 0 | — |
| `rls_enabled_no_policy` (INFO) | 16 | 16 | 0 | — |
| `pg_graphql_anon_table_exposed` | 16 | 16 | 0 | all Material Matrix's |
| `anon_security_definer_function_executable` | 2 | **2** | 0 | both Material Matrix's; **ours is zero** |
| `extension_in_public` · `auth_leaked_password_protection` | 1 · 1 | 1 · 1 | 0 | — |

**The three `_internal` cores do NOT appear in the +1**, which is an independent confirmation that the
`authenticated` revoke on them landed: four functions were created today and only one is listed.

**R9 restated, and it is the same restatement as yesterday because nothing changed.** The advisor
**registered nothing** about any of the six cross-tenant findings closed today, and would have registered
nothing had they stayed open. They are application logic inside correctly-granted objects, which a
seven-rule reachability lint cannot see by construction. The only delta it reports is a new function's
reachability — a fact about the catalog, not about the tenant boundary. **Watch the delta, not the number.**
