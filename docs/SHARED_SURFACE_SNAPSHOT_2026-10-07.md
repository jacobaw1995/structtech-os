# SHARED SURFACE SNAPSHOT — 2026-10-07

Taken by Track S at **`Wed Oct  7 18:47:47 EDT 2026`** (`TZ=America/New_York date`; UTC was already
2026-10-07 22:47). Production serving **`ab865f2`**, read from `/api/health`.

## ⚠ READ THIS FIRST — THIS IS NOT A BEFORE-PICTURE FOR TODAY'S MIGRATION. IT IS AN AFTER-PICTURE.

**It was taken to capture the shared surface *before* Material Matrix applied tonight. Material Matrix
already applied — THIS MORNING.**

```sql
select version, name from supabase_migrations.schema_migrations
where version > '20261005205205' order by version;
--  20261007123837 | wh_pdf_files_staff_read_and_delivery_claim
```

**`20261007123837` — the version stamp is UTC by Supabase convention, so 12:38:37 UTC = 08:38:37 EDT
Wednesday 2026-10-07.** Track S read `20261005205205` as the latest row last night at 20:3x EDT, so
this landed in between, **on pilot day, during working hours.**

*(My own first conversion of that stamp printed 16:38:37 — I had `at time zone`'d a value the session
had already rendered as UTC, i.e. converted twice. Corrected before it reached this file; recorded
because it is the same class of error the whole project's clock discipline exists for.)*

**THE CONSEQUENCE, stated plainly: the pilot-day rule "no migration is applied today, from any track,
for any reason" was broken — and it was broken by the one party the rule was never sent to.** Track S
wrote that rule into `docs/PILOT_DAY_RUNBOOK_2026-10-07.md` last night with the note *"the rule needs
sending, not just writing… MM applies migrations to this same database and is not reading this
file."* **That note was correct and it was not acted on in time.** This is the 2026-08-26 precedent
reproduced exactly: a rule written for ourselves, not passed on, and broken by someone who never saw
it. No blame attaches to Material Matrix, who were not told.

**This file is therefore still worth having — as the before-picture for MM's NEXT migration, and as
the after-picture for this one.** It cannot serve as the before for `20261007123837`.

---

## 1 · Every policy on `storage.objects`

```sql
select policyname, cmd, permissive, roles::text,
       (coalesce(qual,'') || coalesce(with_check,'')) ~ 'bucket_id' as carries_a_bucket_id_term
from pg_policies where schemaname = 'storage' and tablename = 'objects' order by policyname;
```

| policyname | cmd | permissive | roles | bucket_id term |
|---|---|---|---|---|
| org-files work order files delete | DELETE | PERMISSIVE | `{authenticated}` | ✓ |
| org-files work order files insert | INSERT | PERMISSIVE | `{authenticated}` | ✓ |
| org-files work order files read | SELECT | PERMISSIVE | `{authenticated}` | ✓ |
| **pdf-files staff read** | **SELECT** | **PERMISSIVE** | **`{authenticated}`** | **✓ — NEW TODAY** |
| product-photos public read | SELECT | PERMISSIVE | `{public}` | ✓ |
| product-photos role delete | DELETE | PERMISSIVE | `{authenticated}` | ✓ |
| product-photos role insert | INSERT | PERMISSIVE | `{authenticated}` | ✓ |
| product-photos role update | UPDATE | PERMISSIVE | `{authenticated}` | ✓ |
| spec-files customer upload | INSERT | PERMISSIVE | `{anon,authenticated}` | ✓ |
| spec-files staff read | SELECT | PERMISSIVE | `{authenticated}` | ✓ |

### 🔴 FINDING — **10 policies, not 9.** The controller's pre-pilot reading has moved.

**All 10 carry a `bucket_id` term (0 without), so that half of the reading is CONFIRMED.** The count
is not. The tenth is **Material Matrix's**, and it is from this morning's migration:

```
pdf-files staff read ::
  ((bucket_id = 'pdf-files') AND (name ~~ 'work-orders/%')
   AND (my_wh_role() = ANY (ARRAY['admin','assistant','driver'])))
```

`driver` in that role list ties it to `wh_pdf_files_staff_read_and_delivery_claim`. It is scoped to
their own bucket and their own role helper, and **it does not touch `org-files`** — the three
`org-files` policies are byte-identical to last night's reading, which is the thing that mattered for
the pilot.

---

## 2 · `public` schema function counts and fingerprint

```sql
select count(*) as total,
       count(*) filter (where p.prosecdef) as security_definer,
       count(*) filter (where p.prosecdef and has_function_privilege('anon', p.oid, 'execute')) as definer_anon_executable
from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public';

select md5(string_agg(sig, E'\n' order by sig))
from (select p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public') z;
```

| measure | controller's reading | measured 18:47 EDT | |
|---|---|---|---|
| total functions in `public` | 430 | **432** | 🔴 **+2** |
| SECURITY DEFINER | 226 | **228** | 🔴 **+2** |
| SECURITY DEFINER with `anon` EXECUTE | 5 | **5** | ✅ confirmed |
| fingerprint (name + identity args, ordered) | `c5f43dfd3dcfd6c8f747f046620e2226` | **`d596edee1be88615e35e2d32f1806553`** | 🔴 **changed** |

### 🔴 FINDING — three of the four numbers moved, and all three move together.

**+2 total / +2 definer / a changed fingerprint is one change, not three**, and it is the same
migration as the tenth policy. Of the 432 functions, **31 are `wh_*` (Material Matrix's) and 401 are
not.** **The anon-reachable count did NOT move**, which is the number that would have mattered
(migration rule 9: watch the delta, and a delta you did not cause is reported, not investigated).
Reported here; not investigated.

---

## 3 · The five anon-reachable SECURITY DEFINER functions

```sql
select p.proname, array_to_string(p.proacl,' | ')
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public' and p.prosecdef
  and has_function_privilege('anon', p.oid, 'execute') order by 1;
```

| function | whose | acl |
|---|---|---|
| `record_signed_copy_outcome_by_link` | ours | `postgres=X \| authenticated=X \| service_role=X \| anon=X` |
| `sign_estimate_by_link` | ours | same |
| `signed_copy_by_link` | ours | same |
| `signing_link_view` | ours | same |
| `wh_order_by_token` | Material Matrix | same |

✅ **CONFIRMED exactly as the controller stated: four ours, all token-gated signing-link functions,
plus `wh_order_by_token`.**

**And one property worth recording beside them: all five carry an EXPLICIT `anon=X` grant.** None
shows the leading `=X/postgres` that PostgreSQL's built-in default to `PUBLIC` produces. So all five
are **deliberate**, not residue — which is the distinction CLAUDE.md rule 7 exists to make, and it is
the reason this count can sit at 5 without being a finding.

---

## What would have to change for these numbers to move again

- **The policy count:** anyone adding a `storage.objects` policy. Each of the 10 is bucket-scoped, so
  a new one without a `bucket_id` term would be the thing to catch — the 0-without column is the
  instrument, not the total.
- **The function counts and the fingerprint:** any migration from any track. The fingerprint is the
  cheap one: it changes on a renamed argument, which neither count would show.
- **The anon count:** a `grant execute … to anon`, or a new definer function whose migration omits
  the rule-7 revoke. **That is the one to watch, and it is the one that did not move today.**
