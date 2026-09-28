# GOING LIVE — WHAT TO UPGRADE, WHAT NOT TO
**Measured 2026-09-17.** Every number below is read from the live services, not estimated.

## THE HEADLINE

**Your throughput is not the problem. Your recoverability is.**

Measured load today:

| | Now | Free tier limit | Headroom |
|---|---|---|---|
| Database | **25 MB** | 500 MB | 20× |
| Storage | **17 MB**, 50 objects | 1 GB | 60× |
| Auth users | **4** | 50,000 | 12,500× |
| Tenants | **3** | — | — |

Nothing you are about to do strains any service. **Two things will bite you anyway, and
one of them is the biggest unmanaged risk on this project.**

---

## 1. SUPABASE — UPGRADE. $25/mo. DO THIS FIRST.

**You are on the FREE plan.** Confirmed: org `structteck`, plan `free`.

**Free tier has NO BACKUPS. None. No point-in-time recovery.**

Your client's entire business lives in this database — 191 BMR deals, their customers,
their estimates, their signed documents. **There is currently no restore point for any
of it.** A bad migration, a mistaken delete, a bug in a function, and it is gone with no
way back.

That risk is not theoretical here:
- **Material Matrix has applied 17 migrations to this database that do not exist in our
  repo.** We do not review them and we do not know what they do.
- We closed a TRUNCATE grant on three tables *this week* that let any signed-in member
  empty your purchase orders.
- A HackerOne report is still open on `anon` TRUNCATE over storage.

**Free also pauses the project after 1 week of inactivity.** A paused project is a dead
platform. Today the build keeps it awake; a quiet week over a holiday does not.

| | Free (now) | Pro ($25/mo) |
|---|---|---|
| **Backups** | **none** | **daily, kept 7 days** |
| Point-in-time recovery | none | +$100/mo (not yet needed) |
| Pauses after inactivity | **yes, 1 week** | never |
| Log retention | 1 day | 7 days |
| Database included | 500 MB | 8 GB |
| Storage included | 1 GB | 100 GB |
| Support | community | email |

**Verdict: upgrade now, before the pilot, before the next Material Matrix migration.**
Skip the $100 PITR add-on — daily backups are enough at this size.

---

## 2. VERCEL — UPGRADE. $20/mo. THIS IS A LICENSING PROBLEM.

**You are on Hobby.** Vercel's pricing page states plainly: *"Our Hobby plan is for
personal, non-commercial use."* Pro is described as being for *"professional developers,
freelancers, and businesses."*

**The day you charge Brothers Metal Roofing, you are running a commercial product on a
plan whose terms forbid it.** That is not a performance question, it is a terms
question, and it does not get better by waiting.

Second problem, and it lands squarely on October 7: **Hobby retains runtime logs for one
hour, with no log drains.** On pilot day, if a crew member's page fails to load at 9am
and you hear about it at noon, **the evidence is already gone.** Pro gives 1 day, and
drains at $0.50/GB if we want longer.

| | Hobby (now) | Pro ($20/mo) |
|---|---|---|
| **Commercial use** | **not permitted** | permitted |
| Runtime logs | **1 hour** | 1 day |
| Log drains | none | $0.50 / GB |
| Bandwidth | 100 GB/mo | included, flat-rate |
| Function invocations | 1M/mo | 1M/mo |
| Seats | 1 | $20/seat, free viewers |

**Verdict: upgrade before October 7.** One seat is enough — you are the only developer.

---

## 3. RESEND — STAY FREE FOR NOW. Revisit at real volume.

| | Free (now) | Pro ($20/mo) |
|---|---|---|
| Emails / month | 3,000 | 50,000 |
| **Emails / day** | **100** | unlimited |
| Custom domains | 3 (using 1) | 10 |
| Data retention | 30 days | 30 days |

**What you will actually send per job:** a signing link, a signed copy, and six milestone
comms = roughly 8 emails. Even at 50 jobs a month that is ~400 — well inside 3,000.

**The limit that could bite is 100/day, not 3,000/month.** A day where you blast a batch
of follow-ups plus normal job traffic could touch it. It has not yet.

**Verdict: stay free. Upgrade the day you hit a daily cap, not before.** $20/mo saved
until it earns itself.

---

## 4. EVERYTHING ELSE — NO ACTION

- **Healthchecks.io** — free covers 20 checks, you use 1.
- **GitHub Actions** — free and unlimited on public repos; the monitor runs ~7× a day for
  seconds. If you make the repo private (still on your list), free gives 2,000 min/month
  and you would use a tiny fraction.
- **Cloudflare R2** — not built yet. Free covers 10 GB; you are at 17 MB.
- **Stripe** — per-transaction, no tier to choose. Due Oct 18.
- **Wix** — already paid, DNS only.

