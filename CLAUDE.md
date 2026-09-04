# CLAUDE.md — StructTech OS Build Directive

## Before you change anything

Read `docs/STRUCTTECH_OS_DIRECTIVE.md` first. It is the single source of truth for
this build — current phase, decisions of record, active stage, and backlog. Read §1
(Current Position) and §11 (Active Execution Week) to know where we are and what
today's task is.

Rules: if a request doesn't map to a task in §5 it goes to the backlog in §6, not into
the branch. If a task's "Done when" depends on something not written in §5, fix the
directive first — never fill the gap silently in code. The directive wins over the
Build Tracker; if they disagree, correct the tracker.

You are building **StructTech OS**: one modular, multi-tenant platform that runs StructTech's own business and is licensed, in configurable pieces, to StructTech's clients. **One build, licensed per tenant.** StructTech is tenant #1; contractor clients (e.g. Brothers Metal Roofing) are tenants granted a subset of modules.

**Read these first, in order, before writing any code:**
1. `docs/SCOPE.md` — authoritative product scope: tenant/module/role model, confirmed architecture decisions, data-model direction, non-goals. **Precedence: `docs/STRUCTTECH_OS_DIRECTIVE.md` wins over everything. SCOPE.md and
   the module scope docs remain authoritative for anything the directive does not
   cover. If this file disagrees with either, they win over this file.**
2. `docs/ROADMAP.md` — the CURRENT forward timeline + cadence (reset 7/24). Supersedes
   `docs/BUILD_PLAN_3WEEK.md`, which is complete and now historical.
2a. **In-app Build Tracker (`roadmap_items` table, StructTech org) — the live feature-status source AND a
    two-way input channel.** Before scoping or building ANY feature, **read its `roadmap_items.notes`
    first** — Jacob drops questions, concerns, workflow, and expectations there; they are a REQUIRED input
    to the spec, same weight as SCOPE/BACKLOG. Write decisions/answers back into the note so each feature
    carries its own decision log. Flip a feature to `in_progress` when picked up, `shipped` when done.
2b. `docs/BACKLOG.md` — the durable queue of deferred/queued work (what's owed and what's next). The queue lives here, NOT in this file's phase section or a session's memory.
3. `docs/wireframes/StructTech OS - HiFi (standalone).html` — the **locked visual source of truth**. Match it. Design tokens are extracted below.
4. `docs/reference/` — read-only reference: existing DB schema and domain specs to build on (do not treat as the base app; do not copy wholesale).

---

## Rules of engagement (non-negotiable)

- **Build only inside `structtech-os/`.** Never edit anything outside this folder. The legacy projects (`../structtech/`, `../Brothers Metal Roofing/`) are not accessible and are reference only.
- **Build the current phase only.** Right now that is **Week 1 — Foundation** (see §Current Phase). Do not build Week 2+ features unless told.
- **Do not fork the BMR app or `structtech-pipeline`.** Reuse *patterns*, never copy a whole app. The duplication between those two is exactly what this build ends.
- **Confirm before behavior-changing decisions.** If the user describes a behavior, confirm it's intended before "fixing" it. Never guess at product behavior.
- **Ask before:** applying any migration to the live Supabase project, adding a new dependency, changing auth/RLS/security, or anything touching `structtech_state`.
- **Small, reviewable commits.** One concern per commit. The user reviews diffs.
- **THIS PROJECT RUNS ON `America/New_York`. RUN `TZ=America/New_York date` BEFORE WRITING ANY DATE.** UTC rolls over at 8 PM EDT and will silently advance a stamp by a day. This has happened twice in one week — the A1 acceptance ran Friday 2026-08-21 at ~8 PM EDT and was stamped 2026-08-22 across the directive because the clock was read in UTC. Never take the date from `date`, `new Date()`, a tool result, or a system-reminder without converting it first.

---

## Tech stack — decided, do not re-litigate

| Layer | Choice |
|---|---|
| Web | Next.js 14 (App Router) + TypeScript |
| Styling | Tailwind CSS (theme mapped to the design tokens below) |
| Backend | Supabase (Auth + Postgres + RLS + Realtime) — existing `structtech` project |
| Files/photos | Cloudflare R2 (S3-compatible) |
| Mobile (later phases) | React Native + Expo + PowerSync/SQLite |
| Email | Resend · **PDFs** | pdf-lib · **Scheduled sends** | Make.com scenario |

All secrets via env vars (`.env.local`). Never hardcode keys or project refs in source.

