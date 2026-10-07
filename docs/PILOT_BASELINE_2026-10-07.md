# PILOT BASELINE — the "before", taken before pilot day 1

**Taken by Track S. The clock, run first, because UTC had already rolled:**

```
$ TZ=America/New_York date
Tue Oct  6 20:29:58 EDT 2026
$ date -u
2026-10-07 00:29:58 UTC
```

**It is Tuesday 2026-10-06 in New York and Wednesday 2026-10-07 in UTC as this is written.** Every
timestamp below is EDT. Production was serving **`bd181d3`**, read from `/api/health`, not assumed.

**Why this file exists: a "before" cannot be taken after the fact.** Tomorrow this database receives
a roofer's check-ins, hours, blockers, special trips and photos of a real customer's roof.

---

## THE FACT THAT MAKES IT IRREVERSIBLE

**Supabase organization `structteck` (`atutgdfktddukxabhrrj`) is on plan `free`, tier `tier_free`.**

**Source: the Supabase management API, measured by the controller on 2026-10-06.** Track S recorded
this as *unmeasurable from its own session* earlier the same day and was right to — the Supabase MCP
is disconnected here and no management token is available. **It is now measured, and Track S did NOT
re-derive it**; this entry is a record of someone else's measurement with its source named, not a
second reading. *(Note for whoever checks it next: `atutgdfktddukxabhrrj` is an ORGANIZATION id; the
database this file measured is reached by `SUPABASE_DB_URL`, whose project ref is a different
identifier. Confirming they belong to the same org is a one-glance job in the dashboard and has not
been done here.)*

**Free tier means no backups. So everything written tomorrow is irreplaceable** — there is no PITR,
no daily snapshot, and no restore point to go back to. That single fact is the reason for both
standing rules in `docs/PILOT_DAY_RUNBOOK_2026-10-07.md`.

---

## THE COUNTS, each with the filter that produced it

**A count without its filter is not a count (CLAUDE.md 33).** The SQL is beside every number so
tomorrow's diff is reproducible rather than remembered.

### check-ins

| number | value | filter |
|---|---|---|
| total, all orgs | **1** | `select count(*) from check_ins` |
| carrying a `client_token` | **0** | `select count(*) from check_ins where client_token is not null` |
| in BMR | **1** | `… where org_id='9d32b5a9-e11e-401b-8fa7-969065b004ce'` |

**The 0 is the headline.** The idempotency guard shipped 2026-10-04 and **has never been exercised by
a browser**. The one existing row was written at 16:51:57.347 EDT on 2026-10-04, before the caller
existed.

### special trips

| number | value | filter |
|---|---|---|
| total, all orgs | **0** | `select count(*) from special_trips` |
| carrying a `client_token` | **0** | `select count(*) from special_trips where client_token is not null` |

**The table is empty. No special trip has ever been recorded in this product.**

### field events

| number | value | filter |
|---|---|---|
| total, all orgs | **74** | `select count(*) from field_events` |
| distinct `subject_ref` | **8** | `select count(distinct subject_ref) from field_events` |
| rows with a non-null `subject_ref` | **8** | `… where subject_ref is not null` |
| in BMR | **52** | `… where org_id='9d32b5a9-…'` |

**The two 8s are the same 8, and that is the filter worth stating:** `count(distinct …)` ignores
NULLs, so **66 of the 74 rows carry no `subject_ref` at all** — they are `signed_in`, `page_ready`
and `work_order_opened` events, which have no subject. Tomorrow's diff should be read on both
numbers, because a check-in that saves increments the non-null count and one that fails does not.

### office files

| number | value | filter |
|---|---|---|
| objects in `org-files` | **1** | `select count(*) from storage.objects where bucket_id='org-files'` |

**Limit on this instrument, stated because it bounds the claim (CLAUDE.md 34): this counts SURVIVING
objects.** An upload that happened and was deleted is invisible to it.

### schedule blocks covering 2026-10-07, split by whether the parent work order is voided

```sql
select case when w.voided_at is null then 'parent LIVE' else 'parent VOIDED' end as parent_state,
       count(*), string_agg(sb.id::text,', ')
from schedule_blocks sb join work_orders w on w.id = sb.work_order_id
where sb.org_id = '9d32b5a9-e11e-401b-8fa7-969065b004ce'
  and sb.start_date <= '2026-10-07' and sb.end_date >= '2026-10-07'
group by 1;
```

