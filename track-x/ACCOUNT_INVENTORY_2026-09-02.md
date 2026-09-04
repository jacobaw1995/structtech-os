# External account inventory — one list, once

**Track X · X-W1.1 · 2026-09-02 (America/New_York) · measured, not assumed**

The point of this file is that you are interrupted **once** with a complete list
instead of five times across five weeks. Nothing below asks for a key today.

**How to read the columns.** *Start by* is the date you have to begin, not the
date it is needed — for anything with a verification queue those are different
dates, and the gap is the whole reason this list exists.

**Scope of the evidence.** Everything marked *measured* was checked on
2026-09-02 against: this repo, live DNS for `structtek.com` /
`thecontractingco.com`, the live HTTP responses of `os.structtek.com` and
`audit.structtek.com`, and the Supabase project `ejlhrykcdfcyeooooodx`
(edge-function list, `auth.identities`, `storage.buckets`). Where I could not
find something I say **"I could not find one"** — that is not the same as
saying one does not exist, and it is never written as if it were.

---

## The list, ordered by START-BY date

| # | Service | Account exists today? | Start by | Needed by | Lead time |
|---|---|---|---|---|---|
| 1 | **Uptime heartbeat** (dead-man's switch) | No — I could not find one | **now** | now | none (~10 min) |
| 2 | **SPF repair on `structtek.com`** | n/a — a defect, not an account | **now** | before any Resend send | none, but DNS TTL |
| 3 | **Stripe — StructTech's own** | **A Stripe account exists, but it is Material Matrix's** | **~2026-09-25** | 2026-10-18 (G11) | **days to weeks — the big one** |
| 4 | **Resend** | No — I could not find one | **~2 weeks before A6.1** | A6.1 / A6.6 | ~1 h–24 h after DNS |
| 5 | **Cloudflare R2** | No — I could not find one, **and the build may not need it** | **before A4 starts** | A4 (field photos) | ~1 h |
| 6 | **Google OAuth** | Google Workspace yes; **OAuth client no** | Phase D | Phase D — **no Phase A dependency** | minutes, *or* weeks (see below) |

---

## 1 · Uptime heartbeat — the gap in today's own deliverable

**Why it is first.** The front-door monitor shipped today runs on GitHub
Actions. A red run emails you. **Silence does not.** If the schedule stops
firing — GitHub drops scheduled runs under load, and disables them outright
after 60 days of repo inactivity — the result looks exactly like nine weeks of
healthy checks. That is the same shape as the failure the monitor was built to
catch, one level up.

- **What to create:** one free-tier check on any heartbeat service
  (healthchecks.io and Better Stack both have a free tier that covers this).
  It expects a ping every 20 minutes and emails you when one does not arrive.
- **What breaks without it:** nothing visibly — which is the problem. You
  cannot tell a healthy month from a dead monitor.
- **What I need from you:** the ping URL, into the repo's Actions **secrets**
  (Settings → Secrets and variables → Actions). It never comes through chat and
  never into a file.
- **Cost:** $0.

## 2 · SPF on `structtek.com` — a live defect, free to fix, blocks item 4

**Measured today, and this is a fact about your production DNS, not a
prediction:** `structtek.com` publishes **two** `v=spf1` TXT records at the
apex —

```
"v=spf1 include:_spf.google.com ~all"
"v=spf1 include:spf.leadconnectorhq.com include:mailgun.org ~all"
```

RFC 7208 §4.6.4 makes more than one SPF record a **PermError**. Receivers are
entitled to treat the domain as having no usable SPF at all. DMARC is
`p=none` today (`_dmarc.structtek.com` → `_dmarc.wixemails.com`), so nothing
is being rejected yet — which is exactly why nobody has noticed.

Two further facts worth having in one place: **DNS for `structtek.com` is
hosted at Wix** (`ns6/ns7.wixdns.net`), so every record below gets added in
the Wix panel, not Vercel's. And **mail is Google Workspace** (`aspmx.l.google.com`).
The second SPF record shows **LeadConnector (GoHighLevel) and Mailgun** are
already sending as this domain.

- **What to do:** merge the two into one record. Do not guess the merge — it
  needs to name every sender you actually use, and I can only see three.
- **Why it is item 2 and not item 4:** adding Resend to a domain whose SPF is
  already in PermError starts transactional email on a broken foundation, and
  the symptom (silent spam-foldering) is the hardest kind to debug later.

## 3 · Stripe — the one with real lead time

**The trap here is that "we already have Stripe" is true and irrelevant.**

Measured: `create-payment-intent` (v19) and `stripe-webhook` (v12) are ACTIVE
edge functions in `ejlhrykcdfcyeooooodx`. Those are **Material Matrix's**
storefront. The directive's §3 decision 5 is explicit: *"MM keeps its own
Stripe merchant account. StructTech's own billing (Phase D) stays separate."*
So G11 needs a **second, separate Stripe account** under the StructTech
entity — not a new API key on the existing one.

- **What breaks if it is not there by 18 Oct:** the OS cannot charge for
  itself. §6.3 calls this "the $20K MRR path". Every other Phase A item can
  ship without it; this one is revenue.
- **Why it needs three weeks, not an afternoon:** a new Stripe account with
  real bank details goes through business verification. It is usually a couple
  of business days and is occasionally much longer — EIN mismatches, a bank
  account in a different name, or an unclear business description each restart
  the clock. **Starting 25 September buys three weeks of slack for something
  that normally needs two days.** That is the whole reason it is on this list
  now rather than in October.
- **What to create:** Stripe account under the StructTech entity · business
  verification · bank account for payouts · then a product/price for the
  licence tiers. **Keys go from Stripe's dashboard into Vercel's environment
  variables directly — never through chat, never into a repo file.**
- **Also flagged, separately, because it is MM's and not ours:** §6.7 row 7
  still lists MM's own "TEST → LIVE keys + webhook secret" as open. I could not
  verify which mode MM is in — that needs the dashboard, which I do not have.

## 4 · Resend — transactional email

No Resend account found: no DKIM records under `structtek.com`, no `resend`
reference anywhere in `src/`, and **no email-sending code of any kind in the
application today** (`sendEmail`, `resetPasswordForEmail`, `inviteUserByEmail`
— zero hits).

Needed for **A6.1** (six client milestones: signed · material ordered ·
delivery date set · crew scheduled · day-before · complete) and **A6.6**
(remote signing link, auto-emailed signed copy, self-serve password reset).

- **What to create:** Resend account · verify a **sending subdomain**, e.g.
  `mail.structtek.com` or `send.structtek.com` — **not the apex**. A subdomain
  keeps transactional reputation separate from Workspace mail and from
  LeadConnector/Mailgun marketing sends, and it means Resend's SPF does not
  have to be merged into the apex record at all.
- **Lead time:** DNS records propagate in about an hour at Wix, but budget a
  day. Item 2 should be fixed first.
- **What breaks without it:** A6.1's *Done when* — "a scheduled milestone
  fires without anyone remembering to send it" — is unreachable. A6.6's
  password reset also has no channel, which means every new tenant user needs
  you to set their password by hand.

## 5 · Cloudflare R2 — **and a question about whether it is the right answer**

I could not find a Cloudflare account: no `R2_`, `S3`, or `aws-sdk` reference
anywhere in `src/`, and no Cloudflare nameservers on either domain
(`structtek.com` → Wix, `thecontractingco.com` → Vercel).

**Two measurements that should be decided on before an account is created:**

1. **Supabase Storage is already in this project and already holding files** —
   5 buckets (`deal-files`, `pdf-files`, `spec-files`, `product-photos`,
   `bot-assets`), 50 objects. CLAUDE.md names R2 as the decided stack, but the
   live system has been using Supabase Storage.
2. **Field check-in photos are not going to either one today.**
   `src/components/field/PhotoPicker.tsx` reads the picked file to a **base64
   data URI and stores it in the `check_ins.photos` column** — in Postgres.
   The comment says so deliberately ("no separate upload endpoint needed").
   `check_ins` is at **0 rows**, so nothing is broken yet and the whole
   database is 23 MB. The moment a crew starts taking photos this becomes row
   bloat at ~1.33× the file size, inside every query that selects the row.

- **What to create:** nothing, **until the decision is made**. This is a
  StructTech-side decision — R2 vs. the Supabase Storage already in place —
  and it is cheap now and expensive once check-ins carry photos.
- **What breaks if nobody decides:** A4 ships storing photos in Postgres,
  and moving them afterwards is a data migration instead of a config change.

## 6 · Google OAuth — genuinely not urgent, but the lead time is bimodal

**Measured:** `GET /auth/v1/settings` on the project reports **every external
provider `false`**, including `google`; `email` is the only enabled method.
All 4 users in `auth.users` are email/password — **zero non-email identities**.
And Google sign-in appears in the directive only in **§6.3, Phase D** — no
Phase A task depends on it.

- **The lead time depends entirely on scope, and this is the part worth
  knowing now:** plain "Sign in with Google" (`email`, `profile` only) on a
  Workspace-internal app is a same-day job. The moment Gmail-send or Calendar
  scopes are added — which §6.3 lists in the same breath — it becomes a
  **restricted-scope OAuth app requiring Google verification, and that is a
  weeks-long queue with a security questionnaire.**
- **Recommendation:** if Gmail/Calendar is wanted at all, create the Google
  Cloud project and start verification **early**, because it costs nothing to
  have it approved and waiting.
- You already have Google Workspace on this domain, which makes the Cloud
  project and consent screen straightforward.

---

## Not on the directive's list, but found while looking

- **`tmp-render-probe` (v7) is an ACTIVE edge function** in the production
  project. The name says temporary. Residue, not an account — for Track S.
- **`audit_leads` holds 7 rows, newest 2026-07-17** — 47 days ago. I am
  recording the number, not diagnosing it: with no ad spend that is simply
  quiet. It is worth a glance only because the form **cannot report its own
  failure** (see below), so "quiet" and "broken" look identical from outside.
- **The lead form swallows its own errors.** `results.html` posts the lead with
  `.catch(function(err){ console.warn('Supabase write failed (non-blocking)') })`,
  and `fetch` does not reject on HTTP errors — so a 401 from PostgREST resolves
  normally and is never even seen by the `catch`. **A revoked grant would show
  the visitor a success screen and drop the lead in silence, forever.** That is
  the single strongest reason the monitor built today exists.

---

## What is NOT needed, so nobody creates it

- **A monitoring account** — GitHub Actions covers it at $0. Only the heartbeat
  (item 1) is missing.
- **A second Supabase project** — the escape hatch in SCOPE.md §7 is a future
  option, not a purchase.
- **A Vercel account** — one exists and is serving `os.structtek.com` and
  `shop.thecontractingco.com`. Which also settles §4.6's open note: hosting is
  **Vercel**, measured from the response headers (`server: Vercel`,
  `x-vercel-id: iad1::…`). The "Netlify elsewhere" doc conflict is resolvable
  in StructTech's favour of Vercel.
