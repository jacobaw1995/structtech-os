# X-W1.14 · Signed copy: the gap the app can't close, and a proposal for Track S

**Status:** proposal. Nothing here has been run, not even in a rolled-back
transaction. Schema is Track S's.
**Written:** 2026-09-14 (America/New_York), on track-x after merging origin/main `e217ba3`.

## What Track X built, and what it guarantees

`signEstimate` (src/lib/estimating/actions.ts) calls `sign_estimate()`. That is one
security-definer PL/pgSQL function: it inserts the `signatures` row and sets the
estimate to `signed` in one statement, so in one transaction, and it returns the
signature id. Only after that returns does the action call `sendSignedCopy()`
(src/lib/estimating/signed-copy.ts), which:

- writes nothing to the database, so nothing it does can roll the signature back;
- never throws. Every failure comes back as a named state (`sent`, `no_email`,
  `not_configured`, `rejected`, `unavailable`, `render_failed`) that the present
  page shows under "The signature is saved";
- runs in the same request as the signature, so it doesn't depend on anyone
  loading a page afterwards.

Tested against a production build with Supabase and Resend stubs: all six states,
a failing `sign_estimate` (no send attempted), and a client that disconnects 1 s in,
before any send code runs (signature committed and copy sent about 2 s later). That
last test ran on `next start`. **I haven't measured it on Vercel.**

## The gap: the send isn't durable

If the function stops between the commit and the Resend call (a deploy, a crash,
the platform timeout), **the signature is kept and no copy goes out, and nothing
records that it didn't.** No row says a copy was owed. So nobody can find these
cases later, and nothing retries them. In-app code can't close this, because the
"a copy is owed" record has to be written in the same transaction as the signature.

## Proposal: an outbox row written inside `sign_estimate`

Sketch only (not run, and not a migration file):

```sql
create table public.email_outbox (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid not null references public.organizations(id),
  kind             text not null check (kind in ('signed_copy')),
  subject_id       uuid not null,                 -- signatures.id for signed_copy
  idempotency_key  text not null unique,          -- 'signed-copy:<signature id>'
  status           text not null default 'pending'
                   check (status in ('pending','sent','no_email','not_configured',
                                     'rejected','unconfirmed','render_failed')),
  attempts         int  not null default 0,
  provider_id      text,                          -- Resend message id when sent
  created_at       timestamptz not null default now(),
  last_attempt_at  timestamptz,
  sent_at          timestamptz
);
alter table public.email_outbox enable row level security;
revoke all on table public.email_outbox from anon;          -- CLAUDE.md rule 8
create policy email_outbox_select on public.email_outbox
  for select to authenticated using (org_id in (select my_org_ids()));
-- inside sign_estimate(), after the signatures insert:
--   insert into public.email_outbox (org_id, kind, subject_id, idempotency_key)
--   values (v_org_id, 'signed_copy', v_signature_id, 'signed-copy:' || v_signature_id);
-- plus a security-definer RPC to record an attempt's outcome, closed with
-- revoke execute ... from public, anon (rule 7).
```

With that row in place, the app-side send stays as it is. It would also record its
outcome, and a drain would retry `pending` and `unconfirmed` rows.

## Decisions this needs (not Track X's to make)

1. **What drains the outbox.** A Vercel cron route needs a credential that can read
   across orgs, and this build has no service-role path today. A Supabase-side
   sender (pg_net, or an Edge Function) puts the Resend key in Supabase. Both
   change the security surface. Jacob and S decide.
2. **Resend idempotency lasts 24 hours** (Resend docs, read 2026-09-14). A drain
   that retries after 24 hours can deliver a second copy. The retry window should
   be shorter than that, or the record of a send has to be the outbox row rather
   than Resend's key.
3. **Remote signing.** Track X stopped at this line (directive 2c).
   *Corrected the same evening.* The first version of this item said the token
   model was undecided. Track S's spine (`792601b`, migration `20260915004736`)
   landed while this was being written: hashed per-document links in
   `estimate_sign_links`, `signatures.sign_token` dropped, and
   `sign_estimate_by_link(token, …)` as the anon surface. **Read from the migration
   file only; not checked against the live database.** It leaves two gaps for the
   signed copy:
   - `sign_estimate_by_link` returns `{state, business, signed_at}` with **no
     signature id**, so the send can't be keyed to the signature it's for.
   - Its caller is `anon`. `sendSignedCopy()` loads the estimate, lines, signature
     and branding through member-only reads, so it **can't run from that path**.

   What the send path would need from S, in either order: (a) the signature id
   returned from `sign_estimate_by_link`, or the outbox row above written by the
   `signatures_after_insert` trigger, which covers both paths in one place; and
   (b) a way to load the signed document outside a member session.
   One question is also open: should the copy go to the estimate's `email`, or to
   an address captured when the link is issued? `estimate_signing_document()`
   deliberately carries no email.
   No app code calls the remote surface yet (`git grep` of src on main, excluding
   generated types, found nothing).
4. **Invites.** Nothing in the app creates invites (`RoleReference.tsx:13`). No
   invite email was built, because there's no event to send it from.
