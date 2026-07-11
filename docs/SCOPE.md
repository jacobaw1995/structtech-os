# StructTech OS — Master Scope (v1)

**Owner:** Jacob · **Controller:** pm-app-controller skill · **Locked:** 7/8/26
**Status:** IA locked from wireframes (turns 1a–1e, 2a–2i). Field module frame pending from designer. Codebase anchor provisional (see §9).

---

## 1. What StructTech OS is

**One modular, multi-tenant platform** that runs StructTech's own business *and* is licensed, in configurable pieces, to StructTech's clients. Not two products — one build, where each tenant is granted only the modules it pays for.

StructTech is simply the **first and most-entitled tenant** of its own OS. A contractor client (Brothers Metal Roofing) is a tenant with a subset of modules. Onboarding a new client is a **config action — inserting rows — not an engineering project.**

This supersedes the earlier "internal tool vs. client construction platform" split. The construction/field capabilities are **modules a contractor is entitled to**, not a separate app. (`structtech-pipeline` was already a fork of the BMR app — the duplication this scope ends.)

### The business goal it serves
Productized delivery that carries a client from **scan → sold → delivered → proven → testimonial**, with end-to-end clarity, driving toward **$20K MRR** (3 consecutive months + 3 testimonials from transitioned engagements). MRR comes from (a) StructTech's own engagements and (b) licensing OS modules to clients.

---

## 2. Core principles (non-negotiable)

1. **One build, licensed per tenant.** Never fork per client. Differences are config (entitlements + flags), not code.
2. **Two axes of access:** *tenant entitlements* (which modules exist) × *user roles* (which screens a person sees). Nav bends to both.
3. **No re-entry.** Each step is generated from the last — lead → estimate → signed → work order → materials/schedule → field → testimonial. The connective tissue is the product.
4. **Field-first where it's a field tool.** Estimating and Field modules pass the "Roof Test": one-handed, gloves, bright sun, large touch targets (56dp), outdoor high-contrast mode.
5. **StructTech operates on top of client tenants** (agency layer) — it is not a peer tenant sitting beside them.

---

## 3. Tenant model

| Tenant type | Example | Gets |
|---|---|---|
| `internal` (agency) | StructTech | Everything, plus the agency operator layer (switch into any client tenant) and StructTech-only modules (Scan/Roadmap, Delivery) |
| `contractor` | Brothers Metal Roofing | A licensed subset (Pipeline, Estimating, Coordination, Field) + its own StructTech-delivery view |

**Agency operator layer (wireframe 2a, 2h):** Jacob logs in, lands in the StructTech workspace, and uses a **tenant switcher** ("▾ Brothers Metal Roofing ↩ back to StructTech", "viewing as: agency admin") to operate inside a client tenant. Login shows workspace selection when a user belongs to more than one.

**Escape hatch:** a future enterprise client demanding hard data isolation can be **siloed onto its own database** without a code change — same build, different connection. Pooled by default, siloable later.

---

## 4. Module registry (the app suite)

| Module | Who's entitled | What it is | Wireframe |
|---|---|---|---|
| `crm` / Pipeline | all | Kanban with **per-tenant stage config**, deal panel, next-action + auto follow-up | 1b, 2b |
| `estimating` | contractor | Live on-site estimate: preliminary (from lead) → on-roof validate → line-item present → sign | 1c, 2c |
| `coordination` | contractor | Homeowner sign-off gate → work order → material list → schedule (material ready-by **gates** scheduling) | 1d, 2d |
| `field` | contractor | Crew mobile: Today home, daily check-in, visual production packet (role = crew) | 2f (+ pending frame) |
| `delivery` | internal (operator) + surfaced read-only in client tenant | Engagement execution: levels/milestones/check-ins that drive the client portal | 2i (admin) / 2e (client) |
| `scan` + `roadmap` | internal only | Public Revenue-Leak scan → auto-generated roadmap (already live) | — |

---

## 5. Roles (per tenant)

Entitlements decide the module set; **roles decide the screens within it.** Minimum roles:

- **Owner / admin** — full tenant, dashboard, financials
- **Office / coordinator** — pipeline, coordination, estimating
- **Field / crew** — Field module only; **no pipeline, no dollar values** (wireframe 2f)
- **Client-portal viewer** — read-only delivery view + confirm own items (§7)
- **Agency admin** (internal only) — operate across client tenants

Three-layer RBAC from the controller skill applies: per-module level (None/Read/Standard/Admin) → granular flags → item-level roles. Subcontractors/crew never see budget or financials.

---

## 6. The client journey (no re-entry) — wireframe 2g

```
Lead ─generates→ Preliminary estimate ─validated on-roof→ Signed estimate
   ─generates→ Work order ─gates→ Materials + schedule ─→ Field / done ─→ Testimonial
```

Each artifact is generated from the prior one, never re-keyed. This flow is the spine of "absolute clarity across the client journey."

---

## 7. Confirmed architecture decisions

