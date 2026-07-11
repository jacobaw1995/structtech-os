# StructTech OS — 3-Week Build Plan

**Owner:** Jacob · **Controller:** pm-app-controller skill · **Written:** 7/8/26
**Window:** ~3 weeks (Jul 8 → Jul 29) · **Source of truth:** `SCOPE.md` + locked wireframes (1a–1e, 2a–2i, 3a)
**Goal:** functional pipeline, project coordination, and live estimating — on the multi-tenant foundation, for one tenant vertical slice (BMR as tenant #1).

---

## Ground rules

- **"Functional," not polished.** A working vertical slice a real user can run end-to-end. Polish comes after.
- **One tenant path first.** Prove BMR (contractor) + StructTech (agency) before generalizing.
- **Must-hit is Weeks 1–2** (foundation + pipeline + estimating). If anything slips, it's Week-3 scope, never the foundation.
- Every insert/single-fetch via security-definer RPC; `getSession()` before DB; RLS scoped by `org_id`. (OS patterns, non-negotiable.)

---

## Week 0 — this week, in parallel (input, not OS build)

- [ ] **BMR feedback fixes** on the live BMR app. Capture each change as a decision — it's the spec for the `estimating` / `coordination` / `field` modules.
- [ ] **Codebase anchor call** after fixes settle: BMR app as OS base vs. clean start. (Leaning BMR — it already has estimating, e-sign, PDF, field surface.)
- [ ] Stand up target: confirm build happens on the `structtech` Supabase project; BMR stays on its own project until parity.

---

## Week 1 — Foundation (the unlock)

**Goal:** multi-tenant shell people log into, seeing only what they're entitled to.

- [ ] Tables: `organizations` (tenant_type), `tenant_modules` (org_id, module_key, enabled, config), `memberships` (org_id, user_id, role). `org_id` + RLS on every domain table.
- [ ] **Supabase Auth** replaces the admin SHA-256 gate. Login → workspace select when user has >1 org (**wireframe 2h**).
- [ ] **App shell + top bar + tenant switcher** — agency operator can switch into a client tenant ("↩ back to StructTech", "viewing as: agency admin") (**2a**).
- [ ] **Entitlement-driven nav** — sidebar renders only entitled modules; route guards enforce it.
- [ ] **Role-scoped nav** — role decides screens within the module set (crew ≠ owner).
- [ ] Seed two orgs: StructTech (all modules) + BMR (crm, estimating, coordination, field).

**Done =** log in → land in your workspace → see only your modules → agency admin can switch into BMR and back.

---

## Week 2 — Pipeline + Live Estimating (revenue-facing)

**Goal:** BMR runs lead → on-site estimate → signature.

**Pipeline / CRM (2b, 1b)**
- [ ] Kanban with **per-tenant stage config** (BMR funnel vs. StructTech `new_scan…closed_won`) — same board component, config-driven.
- [ ] Deal panel: value, stage, notes, append-only activity, won/lost + reason.
- [ ] **Next-action chip + scheduled follow-up** (day-2 / day-5), cancelled on stage advance. Sends via Make scenario (later) — schema + UI now.
- [ ] Empty state.

**Live Estimating (2c, 1c)**
- [ ] Preliminary estimate **auto-generated from the lead** (no re-entry).
- [ ] On-roof validate & adjust (squares, pitch, adders) → recalc.
- [ ] Present with **line items above the total**; **outdoor high-contrast** toggle.
- [ ] Sign (mobile) → confirm & send copy. Reuse existing pdf-lib + sign-token flow.

**Done =** a BMR lead becomes a signed estimate on a phone, on-site, with the number generated from the lead.

---

## Week 3 — Coordination + Field + Delivery/Portal (clarity)

**Goal:** signed job flows into execution; StructTech engagement visible to the client. *(Overloaded — see triage.)*

**Coordination (2d, 1d)**
- [ ] Flow: signed → **homeowner sign-off (colors/finishes)** → work order → material list → schedule.
- [ ] **Material ready-by gates scheduling** — earliest start clamped to latest ready-by; blocked = flagged.

**Field (3a)**
- [ ] Crew "Today" home (assigned jobs, outdoor-mode default, no Pipeline/$).
- [ ] **Daily check-in** — photos, hours, materials used, blockers; sub-60-second, ≥56dp targets.
- [ ] **Visual production packet** — trim map, boot/vent placements, custom-detail callouts, built from work order + sign-off photos.

**Delivery + Portal (2i, 2e)**
- [ ] Delivery admin: `create_engagement_from_roadmap` at `closed_won`; tick milestones, set week-of windows, log check-ins; on-track/at-risk (**2i**).
- [ ] Client portal **as a module inside the client's tenant**: level bars, milestone diamonds, WIN CONDITION strip, expandable milestones w/ owner tags, next-check-in chip. Read-only status; **client confirms check-ins + attests own ADOPT/PROVE** (**2e**).

**Week-3 triage (if time is short):** protect **Coordination** (it's a stated 3-week target). **Field** and **Portal/Delivery** are the slip candidates → Week 4. Foundation/Pipeline/Estimating never slip.

**Done =** signed job produces a work order + gated schedule; crew logs a daily check-in; StructTech engagement shows in BMR's portal.

---

## Dependencies

```
Week 1 Foundation ──┬── Pipeline ──┬── Estimating (needs lead)
(auth/org/RLS/nav)   │              └── Coordination (needs signed estimate) ── Field (needs work order)
                     └── Delivery/Portal (needs auth + engagement data)
```
Nothing client-facing ships before Week 1. Estimating needs the lead; Coordination needs the signed estimate; Field needs the work order.

---

## Parallel track — targeted hi-fi (not blocking)

Only the **client-facing** surfaces get hi-fi, done in the design tool while Week 1 builds:
- Client portal (2e) · Live estimating (2c).
Internal boards stay lo-fi + default design system.

---

## Risks

1. **Scope > time.** All four Week-3 modules at once is unrealistic; triage above is the release valve.
2. **DB consolidation.** Strangler, not big-bang — BMR's live data folds in at parity, not mid-sprint.
3. **Security debt.** Granular RLS + `structtech_state` RLS is a required dedicated session before client-visible data goes live — schedule it, don't skip it.
4. **Codebase anchor unresolved** until BMR fixes land — Week 1 foundation work is anchor-agnostic enough to start regardless.

---

## Definition of "functional" (the 3-week demo)

Log in as Jacob → operate StructTech, switch into BMR → move a BMR lead through the pipeline → generate + present + sign an on-site estimate → that signed job produces a work order + a materials-gated schedule → (stretch) crew logs a check-in and the client sees the engagement in their portal.