---

## Supabase + App Router — mandatory patterns

These are learned from repeated debugging. Every violation causes silent RLS failures, 404s, or auth bugs. Follow exactly.

1. **`getSession()` before every DB call.** `getUser()` alone does not load the session into the client; without it PostgREST sends no auth header and `auth.uid()` is null.
   ```ts
   const { data: { session } } = await supabase.auth.getSession()
   if (!session) redirect('/login')
   ```
2. **Always `createClient()` from `@/lib/supabase/server`** in server contexts. Never import `createServerClient` directly; never use the browser client server-side.
3. **All inserts go through security-definer RPCs.** Direct `.insert()` on RLS tables fails even with a valid session.
4. **All single-record fetches (`by id`) go through security-definer RPCs.** Direct `.select().eq('id', x).single()` fails RLS. Always pass `org_id` for RLS context.
5. **List queries are fine with direct table access** after `getSession()` — they resolve through the RLS helper.
6. **Server actions `redirect()`, never `return` data.**
7. **All RLS policies use the existing `my_org_ids()` helper** — never subquery `org_members` directly in a policy (infinite recursion). (This function already exists and is used by 8 live policies; reuse it, don't recreate or alias it.)
   ```sql
   create policy "t_select" on <table> for select
     using (org_id in (select my_org_ids()));
   ```
8. **`Cannot find module './vendor-chunks/...'` / `ChunkLoadError`** = stale build cache, not a code bug: `rm -rf .next && npm run dev`.
9. **R2 browser uploads require CORS** on the bucket (`GET PUT POST DELETE HEAD`, `AllowedHeaders: *`, `ExposeHeaders: ETag`) — set before testing in-browser.

RPC templates (insert returns uuid; fetch returns `setof <table>`, `stable`) live in `docs/reference/` — mirror them for every new entity.

---

## Multi-tenancy model — the core of the whole build

- **Every domain table carries `org_id`.** RLS scopes every read/write by org via `my_org_ids()`.
- **`organizations`** — one row per tenant. `tenant_type` ∈ (`internal`, `contractor`).
- **`memberships`** — (`org_id`, `user_id`, `role`). A user can belong to multiple orgs.
- **`tenant_modules`** — (`org_id`, `module_key`, `enabled`, `config` jsonb). This is the entitlement layer. Nav and route guards render from it.
- **Two axes of access:** *tenant entitlements* (which modules exist for the org) × *user role* (which screens within them). Nav bends to both.
- **Agency operator layer:** StructTech admins operate inside client tenants. Model this simply as a **membership in the client org with role `agency_admin`** — so `my_org_ids()` returns it and RLS needs no special case. The top-bar tenant switcher changes the active org context.
- **License activation = inserting rows** (`organizations` + `tenant_modules` + `memberships`), never provisioning a new database.
- **Escape hatch:** a future enterprise client needing hard isolation can be siloed onto its own Supabase project with the same code — do not design anything that blocks that, but do not build it now.

### Module registry
| module_key | entitled tenant types | notes |
|---|---|---|
| `crm` | all | pipeline; **stages are per-tenant config** |
| `estimating` | contractor | live on-site estimate → sign |
| `coordination` | contractor | sign-off → work order → materials (ready-by gates schedule) |
| `field` | contractor | crew mobile; role-scoped; no pipeline/$ |
| `delivery` | internal (admin) + surfaced read-only inside the client tenant | engagement execution → client portal |
| `scan` + `roadmap` | internal only | already live in the DB |

---

## Design system — match the locked hi-fi

Map these into the Tailwind theme / CSS variables. Pull exact spacing/radius from the hi-fi html.

```
--bg:        oklch(98%   0.004 90)
--surface:   oklch(99.5% 0.002 90)
--surface2:  oklch(95.3% 0.004 90)
--text:      oklch(22%   0.006 90)
--muted:     oklch(48%   0.006 90)
--border:    oklch(88%   0.006 90)
--accent:        oklch(0.55 0.16 250)
--accent-strong: oklch(0.42 0.16 250)
--accent-soft:   oklch(0.93 0.03 250)
--warn:      oklch(0.55 0.15 45)
--warn-soft: oklch(0.94 0.04 45)
```

- **Fonts:** IBM Plex Sans (UI) · IBM Plex Mono (money, measurements, IDs) · IBM Plex Serif (client-portal headings only).
- **Accessibility:** small white-text buttons/chips use **`--accent-strong`**, not `--accent` (AA contrast). `--accent` is fine for large text and fills.
- **Field & estimating (mobile):** outdoor high-contrast mode (black bg) is **available via a toggle, NOT default-on** (updated 7/13 per Jacob — crews switch it on if they need it; default to the normal light theme); **≥56dp touch targets**; single thumb column; never show pipeline or dollar figures in the `field` role.
- **Sync status** is a first-class UI element on all field screens (offline / syncing / synced) — offline-first is a core principle.

---

## Data model direction

**Extend the existing `structtech` Supabase project — do not start a new database.**

> **Reality note (confirmed 7/9):** `organizations` and `org_members` **already exist** in the live project (serving `org_systems`, `tickets`, `org_invoices`, `org_invites`, and the `engagement_*` FKs). They ARE the tenant/workspace concept — **extend them, never create a parallel org concept.** Concretely: add `tenant_type` to `organizations` (+ backfill); use the existing **`org_members` as the membership table** ("memberships" in this doc = `org_members`; expand its role values for `owner`/`agency_admin`/office/crew); `my_org_ids()` reads from `org_members`. Only **`tenant_modules`** is genuinely new. Because this alters tables live features depend on, **branch-test before applying.**

- **Add (Week 1 foundation):** extend `organizations` (add `tenant_type`), extend `org_members` (roles), add `tenant_modules`; the `my_org_ids()` RLS helper (reads `org_members`); org-scoped policies; security-definer insert/fetch RPCs. Backfill `org_id` onto existing tables as a **separate** migration.
- **Reuse (already live — see `docs/reference/`):** `audit_leads`, `client_roadmaps`, `roadmap_playbook()`, `deals` + `follow_ups`, `engagements` / `engagement_levels` / `engagement_milestones` / `engagement_checkins`.
- **Later phases add per module:** estimates + line_items + signatures; work_orders + material_items + schedule_blocks; check_ins + production_packets.

---

## Design so as not to preclude (North Star)

Do **not** build these now, but do **not** make choices that block them (full detail: `docs/SCOPE.md` §12–13):
- **Business logic lives in server actions / RPCs, never buried in components** — this action layer becomes the AI assistant's tool surface later.
- **Append-only activity/history on every domain entity** — it's the audit trail and the AI's "what changed" source.
- **Estimate line items (Week 2) must allow an optional `product_id`** link, not free-text only — client catalogs and the shop plug in here.
- **Org isolation is the default, but don't hard-wire it** so a controlled cross-tenant "published supplier catalog" (StructTech's live shop prices, readable by contractor tenants) becomes impossible. No shared-catalog code now — just don't preclude it.
- **`pgvector`** gets enabled when semantic search arrives — not now.