1. **Pooled multi-tenancy.** One shared database; every tenant separated by `org_id` + RLS. License activation = insert `organizations` + `tenant_modules` + memberships. **Not** schema-per-client or DB-per-client. (Siloable escape hatch per §3.)
2. **Delivery portal lives *inside* the client's own tenant** — a nav item in BMR's workspace ("StructTech Roadmap" / Delivery), not a separate login. One workspace, one build. *(Confirmed 7/8.)*
3. **Portal interaction:** read-only for level/milestone **status** (StructTech marks those), but the client **can confirm/reschedule check-ins and attest their own ADOPT/PROVE behaviors.** Amends the "read-only v1" line in the schedule spec. *(Confirmed 7/8.)*
4. **DB consolidation via strangler, not big-bang.** Build the OS on the `structtech` Supabase project (richer schema: deals, engagements, roadmap). BMR keeps running on its own project during this week's fixes; folds in as tenant #1 at parity. No risky one-shot migration of a live client's data.
5. **Auth:** Supabase Auth + org-scoped RLS replaces the admin's soft SHA-256 gate. This is the merge-enabler, built first.

---

## 8. Tech stack (decided — from controller skill)

Next.js 14 App Router + TypeScript (web) · Supabase (Auth + Postgres + Realtime) · Cloudflare R2 (files/photos) · React Native + Expo + PowerSync/SQLite (mobile field, later) · Resend (email) · pdf-lib (estimates/PDFs) · Make.com scheduled scenario (follow-up sends). Supabase + App Router mandatory patterns (getSession before DB, security-definer RPCs for inserts/single fetches, `get_my_project_ids()`-style RLS) apply verbatim.

---

## 9. Data model direction

**Extend the `structtech` project** — do not restart:

- **New foundation tables:** `organizations` (tenant_type), `tenant_modules` (org_id, module_key, enabled, config), `memberships` (org_id, user_id, role). Every domain table carries `org_id`; RLS scopes by org.
- **Reuse existing:** `audit_leads`, `client_roadmaps`, `roadmap_playbook()`, `deals` + `follow_ups` (CRM v1), `engagements` / `engagement_levels` / `engagement_milestones` / `engagement_checkins` (delivery schema — already live, seeded).
- **New per module:** estimating (estimates, line_items, signatures), coordination (work_orders, material_items, schedule_blocks with ready-by gating), field (check_ins, production_packets).
- Inserts and single-record fetches via **security-definer RPCs** per OS patterns.

---

## 10. Non-goals / out of scope

- **Not** the enterprise Procore-competitor construction platform. The controller skill's deep construction modules (RFIs, submittals, AIA pay apps, P6 Gantt, BIM) are **future module candidates**, not v1.
- **Not** rebuilding "The Field" as a separate product — its concepts become the `field` and `coordination` modules.
- No AI layer, no per-level invoicing, no computer vision in this scope.
- The codebase anchor (BMR app as OS base) is **provisional** pending this week's BMR fixes; decided after those settle.

---

## 11. Open items

- Field module frame (daily check-in + visual production packet) — back from designer.
- Codebase anchor final call — after BMR feedback fixes.
- Security workstream (granular RLS on all tables, enable RLS on `structtech_state`) — dedicated session before client-visible data goes live.
- Targeted hi-fi on client-facing surfaces only: portal (2e) + estimating (2c).

---

## 12. Future / North Star (not v1 — foundation must not preclude)

These are near-certain future capabilities. We do **not** build them now, but every foundation decision is made so they drop in without a rebuild.

### A. AI assistant + semantic search
Conversational read/update of projects ("what's the status of X" / "update Y with…") behaving like a personal assistant.
- **Why the foundation already supports it:** every mutation is a named security-definer RPC (that becomes the assistant's tool surface); org-scoped RLS means the assistant runs *as the user* and can't leak across tenants; append-only activity gives it a timeline to summarize; Supabase `pgvector` powers semantic search (enable when we get there).
- **Preserve now:** RPC-as-action-layer and append-only activity on every entity.

### B. Client product catalogs + inventory
Clients add their full product list for accurate pricing and material/inventory tracking.
- Just another org-scoped module (`products`/pricing/stock), entitled per tenant.
- **Preserve now:** estimate line items (Week 2) must allow an **optional `product_id`** link, not free-text only — that nullable link is how catalogs plug into pricing later.

### C. StructTech shop / distribution integration — the vertical-integration payoff
StructTech's online metal-roofing supply shop, baked in: a roofer's estimate prices against StructTech's **live shop prices**, and once the job is signed they place the order in one click. Prototype already exists in `../structtech-x-windyhill` (Stripe, supplier checkout, catalog, configurator).
- **New concepts to model when built (don't preclude):**
  - **Controlled cross-tenant catalog** — StructTech's published prices readable by entitled contractor orgs. A deliberate, explicit exception to strict org isolation (a "published/supplier" visibility path) — not a hack.
  - **Price snapshot** — estimate lines capture the price at time-of-estimate (lock the quote) while referencing the live price for reorder.
  - **Order/commerce domain** extends the no-re-entry journey: estimate (priced from shop) → signed → purchase order to the shop → fulfillment.

**Non-negotiable now (so none of the above gets boxed out):** business logic lives in RPCs/server actions (not components); append-only activity everywhere; org isolation is the default but not so hard-wired that a shared supplier catalog becomes impossible.