---

## THE BILL

| Service | Now | Change | Monthly |
|---|---|---|---|
| **Supabase** | Free | **→ Pro** | **$25** |
| **Vercel** | Hobby | **→ Pro** | **$20** |
| Resend | Free | no change | $0 |
| Healthchecks | Free | no change | $0 |
| GitHub | Free | no change | $0 |
| | | **TOTAL** | **$45 / month** |

**$45/month is what it costs to have backups and to be legitimately commercial.** Against
what you intend to charge per tenant, that is not a decision — it is a rounding error.

---

## ORDER, AND WHY

1. **Supabase Pro — today.** Every day without backups is a day a Material Matrix
   migration or a bad function can destroy a client's data permanently. This is the one
   with an irreversible failure mode.
2. **Vercel Pro — before October 7.** Licensing compliance, and the logs you will need on
   pilot day.
3. **Supabase custom SMTP — 5 minutes, free.** Separate from the above and also blocking:
   the built-in mailer only delivers to your own team, so a crew member locked out on a
   roof cannot reset their password. Host `smtp.resend.com`, port 465, username `resend`,
   password is a fresh Resend key.
4. **Resend Pro — not yet.** Revisit when a daily cap is actually hit.

## ONE THING TO WATCH AFTER UPGRADING

Pro plans bill on usage above the included amounts. At your size that will not happen,
but **set a spend cap in Vercel** (Pro includes spend management) so a runaway function
or a traffic spike cannot produce a surprise. Supabase Pro at 25 MB against an 8 GB
allowance has no realistic path to an overage this year.

---

# PLATFORM REGISTRY — THE WHOLE STACK

**Purpose:** one record per external service, structured so it can become a
`platform_services` table in the StructTech admin portal. Every field below is a column.
**No credential values appear here — variable NAMES only.** That rule holds when this
becomes a settings screen too: the portal stores where a key lives and when it expires,
never the key.

**Measured 2026-09-17.** Re-derive before trusting; a registry read from memory is a
registry that lies.

## PROPOSED COLUMNS

`service` · `purpose` · `account_ref` · `plan` · `monthly_cost` · `billing_owner` ·
`env_var_names` · `expires_at` · `breaks_if_down` · `decision` · `decided_on` · `notes`

---

## LIVE — PAYING OR DEPENDED ON TODAY

### Supabase
- **Purpose:** database, auth, storage, row-level security. The whole platform.
- **Account ref:** project `structtech` / `ejlhrykcdfcyeooooodx` · org `structteck` /
  `atutgdfktddukxabhrrj` · region `us-east-1` · Postgres `17.6.1.084` · created 2026-03-18
- **Plan:** FREE · **$0** → **upgrade to Pro, $25/mo**
- **Env var names:** `NEXT_PUBLIC_SUPABASE_URL` · `NEXT_PUBLIC_SUPABASE_ANON_KEY` ·
  `SUPABASE_SERVICE_ROLE_KEY` · `SUPABASE_DB_URL`
- **Expires:** the management PAT expires **2026-12-31**. Deliberately not rotated —
  Jacob's standing decision. Put a reminder on the calendar; when it lapses, MCP access
  and every tool built on it stops.
- **Breaks if down:** everything. No login, no data, no app.
- **Decision:** upgrade to Pro immediately — Free has zero backups. 2026-09-17.
- **Notes:** shared with Material Matrix, who have applied **17 migrations not in our
  repo**. Custom SMTP not configured — built-in mailer only delivers to team addresses.

### Vercel
- **Purpose:** hosts the Next.js app at `os.structtek.com`. Build, deploy, run.
- **Account ref:** project `structtech-os`
- **Plan:** HOBBY · **$0** → **upgrade to Pro, $20/mo**
- **Env var names (Production, confirmed by name):** `RESEND_API_KEY` · `EMAIL_FROM` ·
  `AUTH_EMAIL_ENABLED`. **Not set:** `ORG_FILES_ENABLED`.
- **Breaks if down:** the app is unreachable. Database survives.
- **Decision:** upgrade before 2026-10-07 — **Hobby terms forbid commercial use**, and
  1-hour log retention is blind on pilot day.
- **Notes:** CLI linked 2026-09-16 so CC can read env names itself. Set a spend cap on Pro.

### Resend
- **Purpose:** transactional email — signing links, signed copies, milestone comms.
- **Account ref:** domain `structtek.com` (apex), verified via **CNAME** records, not MX
  (Wix cannot do subdomain MX). Records: `resend._domainkey` TXT · `rsend` CNAME ·
  `send` CNAME → `*.forge.rmta.net`
