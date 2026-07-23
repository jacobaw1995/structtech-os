# StructTech OS — Build Roadmap (reset 7/24/26)

**Supersedes `BUILD_PLAN_3WEEK.md` as the forward timeline.** That 3-week plan is complete and now
historical. `BACKLOG.md` stays the durable item queue; this file is the *sequence and cadence*.
`SCOPE.md` stays "what things are." When an item here is picked up it moves into the CLAUDE.md active
phase; when done, it's struck here and in BACKLOG.

---

## Where we are — the current base (live at os.structtek.com, Isaac using it daily)

**Solid underneath (done, verified, not to be re-litigated):**
- Foundation: Supabase auth, pooled multi-tenancy, workspace shell, roles + module entitlements.
- Security gate closed (Stage 5 A/B/C): RLS leaks fixed, Isaac seeded as BMR owner scoped to BMR only,
  ownership + actor attribution on every mutation, edit-by-ownership (RPC-level).
- Data: BMR's real book migrated clean (188 leads + notes + activity, attribution preserved). Isaac is
  now creating his own live leads on top.

**Working for Isaac end-to-end today:**
- **CRM / Lead Control Center** — the strong module. 3-panel command center, form==checklist, config-driven
  stages, owner assignment, author-stamped notes/activity. **Gating is advisory, never blocking (§2.8).**
- **Estimate builder** — just rebuilt as a document-as-editor (Joist model): the editor IS the customer's
  document. Manual/Guided toggle, inline line items, PDF parity, Present Mode (estimate-as-presentation).
- **Coordination** — exists: sign-off → work order → materials → schedule. *Sign-off is still a stub* (see A2).
- **Field** — exists: crew mobile, check-ins, production packet. *Clunky; open permission questions* (see A3).

**Recently shipped fixes (7/24):** explicit Edit affordance on contact fields, post-signature change
logging, the coalesce/clear systemic fix on the deals path, the NULL-authorization security gap.

---

## How this roadmap works (read before using it)

1. **Depth over breadth — the standing mandate (§2.8, Isaac 7/20):** no new modules until what exists is
   *chosen over the old app*, not merely tolerated. Phases A→B are all depth on the live surface.
2. **Every week has ONE primary goal + a reserved bug/support lane** (~1 day / ~25% capacity) for whatever
   Isaac surfaces. A churn-risk bug **preempts** the week's goal; an unused lane **pulls the next item forward.**
   This is structural, not optional — a live client generates work that can't be scheduled in advance.
3. **Near term is week-detailed; later phases are directional.** Don't pretend to know Week 8 precisely.
4. **Sequence is a recommendation, reorderable** — but A comes before B before C for real reasons noted below.

---

## Tracking artifacts + update cadence (standing rule, Jacob 7/24)