---

## Migration discipline — learned the hard way, do not skip

1. **`CREATE OR REPLACE` with a CHANGED SIGNATURE creates an OVERLOAD, not a replacement.** Adding even a
   trailing optional param counts. Always `DROP FUNCTION` the exact old signature first. "Safe for existing
   callers" is about *callers* — it says nothing about overloads. (Hit 3+ times: line-item RPCs, milestone
   RPCs, `update_estimate_details`.)
2. **`DROP FUNCTION IF EXISTS` with a mistyped signature SILENTLY SUCCEEDS.** `IF EXISTS` suppresses the
   no-match error, so a hand-transcribed type list that's off by one `text` drops nothing and reports
   success. **Copy the signature verbatim from `pg_get_function_identity_arguments()`; never retype it.**
   (Hit 7/24 on `update_deal_details`.)
3. **Verify DB state after applying — never trust the success response.** Both traps above were caught only
   by re-querying `pg_proc` afterward. Confirm overload counts and that drops actually dropped.
4. **CHECK-constraint value changes need DROP → UPDATE rows → ADD.** Updating rows to a value the *old*
   constraint forbids aborts the migration. (Hit on `lead_type`, again on `estimates.status`.)
5b. **Migrations hit prod IMMEDIATELY; UI deploys lag. A migration must stay backward-compatible with
   the CURRENTLY-DEPLOYED UI until the matching UI ships.** Chunk 1 narrowed `estimates.status` vocabulary
   in prod while the deployed wizard still read the old values — which silently broke estimate *creation*
   (bug #4) AND *step advancement* (flow.ts) in production for days. If a migration changes a value set,
   constraint, or default the live UI depends on, either ship the UI in the same window or keep the change
   additive/backward-compatible until you do. When in doubt, test the DEPLOYED commit against the migrated
   schema (git worktree at the prod commit + live DB) — reasoning isn't enough.
5. **PL/pgSQL treats a NULL `IF` condition as FALSE.** `if not (is_manager or v_owner_id = auth.uid())`
   silently *allows* the action when `owner_id IS NULL`. Wrap nullable comparisons in
   `coalesce(..., false)`. (Hit 7/24 — a real authorization bypass on unowned rows.)
6. **`tsc` passing is not evidence the generated types match the schema — only that the code agrees with
   whatever the types happen to say.** Regenerate or hand-verify `database.types.ts` against
   `information_schema` in the same task as any migration that adds or drops a column, table or constraint.
   (Hit 8/18: A1.1 added six columns to `work_orders` and created `jobs`; both A1.1 and A1.2 shipped green
   with `work_orders` missing all six, `jobs` absent from the types entirely, and `estimate_id` still marked
   `isOneToOne` after its unique constraint was dropped. Nothing caught it because no code had read the new
   columns yet.)

7. **EVERY MIGRATION THAT CREATES A FUNCTION IN `public` CARRIES AN EXPLICIT `revoke execute on function <sig> from public, anon` AS A CLOSING STATEMENT — AND `set search_path`.** PostgreSQL's built-in default grants `EXECUTE` on new functions to `PUBLIC`, and **`ALTER DEFAULT PRIVILEGES` CANNOT remove it** (proved on a virgin PG 17.11 after our own pairing turned out to be a no-op — §6.9). So on this backend **every new security-definer function in `public` is `anon`-executable the moment it exists** unless the migration revokes it. `grant ... to authenticated` narrows nothing; it re-states a grant that already exists. Copy the signature from `pg_get_function_identity_arguments()`, never retype it (rule 2). *(Written down as a rule for ourselves on 8/20 and not sent to Material Matrix until 8/26 — which is how `wh_reject_retired_color_link()` arrived unrevoked. The omission was ours.)*
   **THE MECHANISM, not just the statement (added 8/27 — our previous wording was right by luck, not by understanding).** The grant is on **`PUBLIC`**, and it shows up in `proacl` as the **leading `=X/postgres`** entry with no grantee name in front of the `=`. It is **not** a grant to `anon`. So **a revoke naming only `anon` is a NO-OP** — it removes a grant that was never there, reports success, and leaves `anon` executing the function through its `PUBLIC` membership. `revoke ... from public, anon` works because of the `public`; the `anon` is belt-and-braces. Read `proacl` after the revoke and confirm the `=X` entry is gone — do not trust the success response (rule 3).
   **THE `authenticated` CARVE-OUT, and the TEST behind it (Jacob's decision, 8/27).** Material Matrix proposed adding `authenticated` to the blanket revoke. **REJECTED.** Every app write in this build is a security-definer RPC called **as `authenticated`** — that grant *is* the call path, and revoking it breaks the application, not an attacker. Revoke `authenticated` **only when nothing outside the database calls the function** — as we correctly did for `default_permissions_for_role` (called only from `accept_invite`/`add_org_member`/the role-change trigger) and `derive_catalog_price` (called only from the catalog RPCs). **THE TEST IS "does anything outside the database call this?", answered PER FUNCTION, never assumed.** MM ran the same test against their own schema and found **four** functions their own proposed blanket rule would have broken, checkout among them.
8. **THE SAME IS TRUE OF TABLES.** A new table in `public` comes out `anon=arwdDxtm` — full SELECT/INSERT/UPDATE/DELETE. **Every migration creating a table in `public` carries an explicit `revoke all on table <t> from anon`.** Found 8/25 on `products`, which had RLS on and every policy scoped `TO authenticated`, so nothing was readable — **the defect was REACHABILITY, not disclosure**, and it surfaced as `pg_graphql_anon_table_exposed` moving 67 → 68. Scope new policies `TO authenticated` too: a policy left `TO public` whose expression calls a definer helper must be *evaluated* for `anon`, which is what took the Material Matrix storefront down on 8/20.
9. **THE ADVISOR IS A CHANGE DETECTOR, NOT A SAFETY MEASURE — WATCH THE DELTA, NOT THE NUMBER.** `anon_security_definer_function_executable` sat at 2 for six days and was read as evidence the door stayed shut; it was only evidence nobody had opened a new one. It moved to 3 on 8/26. **It is a shared instrument reporting on a shared surface** (§4.7, D6/D7), so a number that does not move proves nothing about either project. Record the count before and after every migration and account for every delta, including the other project's. **AND A DELTA YOU DID NOT CAUSE GETS REPORTED TO THE OTHER SIDE, NOT INVESTIGATED** (MM's refinement, adopted 8/27). Accounting for a delta means identifying whose it is, not diagnosing it. **8/20 is the precedent: our migration, their outage** — and the fix was right only because each side examined its own half. Investigating someone else's half means reasoning about code you cannot read and a live surface you cannot test, which is how a correct report turns into a wrong fix.

10. **A RECONCILED FILE REPRODUCES WHAT RAN — DOWN TO THE VALUE, NOT ONLY THE FILE. BUT IT DOES NOT FABRICATE A HISTORY THE REPLAY DOES NOT HAVE.** *(Both halves added 8/27, on Material Matrix's review of the joint `organizations` row.)*
    **The first half — specify identity LITERALLY.** An idempotency guard keyed on a MUTABLE column reproduces *a* row, not *the* row. Our `organizations` guard keyed on `name + tenant_type`; `name` is mutable, so after a rename the guard matches nothing and silently creates the duplicate it exists to prevent — at the moment nobody is watching, because a guarded file reads as safe. **Proved, not argued (8/27):** replaying the name-keyed file against a restore whose row had been renamed produced a SECOND org with a second id. **Key on the primary key and write the id as a literal.** This is §7.1 Rule 1 applied to a VALUE rather than to a FILE.
    **The second half — the BOUNDARY, and it is not a softening of the rule.** Do **not** pin audit fields the replay cannot honestly assert: `created_at`, `updated_at`, and anything else that records *when*, not *what*. Forcing a production timestamp into a clean restore asserts a history that restore does not have. **Pin identity and payload; let time be time.**
    **A DIVERGENCE YOU DOCUMENT IS A FACT; A DIVERGENCE YOU LEAVE UNDOCUMENTED TRAINS PEOPLE TO IGNORE DIFFERENCES** (MM's reasoning, adopted). So the deliberate divergence gets a comment line in the file itself. Someone diffing a restore against production in three months either burns a day on it or learns that differences on this row are normal — and the second is the advisor problem (rule 9) wearing different clothes.

11. **THE THREE REFUSAL FORMS — GRADE AN `anon` PROBE ON THE MESSAGE, NOT ON THE CODE.** *(Added 8/29. We mislabelled this in BOTH directions inside one session, and caught ourselves both times — which is the reason it is written down rather than assumed.)*
    A probe that "failed" proves nothing until you read *which* failure it was. There are three, and two of them are the same SQLSTATE:
    1. **`permission denied for table X`** → the table grant is gone. **PASS.**
    2. **EMPTY RESULT, NO ERROR** → RLS refused the rows and **THE GRANT SURVIVED**. The privilege layer was never reached. **NOT A PASS** — this is a closed door with the lock still unset.
    3. **`permission denied for function Y`** → **depends entirely on what Y is, and this is the discriminator:** if `Y` is the **TARGET** of the call (you invoked `Y` and were refused), **PASS**. If `Y` is a **HELPER a policy tried to evaluate** (`my_org_ids`, `is_staff`, `has_capability`, …), then the *target's* grant is **INTACT** and you were stopped by an unrelated EXECUTE bit. **NOT A PASS.**
    **Forms 1 and 3 are both `42501` and are indistinguishable to any code-based grader.** A harness that asserts `error.code === '42501'` reports a pass for the one case that is not one. Read the message text, name which of the three forms it is, and record that name in the evidence — not the code, and not "denied."
    **Worked example, 8/29 `audit_leads`:** `INSERT … RETURNING` as `anon` returned `permission denied for function my_org_ids`. That is Form 3, helper variant. `anon` still held `SELECT, INSERT, UPDATE, DELETE` on the table; the only thing standing in the way was an EXECUTE bit on a function the table does not own. Graded as a pass, it would have certified a wide-open table as closed.

    **AMENDMENT, 2026-08-29, THE SAME DAY — AND IT IS A LIMIT ON THIS RULE, NOT AN EXTENSION OF IT. THE TELL IDENTIFIES *WHERE* THE BARRIER IS. IT DOES NOT TELL YOU WHETHER THAT IS THE RIGHT BARRIER.** Everything above is written against `anon`, where an empty result means a grant you meant to remove is still there. **ON `authenticated`, AN EMPTY RESULT IS THE CORRECT OUTCOME AND MUST NOT BE "FIXED".** Every user of this build runs as `authenticated`; its SELECT/INSERT/UPDATE/DELETE grants are **LOAD-BEARING**, and the barrier there is **DELIBERATELY RLS**. Form 2 on that role is the design working.
    **Measured side by side, in one rolled-back transaction, so the two cannot be confused:** as `authenticated` **with a real signed-in BMR owner's JWT**, `select count(*) from deals` returns **191** — the application works. As `authenticated` **with no JWT**, the identical query returns **0 rows, no error** — form 2, and **correct**, because `auth.uid()` is NULL and no org matches. **Same role, same table, same statement; the difference is identity, which is exactly what RLS is for.**
    **Read rule 11 without this paragraph and you will revoke a grant the product needs, on the strength of a probe that was telling you the truth.** The question the tell answers is "which layer stopped me," and the question that follows it is **"is that the layer I intended?"** — which the tell cannot answer and a human must. **On `anon`, RLS-as-the-only-barrier is an accident (rule 13). On `authenticated`, it is the architecture.**

    *(There is no rule 12 here. 13 keeps Material Matrix's own number so that "rule 13" means the same thing in both projects' write-ups. Do not renumber it to close the gap — the gap is the cross-reference.)*

13. **CLOSED BY ACCIDENT IS NOT CLOSED. NAME THE THING THAT WOULD HAVE TO CHANGE FOR THIS TO OPEN.** *(Material Matrix's, adopted whole 8/29. Recorded because they applied it to their OWN remediation and found it wanting — which is the only reason we have it.)*
    For every object you are about to call closed, write down the single change that would reopen it. If the answer is **"somebody adds a policy"** or **"somebody grants EXECUTE on an unrelated helper,"** it is **NOT CLOSED.** Both are **absences standing in for controls**, and an absence has no owner, no review and no alarm.
    The two forms, both live in this database on 8/29:
    · **Closed by a missing EXECUTE.** 49 StructTech tables held the full `arwdDxtm` anon grant and were closed only because their policy predicates call definer helpers `anon` cannot execute. **One `grant execute on function my_org_ids() to anon` would have opened all 49 at once** — and that grant is one line in an unrelated migration written by someone fixing something else.
    · **Closed by a missing policy.** Seven of those 49 had RLS on and **zero** policies, the five `migration_bmr_*` raw PII tables among them. Adding any permissive policy — the ordinary way to make a table usable — would have opened a table nobody remembered was ungranted.
    **The remedy is to make the control the thing you can point at.** Revoke the grant, so closure survives a change to the helper. Then Rule 13's answer becomes "somebody grants `anon` this table," which is a statement about the table itself, reviewable in the diff that makes it.
    **This rule is why `audit_leads` was not fixed first on 8/29.** Fixing the one known instance would have told us nothing about whether it was one of one or one of five. **GET THE DENOMINATOR BEFORE YOU ENUMERATE:** 198 policies, 109 scoped `{public}`, 64 anon-granted objects. `audit_leads` was one of **49**.

14. **TABLES ARE CREATED BY MIGRATIONS. NOT BY THE SUPABASE TABLE EDITOR.** *(Controller decision, Jacob, 2026-09-01.)* Sketching a table is fine — **sketch it inside a transaction you ROLL BACK.** No file, no ledger row, no grants, no residue. A table that survives the sketch was created by a migration or it should not exist.
    **The reasoning, which is stronger than the rule.** A Table-Editor table has **no migration file and no ledger row** — the orphan class A1.0 spent a week bounding — and rule 8 above cannot be applied to a migration that does not exist. And it **may be created by a role whose `pg_default_acl` we do not control**, so an `ALTER DEFAULT PRIVILEGES` on the `postgres → public` entry **would miss it and report success**. That is rule 9's failure mode — an instrument that does not move proving nothing — reached by a different road.
    **The same rule covers probe fixtures, and there it is rule 8's problem in miniature:** any object you create in `public` to test a privilege is **born holding whatever `pg_default_acl` grants** (proved 8/31 — a probe sequence born `authenticated=rwU` reported that `setval` needs no UPDATE). Create it, **revoke explicitly**, then test the denial, then roll back.

15. **A MIGRATION THAT SUCCEEDS AND BREAKS SOMETHING IS INDISTINGUISHABLE FROM ONE THAT SUCCEEDS, WHEN VALIDATION IS DEFERRED TO FIRST CALL.** *(Found 2026-09-03 on A2.3, by a probe of our own that was itself incomplete — which is the only reason it surfaced.)*
    **The mechanism.** PostgreSQL does not resolve the column references inside a function body at `ALTER TABLE … RENAME COLUMN` time. There is no dependency edge from a function body to a column: SQL-language bodies are re-planned at **first call**, and PL/pgSQL statements are parsed at **first execution of that statement**. So a migration can rename a column, leave five functions referencing the old name, **return success**, and pass every structural check — overload counts, `proacl`, row counts, the advisor — while a page dies the next time a user opens it.
    **Proved, not reasoned:** renaming `schedule_blocks.blocked` without replacing `fetch_field_jobs` in the same transaction applied cleanly and then failed with `42703 column sb.blocked does not exist` **only when the function was called**.
    **This is a THIRD class and it is worth keeping distinct from the two already on the list.** Rule 11's refusal forms are about a check that is *wrong*. The empty-instrument problem (§6.9, the 15 zero-row tables) is about a check that *could not have failed*. This one is about **the apply itself reporting success while having broken a runtime path** — there is no probe to misread, no control to omit and no refusal form to grade, just a green result and a defect with a delay fuse.
    **THE REMEDY IS MECHANICAL, WHICH IS WHY IT WILL SURVIVE BEING FORGOTTEN: after any migration that RENAMES or RETYPES a column, CALL every function whose body references it.** Not count them, not read them — call them, and make the referencing statement actually execute, because a branch that never runs is never validated. A refusal counts as an exercise only when the refusal is itself produced by the referencing statement (A1.4's "has materials, a schedule…" is, because that message is the result of the query).
    **ENUMERATE BY PROPERTY, AND WATCH THE INSTRUMENT.** `select … from pg_proc where prosrc ilike '%schedule_blocks%'` returned 9 functions where 7 genuinely touch the table: **`ILIKE` treats `_` as a single-character wildcard**, so the pattern also matched the prose *"schedule blocks"* in an error string. Harmless here — it over-matched — but the identical bug under-matches whenever someone means the underscore literally. Use `~` with a real word boundary, and confirm each hit by reading the context, not the count. Sweep views, RLS policy expressions, indexes, CHECK constraints and triggers in the same pass; on 2026-09-03 all five were empty and the zero was looked for.

---

## CURRENT PHASE — DEPTH PASS (set 7/20, after Isaac's first real demo)

**STOP BUILDING NEW MODULES.** First client demo exposed the gap: the *foundation* held (security,
tenancy, attribution, the 946-row BMR migration) but the *workflow surface* did not. Estimating,
coordination and field were built fast in Weeks 2–3 as skeletons and never got a depth pass.

**The rule now: depth on what exists, in Isaac's real workflow order, until he'd CHOOSE this over his
old app rather than tolerate it.** No new modules until then.

**Full priority list + detail: `docs/BACKLOG.md` → "🔴 ISAAC FEEDBACK (7/20) — DEPTH PASS."**
Order: **P0** stage-gating removal (SCOPE §2.8) → **P1** estimate builder as a Joist-style
document-as-editor (Manual/Guided toggle), real coordination sign-off (signature + document + homeowner
confirmation), field depth (office-side upload + per-role file permissions), dashboard → **P2** Present
Mode as a true multi-section sales deck that *sells the roof*.

**NEW NON-NEGOTIABLE — SCOPE §2.8 "Never block the user."** Never disable a tab, button, or field
because other data is incomplete. Guidance is advisory. Enforcement is per-tenant config, default OFF.
This ranks with §2.6 (full CRUD) and §2.7 (configurable platform) — all three came from real users
telling us the software was in their way.

---

## PREVIOUS PHASE (COMPLETE 7/19) — CRM Depth (turn the pipeline into a real CRM)

**Weeks 1–3 COMPLETE and live at os.structtek.com** — foundation/auth/multi-tenancy/shell (W1); pipeline both tenants + BMR live estimating (W2); BMR coordination + field + management-controls retrofit (W3). All the create/edit/delete controls exist per §2.6.

**Why this phase exists:** what shipped for `crm` is a thin **sales-pipeline view**, not a CRM. Isaac is currently on the BMR app (which he's outgrowing) and StructTech OS's CRM must not be a downgrade. **Full requirements + grounding: `docs/reference/CRM_DEPTH_REQUIREMENTS.md`** — adopt the BMR spec's *features & logic*, NOT its UI/UX/workflow (design fresh from the hi-fi). Every entity gets full CRUD (§2.6).

**RE-FOUNDED 7/14: the CRM Depth phase IS building the Lead Control Center** — the per-lead command center that opens when you click a lead (3-panel desktop/tablet + mobile). What shipped is a thin deal panel; the real design is a stage-driven command center where **every row is a form field AND a checklist item at once.** **Authoritative spec: `docs/reference/LEAD_CONTROL_CENTER_SPEC.md`** (dual-track model, per-stage vital fields, the two checklists, confirmed 3-panel layout). Grounded in BMR's `command-center.ts`/`intake-checklist.ts`/`scope-fields.ts` — **adopt features & logic, design UI fresh.**

**Staged (each reviewable; migrations tight, UI faster):**

1. ✅ **DONE — contact & address data** (shipped): `deals` got `lead_type`/`project_address`/`billing_address`; new-lead form; estimate carries the address.
2. ✅ **DONE — full lead data model** (shipped): split names, structured service address, `intake_checklist` JSONB, milestone timestamps, `owner_id`, tags + RPCs.
3. ✅ **DONE — config-driven command-stage + checklist engine** (shipped): definitions in per-tenant `tenant_modules.config`, TS engine reads config generically. BMR seeded as default.
4. ✅ **DONE + LIVE — Lead Control Center UI** (shipped 7/16, verified on mobile): 3-panel command center, form==checklist inline rows, owner + author-stamped notes. Fix-pass shipped (nested-jsonb completion bug, datetime + roof-type-options fields, add-form → first/last + structured address flowing to checklist + estimate).
5. **✅ DONE (7/19) — Go-live gate: SECURITY + BMR ACCOUNTS + ownership/attribution.** Track A (RLS
   leaks closed, advisor-clean), B (profile-per-user trigger + Isaac seeded as BMR owner, isolation
   probe-verified), C (actor identity on every mutation + owner assignment + edit-by-ownership,
   13-scenario synthetic-rep verified). Isaac can log in scoped to BMR only. Deeper RLS enforcement +
   funnel null-org stopgap tracked in BACKLOG. Original plan text below.
   **← WAS: Go-live gate — SECURITY + BMR ACCOUNTS + ownership/attribution.** **Authoritative plan + live security audit (7/17): `docs/reference/STAGE5_GOLIVE_GATE.md`.** Three tracks, hard-sequenced: **(A) Security** — kill the confirmed `qual=true` leaks (`audit_leads` read, `audits`/`proposals`/`prospects` ALL, `client_roadmaps` update) and re-scope `profiles` + `lead_appointments` off `is_pipeline_user()` (= "any profiled user", not org-scoped); harden `my_org_ids()` search_path; **advisor re-run is the DoD.** (B) Accounts — profile-per-user trigger + backfill the 1 orphan, then seed **Isaac as `owner` in the BMR org via Auth invite (never `staff_users`).** (C) Ownership — owner assignment, actor identity on every mutation, edit-by-ownership (salesman/manager). **Rule: Track A must be advisor-clean BEFORE Isaac's login exists — separate commit.** (Note: RLS-on-structtech_state and most is_staff→my_org_ids items from the old backlog are already done / unnecessary — see the spec.)
6. **Scheduling** — `appointments` (site_survey/inspection; scheduled_at/duration/status). The Schedule quick action → completes the Site Visit stage. (Google Calendar sync later, §13.)
7. **Scope → estimate wiring** — the site-visit **scope checklist feeds the estimate/quote** (closes the site-survey→estimate loop).
8. **Views** — table + calendar (kanban exists). Quick actions are native links now (`tel:`/`sms:`/`mailto:`); Twilio/Gmail integration later (§13).

**Done =** clicking a BMR lead opens a working 3-panel command center: per-stage form==checklist with live completion, owner + author-stamped notes/activity, quick actions, schedulable site visit, the scope checklist flowing into the estimate — all editable/deletable (§2.6), fresh UI, matching Jacob's hi-fi. Isaac can run his whole sales process here instead of the old BMR app.

Pace: tight review on migrations/RLS, faster on UI.

---

## Definition of done (every phase)

- TypeScript builds clean; `npm run dev` runs without console errors.
- RLS verified: a user in org A cannot read org B's rows (write an explicit check).
- Matches the locked hi-fi visually.
- Behavior confirmed with the user before anything ambiguous ships.
- **Full user CRUD (SCOPE §2.6):** every entity the phase creates can be **edited and deleted/archived/voided by the user in the UI** — not just created and advanced. If the user could make it, the user can fix or remove it, without a developer or SQL. No create-only happy paths.
