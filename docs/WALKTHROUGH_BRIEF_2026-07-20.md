# StructTech OS — System State Briefing

**For:** Jacob's Monday walkthrough with Isaac (Brothers Metal Roofing)
**As of:** 7/19/26 · live at os.structtek.com
**Purpose:** exactly what's active (down to the feature, with honest expectations), then what's coming (scope + backlog).

---

## How to frame it for Isaac (30-second version)

It's **one platform**, and BMR is a tenant on it. Isaac logs in as himself (`owner` of BMR), sees **only BMR's data** — never StructTech's or any other client's (this is enforced and verified at the database level). He runs his whole flow in one place with **no re-entry**: lead → estimate → signed → work order → materials/schedule → field. Everything he creates, he can **edit, archive, or fix himself** in the UI — no calling us to correct a typo. And every change is **stamped with who did it and when**.

What to *under*-promise: a few things look like they should work but aren't wired yet (automated follow-up emails, in-app calling/texting, a calendar view, a cross-job schedule, self-serve customization). Those are on the list below — see **Part 3** so you don't over-commit on the call.

---

# PART 1 — WHAT'S LIVE TODAY

## Platform & access (the foundation)

- **Login + workspaces.** Isaac logs in; if a user belongs to multiple tenants they pick a workspace. Isaac only has BMR, so he lands straight in it.
- **Multi-tenant isolation — proven.** BMR data is walled off from StructTech and every other tenant by database-level row security. We verified with a live probe: Isaac's account sees all 8 BMR deals and **0** StructTech deals / audit leads.
- **Roles.** BMR = `owner` (Isaac), and the model supports `admin` / `office` / `field` (crew) / `client_portal_viewer` for when he adds people. Crew never see pipeline or dollar figures.
- **Ownership & attribution.** Leads have an owner; you can claim/assign/reassign. Every edit, stage change, note, and milestone records **who did it** — visible in the lead's Revision History.
- **Edit-by-ownership (built, matters once he adds reps).** A manager/owner edits any lead; a sales rep edits only leads they own and can't reassign leads away. Isaac as owner does everything.
- **Full CRUD everywhere (§2.6).** Every entity is editable / archivable / voidable from the UI — never requires us or SQL.
- **Agency layer (Jacob only).** You operate inside BMR via your `agency_admin` membership + the tenant switcher. Isaac never sees this.

## CRM / Pipeline — the core of Isaac's day