**✅ LIVE (7/24): the in-app Build Tracker** — StructTech-internal module at `/w/[orgId]/build`, 66 items
seeded, full CRUD with who-changed-what attribution. **It is now THE authoritative source for feature
status.** Edit it in the app/DB, not a file. First real use = flip the Phase A items to `in_progress` as
we pick them up.
- **`ROADMAP_MATRIX.html`** — RETIRED (fully superseded by the tracker; deleted).
- **`ROLLOUT_CHECKLIST.md`** — kept as a **subordinate task-level working doc** (per-feature build steps the
  coarse tracker rows don't hold). Status-of-truth defers to the tracker; as each feature is executed its
  task detail migrates into that tracker item's `notes`, and the checklist shrinks toward retirement.
- **`ROADMAP.md`** (this file) — stays: narrative, phase sequencing, cadence rules.

**Update cadence — non-negotiable, this is how we avoid losing our place:**
1. **At least twice per phase** — once at phase start (mark items in-flight), once at/near phase end (mark done, surface slippage).
2. **Before any bug-fix detour** — when we drop the phase work to chase a bug, **update the matrix + checklist FIRST** so we have a clean marker of exactly where to resume. (This is the specific failure mode that made the 7/24 re-baseline necessary.)
3. **On completion of any checklist item** — tick it; don't batch.
Not expected daily. The trigger is "phase boundary, or we're about to context-switch."

---

## PHASE A — Finish the depth pass (make what exists real) · ~Weeks 1–3

The Isaac mandate. Each of these is a module he touches that currently under-delivers.

**Week 1 — Assistant role + P0.5 close-out**
- **(c) Admin-assistant capability role** (in flight). Her real profile: sees all leads, adds notes,
  schedules; does NOT see financials or estimates. Server-side field-stripping, not UI-hiding. Resolve the
  three documented interactions (edit_leads × C3 ownership; capability × role precedence; edit × view_financials).
- **Finish P0.5** — apply the deals JSONB-patch convention (or explicit clear-flags) to the estimate,
  line-item, and production-packet update RPCs. **Decide the convention once**, don't refight per table.
- *Bug lane.*

**Week 2 — The signing system + coordination sign-off becomes real**
- **Signing is a SYSTEM, not a row** (BACKLOG): two paths on shared infra — **in-person** signature, and
  **remote** (tokenized email link → customer signs on their device → OS updates → signed copy auto-emailed
  back). Built once, used by estimate signing AND coordination sign-off.
- **Pull Resend/SMTP forward from Phase D into here** — remote signing, password reset, and homeowner
  invites all depend on reliable email; do it once, early.
- Coordination sign-off: replace the color/finish stub with real signature capture (both paths), a
  **generated signed document** on the job, and the copy **delivered to the homeowner.** (Interim
  change-after-sign-off logging already shipped; this is the real thing.)
- *Bug lane.*

**Week 3 — Field depth + a home**
- **Field module:** answer + fix the open questions — can Isaac (office) create/upload roof data himself,
  and can crew edit/delete a file he uploaded (real per-role file permission model)? Plus the UX pass.
- **Dashboard / home view** — there's currently no overview; nav drops you straight into pipeline. A simple
  at-a-glance home (open leads, today's schedule, recent activity).
- *Bug lane.*

**Exit criteria for Phase A:** Isaac would pick StructTech OS over his old app for his whole day —
lead → estimate → signed → coordinated → field — without hitting a stub.

---

## PHASE B — The differentiator: Present Mode as a real sales deck · ~Weeks 4–5

Not "the estimate rendered nicely" — a multi-section **presentation that sells the roof**, walked through
on a tablet at the kitchen table, closing with a signature (roofdocsstudio.com is the reference). The
estimate builder is done, so the investment summary now has a source. **Assembles existing data** (no
re-entry applied to selling): lead → cover, checklist + photos → findings, roof-type/catalog → the product
section, line items → investment summary. New pieces it needs: a testimonials table and a payment schedule
(30/40/30) on the estimate. Tablet-first, printable, per-tenant branding.

*This is the first thing that makes a prospect say "I've never seen this from a roofer" — the sales edge.*

---

## 🏠 CUSTOMER / HOMEOWNER PORTAL — directed, was un-scoped, now placed (full spec in BACKLOG)

The contractor's END customers get a portal for *their* job — signed docs, schedule, progress, photos.
A core differentiator Jacob directed early; it had no home until 7/24. **Distinct from the `delivery`
portal** (StructTech→contractor); this is contractor→homeowner, the same pattern one level down.
Heavy part = a **new external actor class** (homeowners aren't `org_members`; per-job scoped access via
tokenized links / light accounts + scoped read paths). Depends on Phase A (real sign-off + docs) + email;
wants R2 for photos. **Default slot: Phase C (v1 read-only).** Jacob flagged it *critical* — open question
whether v1 pulls ahead of or alongside Present Mode (B). Present Mode wins the job; the portal delivers the
after-experience. Both are customer-facing edges a contractor would license the platform for.

## PHASE C — Second-client readiness (make "one build, licensed per tenant" real) · ~Weeks 6–8

Everything so far served one tenant by hand. This phase is what lets a second contractor onboard as config,
not engineering — the actual business model.
- **Config editor** — let a tenant self-edit stages, checklist fields, dropdown options (kills the recurring
  "CC tweaks the config" friction; the data model already supports it).
- **Pricing matrix** — checklist data points → pricing rules → estimate line items (the Guided-mode payoff;
  hooks already laid: stable scope keys + `product_id`).
- **Security for multi-user tenants** — tighten edit-by-ownership to the RLS layer *before* any non-manager
  rep gets a login; the assistant role (Phase A) is the first test of this.
- **Stand up a second contractor tenant** ("StructTech Test Co") — proves the onboarding-is-config claim and
  gives a permanent safe test environment (today all testing risks Isaac's live data).

---

## PHASE D — Integrations + platform maturity · ongoing, slot as pulled forward

- **Google Workspace** (OAuth sign-in, Calendar sync, Gmail for follow-ups) · **Twilio** (SMS lead
  response) · **Stripe** (tenant billing — the $20K MRR path).
- **Auth maturity:** self-serve password reset + Resend SMTP (reliable invites/recovery) — do together.
- **Docs section** (view/download/send work orders + estimates) · **follow-ups a home** (they're scheduled
  but inert) · **first-timer onboarding tour + Settings tutorial tab.**

---

## Parking lot — real needs, not yet sequenced

- **Cross-job crew Gantt** (flagged VITAL — master schedule across all jobs/crews; deferrable only while the
  crew is small).
- Scheduling depth (appointments/calendar) · table + calendar CRM views · global search (currently a stub) ·
  next-action chip · R2 file storage (PDFs + field photos at volume) · qualification/site-survey checklists ·
  roof-type touch picker · `/select-workspace` session-bounce root cause.
- **Security debt:** `client_roadmaps` token leak (portal-coordinated migration) · funnel null-org stopgap ·
  decommission the old standalone StructTech app (second door into prod DB).
- **North Star (§12):** AI assistant + semantic search · client product catalogs · StructTech shop ·
  native mobile app · editable document-template system. Foundation preserves these; none built now.

---

## The standing bug-fix / support lane (the thing you asked to protect)

Isaac is live, so real-world bugs and requests arrive on his schedule, not ours. Rather than let them
derail a phase or pile up unlogged:
- **~1 day per week is reserved** for Isaac-surfaced bugs, support, and small requests. It's part of the
  plan, not stolen from it.
- **Churn-risk bugs preempt** the week's primary goal (the gating removal and the estimate-creation hotfix
  were both this — correctly jumped the queue).
- **Everything gets logged in BACKLOG first**, triaged into P0 (preempt) / P1 (this phase) / later, so
  nothing lives only in a side chat. That's the exact hygiene gap that made this reset necessary.
- **Every week ends by reconciling BACKLOG** — mark done what shipped, don't only add new items.