- **Plan:** FREE — 3,000/mo, **100/day** · **$0**
- **Env var names:** `RESEND_API_KEY` · `EMAIL_FROM` (`StructTech OS <documents@structtek.com>`)
- **Breaks if down:** no signing links, no signed copies. Signatures still save.
- **Decision:** stay free. Revisit at a daily cap, not a monthly one. 2026-09-17.
- **Notes:** keys are send-scoped, which is correct and which is also why a `GET /domains`
  call returns 401. Multiple keys may exist from setup attempts — **audit and delete the
  unused ones.**

### GitHub
- **Purpose:** source of record; Actions runs the front-door monitor and the tripwires.
- **Account ref:** `jacobaw1995/structtech-os` — **PUBLIC**
- **Plan:** Free · **$0** (unlimited Actions minutes on public repos)
- **Secret names:** `DEADMAN_PING_URL`
- **Breaks if down:** no monitoring, no deploys from push. Running app unaffected.
- **Decision:** no change. If the repo goes private, free gives 2,000 min/mo — the monitor
  uses a tiny fraction.
- **Notes:** **making the repo private is still an open item on Jacob's list.**

### Healthchecks.io
- **Purpose:** the dead-man's switch. Alerts when the monitor stops reporting.
- **Account ref:** check `structtech front-door monitor` · Period 1 h · Grace 7 h
- **Plan:** Free — 20 checks, 1 in use · **$0**
- **Breaks if down:** we lose the alarm on the alarm. Nothing user-facing.
- **Decision:** no change. 2026-09-17.
- **Notes:** ARMED confirmed 2026-09-16 (delivery proven). **Alerting not yet proven** —
  test with the grace-time method, never Pause.

### Wix
- **Purpose:** DNS for `structtek.com`. Nothing else in this stack.
- **Plan:** already paid · **$0 incremental**
- **Breaks if down:** DNS fails — email and the app's domain both stop resolving.
- **Notes:** **cannot create MX records on subdomains** — this forced the Resend CNAME
  path. DMARC is CNAME'd to Wix at `p=none`, reporting to `vali.email`: **a third party
  controls your DMARC policy.**

### Google Workspace
- **Purpose:** actual business email at `structtek.com`. MX at the apex.
- **Breaks if down:** you lose email. Unrelated to the OS.
- **Notes:** SPF merged 2026-09-16 and verified — 1 record, 7 of 10 lookups.

---

## IN THE SPF RECORD BUT UNACCOUNTED FOR — AUDIT THESE

Your merged SPF authorizes three senders. One is Google. **The other two send mail as
`structtek.com` and are not part of this build:**

- **LeadConnector** (`spf.leadconnectorhq.com`) — GoHighLevel. Marketing/CRM automation.
- **Mailgun** (`mailgun.org`)

**Neither appears anywhere in StructTech OS.** Confirm what uses them and whether they
should still be authorized. **Every sender in your SPF can send mail that passes
authentication as you** — an authorization you forgot is an authorization you still granted.

---

## COMMITTED BUT NOT YET CREATED

### Stripe
- **Purpose:** subscription billing — the licensing revenue path (Phase D).
- **Plan:** per-transaction, no tier to choose.
- **Due:** account under the StructTech entity by **2026-09-25** (verification takes days
  to weeks) · live **2026-10-18**
- **Decision:** not created. Nothing purchased.
- **Notes:** standing rule 14 applies — one real call and one real refusal against real
  Stripe before it is called done.

### Cloudflare R2
- **Purpose:** file storage at volume — crew photos, packets.
- **Plan:** not created. Free covers 10 GB; current usage 17 MB.
- **Decision:** defer. Supabase Storage is carrying it. Revisit when photos scale.

### Twilio
- **Purpose:** SMS for instant lead response.
- **Status:** DEFERRED TO NOVEMBER by the MVP line. Not cut.

---

## WHAT THIS BECOMES IN THE ADMIN PORTAL

A settings screen under StructTech's own tenant, internal-only, that answers four
questions without anyone opening a vendor dashboard:

1. **What are we paying, to whom, and when does it renew.**
2. **What expires** — the Supabase PAT on 2026-12-31 is the live example. A key that
   lapses silently is an outage nobody predicted.
3. **What breaks if this dies** — the blast radius column, written before the outage
   rather than during it.
4. **Which environment holds which variable**, by name only. Never a value, in the
   database or on the screen.

**Two rules for when it is built:**

- **It stores names and dates, never secrets.** If the portal can display a key, the
  portal is now a place keys leak from.
- **A row is a claim and it needs a measured-on date.** Every field above carries
  2026-09-17. A registry nobody re-measures becomes a document that describes a system
  you no longer have — which is exactly how the Build module went 25 days stale.

**Not a roadmap item yet.** Add it to the tracker under StructTech internal, and keep it
out of Phase A — nothing here blocks the 31 October MVP.