- **Kanban pipeline** with per-tenant stages (BMR's stages are seeded and configurable by us).
- **Add Lead** captures: first/last name, cell + secondary phone, email, **lead type** (Homeowner / Contractor-GC / Property Management / Commercial), **structured service address** + separate billing address, existing/requested roof types, remodel-vs-new, referral, tags, source.
- **Lead Control Center** (opens when you click a lead) — the command center, 3-panel on desktop/tablet, stacked on mobile:
  - **Left:** quick actions (Call · Text · Schedule · Log Activity), prospect data, **Owner** dropdown, **Tags**, **Pipeline Stage** dropdown, Edit-lead-details, Revision History.
  - **Center:** progress %, **command-stage tabs** (New Lead → Site Visit → Scope → Quote → Negotiating → Closed), and the active stage's **form == checklist** — every row is both a data field and a checklist item (empty → hint → tap to fill inline; filled → value + green check + edit). Live "X of N" completion.
  - **Right:** Lead Notes — author + timestamp on every entry.
- **Intake-call checklist** (config-driven) + **milestones** — site survey completed / scope ordered / quote presented, each logged with actor.
- **Mobile:** the full command center stacks; Notes + activity merge into one Log Activity feed.

**Expectations / limits to set:**
- **Follow-ups:** the system *schedules* day-2/day-5 follow-ups, but the automated **sender isn't built yet and they aren't displayed** — so don't promise automatic follow-up emails go out today.
- **Quick actions (Call/Text/Email):** these are **native links** — they open his phone's dialer / SMS / email app. They do **not** yet log the call/text in-app or send through an integration (Twilio/Gmail come later).
- **Views:** today it's the **kanban board + the Lead Control Center**. There's **no table or calendar view yet** (Stage 8).
- **Scheduling:** "site visit scheduled" is a date+time **field** on the checklist. There's **no real appointment/calendar system yet** (Stage 6) — the Schedule button is a placeholder for that.

## Estimating (contractor)

- Live on-site flow: **preliminary** (from the lead) → **on-roof validate** → **line-item present** → **sign** (e-signature).
- Carries the lead's **structured address** in automatically (no re-typing).
- Line items; PDF generation (pdf-lib); full edit/void from the UI.

**Limits:** PDFs are generated **on-demand, not stored** (cloud file storage / R2 isn't set up — `pdf_url` stays empty). The **on-site scope checklist does not yet auto-build the estimate** (Stage 7) — line items are entered on the estimate. Back-navigation polish in the wizard was flagged; confirm current state before demoing that step.

## Coordination (contractor)

- **Homeowner sign-off gate → work order → material list → schedule**, where **material ready-by dates gate the schedule** (you can't schedule ahead of materials).
- Materials and schedule blocks are fully add/edit/delete.

**Limits:** **No cross-job Gantt / master schedule yet** — you see one work order's crew+dates, not all jobs/crews on one timeline (this is flagged VITAL and is coming). Mobile layout tightening on the material/schedule rows was flagged; confirm before demoing on a phone.

## Field (crew)

- Crew mobile: **Today** home, **daily check-in**, **visual production packet**; **role-scoped** (crew see no pipeline, no dollars); **outdoor high-contrast mode** available via toggle (default off); large 56dp touch targets; **offline/sync status** shown.

**Limits:** check-in **photos are stored inline (base64)** — fine for a handful per check-in, not high volume (waits on R2). The annotated trim-map / pinned-photo layer isn't built (a text detail-list shipped instead).

## Delivery / Scan / Roadmap (StructTech-internal — *not* Isaac's)

- These are StructTech-only modules (the audit scan → roadmap → engagement/delivery portal). BMR **is not entitled** to them, so they won't appear in Isaac's workspace. Mentioned only so you know why they're not on his screen.

---

# PART 2 — WHAT'S COMING (scope + backlog)

## Next up — finishing CRM Depth (scoped, near-term)

- **Stage 6 — Scheduling.** Real appointments/site-visits per lead (type, time, duration, status); the **Schedule** quick action creates one and completes the Site Visit stage. (Google Calendar sync later.)
- **Stage 7 — Scope → Estimate wiring.** The on-site **scope checklist feeds the estimate/quote** — closes the survey→quote loop so scope data becomes line items.
- **Stage 8 — Views.** **Table + calendar** views alongside the kanban board.

## The platform payoff — configurability (the real differentiator)

- **Config editor (§12F).** Let a tenant **edit their own** stages, checklist fields, dropdown options, and pipelines — the "I'd just fix that myself" tooling. (Today we configure BMR for him; this hands him the controls.)
- **Pricing matrix.** Map checklist data points → pricing rules → estimate line items, so the quote generates from *his* checklist.
- **Multiple pipeline types** (sales / campaign / marketing / custom) and **self-serve onboarding** at scale.

## Near-term fixes & gaps (backlog)

- **Follow-ups need a home + a sender** (currently scheduled but dormant — not sent, not shown).
- **Docs section** — one place to view / download / send work orders + estimates (later invoices).
- **Per-lead next-action chip.**
- **R2 file storage** — persist estimate PDFs and field photos at real volume.
- **Gantt / cross-job crew schedule** (flagged VITAL).
- **Qualification + site-survey checklists** (two distinct checklists at two moments).
- **First-timer onboarding tour + Settings → Tutorial tab** (the walkthrough guide you raised — scope after watching Isaac Monday).
- **Intermittent `/select-workspace` bounce** — a session-refresh quirk to root-cause (harmless but can drop a mid-form input).

## Security follow-ups (before scaling beyond Isaac)

- **Edit-by-ownership at the database (RLS) level** — before any non-manager rep gets a login (today it's enforced in the app layer; Isaac as manager is unaffected).
- **`client_roadmaps` token leak** — its own migration, coordinated with the external portal.
- **Funnel null-org stopgap** — so StructTech's own funnel leads stop landing tenant-less.
- **Decommission the old standalone StructTech app** — it still reads/writes the same DB as a second, ungoverned door; reference-only for now, retire before scaling.

## Integrations (committed, staged — §13)

- **Google Workspace** — OAuth sign-in, two-way Calendar sync (visits/check-ins/scheduling), Gmail for follow-ups/updates.
- **Twilio** — SMS: instant lead-response text-back, client update texts, crew schedule push.
- **Stripe** — StructTech's own billing (tenant subscriptions / engagement billing → the $20K MRR) and, later, the shop checkout.
- **Runner-ups:** QuickBooks Online (accounting sync), aerial roof measurement (EagleView / Hover) to auto-generate the preliminary estimate from an address.

## North Star (later — foundation deliberately doesn't preclude these — §12)

- **AI assistant + semantic search** (conversational read/update; every action is already an RPC tool surface).
- **Client product catalogs + inventory** (accurate pricing off a real product list).
- **StructTech shop / distribution** (estimate prices against live shop prices → one-click reorder on signature).
- **Native mobile app** (App Store + Google Play, offline-first for the field).
- **Tenant-custom document templates** (branded estimates/invoices/work orders/proposals).

---

# PART 3 — "Don't over-promise" quick list

Say these are **coming**, not here, so Monday goes smoothly:

1. Automated follow-up **emails/texts don't send yet** (scheduled only).
2. Call/Text/Email buttons **open his phone**, they don't log or auto-send in-app yet.
3. **No table or calendar view** yet — kanban board + lead command center only.
4. **No real appointment/scheduling calendar** yet (the field captures a date/time; the Schedule flow is Stage 6).
5. The **scope checklist doesn't auto-build the estimate** yet (Stage 7).
6. **No cross-job master schedule / Gantt** yet.
7. **He can't self-edit** his checklists/stages/fields yet — we configure BMR for him until the config editor ships.
8. **No document download/send center** yet, and PDFs aren't stored (regenerated on demand).

Everything in that list is already scoped or backlogged — none of it is a surprise, and most of it is near-term.

---

## One thing to actually do before the call

Have **Isaac accept his invite and log in once** before Monday. Every check so far has been a database-level probe (rock-solid for the logic), but nobody has driven a real Isaac browser session yet — worth surfacing any first-login quirk (email delivery, the workspace-bounce) with time to fix, not live in front of him.
