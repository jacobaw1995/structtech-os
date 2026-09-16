# Field pilot instrumentation — October 7, 2026

Track X, X-W1.18, written 2026-09-16 (America/New_York). Proposal plus the two
read-only scripts that need no migration.

## 1 · What has to be true on the day for a crew on a roof to use this

`node scripts/pilot/pilot-readiness.mjs` checks every item that can be checked
without writing anything. Exit codes: 0 ready, 1 not ready, 2 undetermined.

| # | Must be true | How it's checked |
|---|---|---|
| R1 | Production answers | `/api/health` returns `ok` and a SHA |
| R2 | The office roof-data section is switched on | `ORG_FILES_ENABLED` present in Vercel Production, by name |
| R3 | We know who the pilot crew are | user ids named in `pilot.config.json` by Jacob, not inferred from a role |
| R4 | Each of them has an account and has signed in once | `auth.users.last_sign_in_at` |
| R5 | Each of them sees a job to work on | asked **as that user**: live trade work orders visible |
| R6 | …and no master work order | asked as that user |
| R7 | …and no estimate, so no dollars | asked as that user |
| R8 | …and can open roof data and photos from the office | asked as that user: `org-files` objects visible |
| R9 | The office has actually uploaded something | object count in `org-files` for the pilot org |
| R10 | We can still see what happened after the day ends | Vercel plan: runtime-log retention |

**Why this pass condition can't be moved by another track.** Nothing here names a
role, a policy, a helper function, or another track's column as the thing that must
be true. The crew are named people, and each check asks what *that person* can
reach through whatever RLS is live that day. If the crew gate is rewritten, the
question and its meaning stay the same. **Controls, 2026-09-16:** with the BMR
owner (deliberately not crew) as "crew", R6 and R7 **fail** (2 masters and 4
estimates visible). A made-up user id **fails** R4 and R5. So the checks can see
rows, and they can fail.

**First run, 2026-09-16: NOT READY — 1 PASS, 4 FAIL.**
- R2: `ORG_FILES_ENABLED` is missing in Production.
- R3: no pilot crew are named.
- R9: 0 office files.
- R10: the plan is **Hobby**.

## 2 · What we'd need to see to know whether it worked

`node scripts/pilot/pilot-day-signals.mjs 2026-10-07` counts, for one New York
day and from durable records only:
- check-ins (all authors, and by named crew), distinct work orders, check-ins with
  photos, and check-ins reporting a blocker;
- office files added;
- work-order activity rows;
- named crew whose last sign-in fell on that day.

The day window is converted by Postgres. Control: 2 estimates on 2026-07-21, 0 on
the 20th.

It then lists, **as unknown and not as zero**, everything nothing records (§3).

## 3 · What we couldn't tell you on pilot day with what exists now

1. **Whether a crew member opened the work order or its packet.** Nothing writes an
   open. That's A4.5 (acknowledgment), which is also "the office can prove the crew
   received the current version".
2. **Completion rate and time-to-complete (A4.8).** There's no expected-work
   denominator (A4.1, the daily objective, isn't built) and no start event.
   **A4.8 has no Build Tracker row**, although the directive lists it in §5.4.
3. **Failed, slow or abandoned loads on a weak signal.** They appear only in Vercel
   runtime logs, and **on Hobby those last 1 hour, with no log drains**
   (vercel.com/docs/logs/runtime, read 2026-09-16). By the next morning they're gone.
   Today's `[email.send]` lines have the same limit.
4. **Every sign-in.** `auth.audit_log_entries` holds 0 rows; auth events go to
   Supabase's log stream. Only each person's *last* sign-in is durable.
5. **Which files a crew member actually opened.** A signed-URL read leaves no record.
6. **Special trips (A4.2) and QC photos (A4.3).** Not built.
7. **Whether a crew member locked out on the roof can get back in.** Password-reset
   mail goes through Supabase's **built-in** mailer (measured 2026-09-16:
   `mail_from noreply@mail.app.supabase.io`), which is documented to refuse any
   address outside the Supabase organization's team. A crew member asking for a
   reset gets `mailer_restricted` and no email.

## 4 · Proposal for Track S — the one migration that closes 1, 2 and 5

An append-only `field_events` table: `org_id`, `actor_id`, `work_order_id`, `event`
(`work_order_opened`, `packet_opened`, `file_opened`, `check_in_started`,
`check_in_saved`), `occurred_at` (server), `client_sent_at` (the phone's clock, so
an offline queue is visible later), and `meta jsonb` with ids only.

Writes go through one security-definer `record_field_event` RPC that takes the
work order id and derives the org and actor itself, closed with
`revoke execute … from public, anon`. It needs the house grant set for both roles
(rule 8), and read `to authenticated` via `my_org_ids()`.

Track X would then call it from the field pages and the files section (all Track X
code or small inserts), and `pilot-day-signals.mjs` would count opens and
time-to-complete from it. **Not built, because it's schema.**

## 5 · Decisions that aren't Track X's

- **Vercel plan.** Hobby is documented as "non-commercial, personal use only"
  (vercel.com/docs/plans/hobby) and keeps logs 1 hour. A paid client pilot on it is
  a terms question as well as an observability one. Jacob's call; nothing was
  changed or purchased.
- **Name the pilot crew:** copy `pilot.config.example.json` to `pilot.config.json`
  and add their user ids.
- **Custom SMTP for Supabase Auth,** or crew can't reset their own passwords (§3.7).
- **Set `ORG_FILES_ENABLED=true`** in Production, now that Track S has applied the
  storage policies.