| parent | blocks | id | trade |
|---|---|---|---|
| **LIVE** | **1** | `5aa34bb4-4959-4470-827b-9a126523fde5` | Test Roofing |
| **VOIDED** | **1** | `7253dc37-7fe7-4c40-9af1-384c8df82de5` | TRACK S · A2 live acceptance (Fake Lead) |

**TWO blocks cover pilot day; ONE reaches a phone.** `fetch_field_jobs` carries
`and w.voided_at is null`, and **that predicate is the only thing keeping a Track S fixture off a
roofer's screen tomorrow morning.** "1 schedule block" was stated three times across three days and
was never the whole number.

### crew assignment on the pilot work order

```sql
select a.id, a.crew_id, c.name, a.task, a.created_at
from work_order_crew_assignments a left join crews c on c.id = a.crew_id
where a.work_order_id = 'd76d8664-3337-4e2c-a898-b3b5bae32415';
```

| field | value |
|---|---|
| assignment | `9d21e83d-a221-4e0a-b73e-e69952207956` |
| crew | `ac5046da-51ec-41f8-866b-bbad2f05c378` — **Install Crew** |
| task | **Roof Install** |
| created | 2026-10-04 00:30:20 EDT |

### the pilot work order's stage — and it is DERIVED, not a column

**`work_orders` has NO `stage` or `status` column.** Measured:
`select column_name from information_schema.columns where table_name='work_orders' and column_name ~ 'stage|status|state'` returns **nothing**. The
progress rail is derived in **`src/lib/coordination/stage.ts`** from data presence, so it "can never
drift from the rows it summarizes". The five chips, each with the query that decides it:

| chip | complete? | derivation, measured tonight |
|---|---|---|
| **Signed job** | ✅ **true** | a **signature row** exists for the job's estimate — `select count(*) from signatures s join jobs j on j.estimate_id=s.estimate_id where j.id='7e9e4f49-…'` = **1**. Deliberately not `estimates.status`, which a person can set |
| **Sign-off: colors & finishes** | ❌ **FALSE** | `work_orders.sign_off_at is null` on the trade **and** on the master. Both NULL |
| **Work order** | ✅ **true** | `select count(*) from work_orders where job_id='7e9e4f49-…' and kind='trade' and voided_at is null` = **1** |
| **Materials** | ❌ **FALSE** | `select count(*) from material_items where work_order_id='d76d8664-…'` = **0** — the material list is **empty** |
| **Schedule** | ✅ **true** | `select count(*) from schedule_blocks where work_order_id='d76d8664-…'` = **1** |

**TWO chips are grey tomorrow, not one: Materials AND Sign-off.** Both are expected. The work order
itself is `kind='trade'`, trade "Test Roofing", `voided_at` NULL.

---

## The signed-URL read path, answered tonight

Full reasoning in the runbook. The measured facts: **the page-level thumbnail URL lives ONE HOUR**
(`DEFAULT_SIGNED_URL_TTL_SECONDS = 60 * 60` in `src/lib/storage/org-files.ts`, and
`WorkOrderFiles.tsx:44` calls `signOrgFiles` without an override), minted at server-render time and
baked into the delivered HTML. **Opening a file goes through a different path that re-signs per
click at 60 s** (`src/app/w/[orgId]/files/open/route.ts`). **So the file always opens; the THUMBNAIL
beside it breaks after an hour on a page nobody reloaded.**

---

## How to take the "after"

Re-run every query in this file, in order, and diff. **Expected directions if the pilot goes well:**
`check_ins` up with **every new row carrying a non-null `client_token`** · `special_trips` 0 → n with
tokens · `field_events` up with the non-null `subject_ref` count rising alongside saved check-ins ·
`org-files` unchanged unless the office uploads again · schedule blocks unchanged · the Materials and
Sign-off chips still grey unless somebody acts on them.

**The one number that would mean the idempotency guard did not work: more than one `check_ins` row
sharing a `client_token`** — impossible by the partial unique index, so the failure shape to look for
is instead **new rows with a NULL token**, which would mean the caller is not sending one.
