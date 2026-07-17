# CRM Depth — Stage 5: The Go-Live Gate (security + accounts + ownership)

**Purpose:** make StructTech OS safe to hand a real client login (Isaac). This is the one
stage where the security half is a hard gate — no client account may exist until Track A is
advisor-clean. Grounded in a **live audit of the `structtech` Supabase project
(`ejlhrykcdfcyeooooodx`) on 7/17**, not stale assumptions.

---

## Live audit — what's actually true right now

**Reassuring:**
- **RLS is enabled on every `public` table** (37/37), including `audit_leads` and
  `structtech_state`. The backlog item "enable RLS on structtech_state" is already done.
- The **core member-facing tables are correctly org-scoped**: `deals`, `deal_notes`,
  `deal_activity`, `estimates`, `estimate_line_items`, `work_orders`, `material_items`,
  `schedule_blocks`, `follow_ups`, `tenant_modules`, `organizations`, `org_members` all carry
  `org_id IN (my_org_ids())` member policies (plus an `is_staff()` platform-admin catch-all,
  which is fine — `staff_users` is StructTech-internal only).
- The `is_staff()` legacy tables that are **internal-only** (`engagements*`, `tickets`,
  `ticket_messages`, `org_systems`, `org_invites`, `org_invoices`, `staff_*`) are *correctly*
  staff-gated — contractors shouldn't see them. So the backlog's "migrate everything off
  is_staff → my_org_ids" is **mostly unnecessary**; is_staff() is the right platform-admin gate
  for internal tables. Do NOT blanket-rip it out.

**The real leaks (RLS is on, but the policy says `true` — worse than it looks, because it
*appears* protected):**

| Table | Policy | Problem |
|---|---|---|
| `audit_leads` | `Allow authenticated read` (SELECT `true`) | **Any logged-in user reads every tenant's inbound leads.** |
| `audits` | `all_audits` (ALL `true`/`true`) | Wide open to everyone — read + write. |
| `proposals` | `all_proposals` (ALL `true`/`true`) | Wide open (StructTech-internal data). |
| `prospects` | `all_prospects` (ALL `true`/`true`) | Wide open. |
| `client_roadmaps` | `update roadmap milestones` (UPDATE `true`/`true`) | Anyone can write any roadmap. (The token-scoped SELECT is likely the intended client-portal read — confirm before touching.) |
| `profiles` | `pipeline_profiles_select` (`is_pipeline_user()`) | **`is_pipeline_user()` = "has any profile row."** So any profiled user reads **every** user's profile (name/email) across all tenants. |
| `lead_appointments` | `lead_appointments_manage` / `_select` (`is_pipeline_user()`) | Same gate → any profiled user reads/writes **every tenant's** appointments. (This is the Stage-6 scheduling table, already scaffolded.) |

**The trap:** `is_pipeline_user()` is `exists(select 1 from profiles where id = auth.uid())` —
it means "is any logged-in app user," NOT org-scoped. The moment Isaac gets a profile (Track B),
he'd read every tenant's profiles + appointments. So `profiles` and `lead_appointments` MUST be
re-scoped in Track A, before his account exists.

**Helper hardening:** `is_staff()`, `is_platform_admin()`, `is_pipeline_user()` are all
`SECURITY DEFINER STABLE` with `SET search_path=public`. **`my_org_ids()` is the exception — it
has no pinned search_path.** Add `SET search_path=public` to it.

**Users / membership today:**
- `jacob@structtek.com` — has profile; `org_members`: **owner** of StructTech (internal) +
  **agency_admin** of Brothers Metal Roofing (contractor). This is the working membership model.
- `jacobaw1995@gmail.com` — **no profile, not in org_members** (a secondary/Cowork identity). This
  is the "1 auth user without a profile."
- **Isaac does not exist yet** — no auth user, no profile, no membership.
- BMR org_id: `9d32b5a9-e11e-401b-8fa7-969065b004ce` · StructTech org_id: `034db6f4-bb39-4ffa-9c83-a064d1a8ef98`.

---

## Track A — Security (HARD GATE; lands + advisor-clean before any client login)

**A0. Verify + inventory.** CC re-confirms against live: enumerate every policy with `qual=true`
or `with_check=true`, plus the `is_pipeline_user()`-gated set, plus INSERT-policy `with_check`
bodies on the member tables (they show `qual=null`; confirm they can't insert arbitrary `org_id`).
Produce a short findings table before writing DDL.

**A1. Kill the wide-open leaks.** One migration, per table:
- `audit_leads`: drop `Allow authenticated read`. Replace with org-scoped read
  (`org_id IN (my_org_ids())`) **and** keep the `is_staff()` platform-admin ALL policy. Keep the
  anon INSERT (public marketing lead-capture) — but confirm the capture path sets `org_id`.
- `audits`, `proposals`, `prospects`: no `org_id`, StructTech-internal, **not referenced anywhere
  in `src/` (grep-confirmed 7/17)** — the only writer is Jacob's external funnel automation. Replace
  `all_*` `true` with `is_platform_admin()`. **Safety net:** the funnel is backend (likely
  service-role → RLS-bypassed → unaffected); if it happens to use the public key, its inserts will
  fail — detectable via a single test lead, fixed by adding an `audit_leads`-style anon-INSERT policy.
  So: apply, then Jacob smoke-tests the funnel before Track B proceeds. (`proposals` here is
  StructTech's internal Present-Mode table; contractors' proposal-on-inspection flow is the
  org-scoped `estimates` wizard — a future contractor proposal module gets its own org-scoped table.)
- `client_roadmaps`: drop the blanket `UPDATE true`. Writes go through an org-scoped policy or a
  security-definer RPC with a token check. **Confirm the client-portal design first** — the
  token-scoped SELECT may be intentional public read; don't break the portal.
- `profiles`: re-scope `pipeline_profiles_select` from `is_pipeline_user()` to
  "self or shares an org with me" (`id = auth.uid() OR id IN (select user_id from org_members
  where org_id IN (my_org_ids()))`). Keep `update own` (`id = auth.uid()`).
- **Legacy `lead_*` cluster** (`leads`, `lead_notes`, `lead_activity`, `lead_appointments`,
  `pipeline_invites`): CONFIRMED 7/17 these have **no `org_id`** and are gated only by
  `is_pipeline_user()` (= any profiled user) — a cross-tenant leak the moment Isaac gets a profile.
  The live app runs on `deals`/`deal_*` (already org-scoped); this cluster appears unused.
  **Deny-by-default: lock all five to `is_staff()` now** (zero schema change, closes the leak).
  Grep first to confirm no authenticated-member code path reads them; if one exists, stop and flag.
  Proper org-scoping (add `org_id` + backfill, or rebuild appointments against `deal_id`) is a
  deliberate **Stage 6** follow-up when real scheduling is built — re-opening a locked table is a
  reviewed step, not a rushed one. (Supersedes the earlier "re-scope lead_appointments to
  my_org_ids" note — it has no org_id.)

**A2. Harden helpers + all advisor-flagged functions.** Pin `SET search_path=public` on every
function the security advisor flags for mutable search_path — `my_org_ids()` plus the 7 others
(`protect_roadmap_columns`, `roadmap_playbook`, `auto_create_roadmap`, `generate_roadmap_for_lead`,
`build_roadmap_levels`, `accept_invite`, `touch_leads_updated_at`). Additive, zero-logic. Before
pinning each, confirm no unqualified cross-schema call in the body (extension/`auth.*` referenced
bare); qualify or extend the path if so. "Advisor-clean" (A3) is the DoD, so clear all of them.

**A3. Advisor gate (verification).** Re-run the Supabase **security advisor**; Stage 5 does not
proceed to Track B seeding until it reports no critical RLS/exposure findings on these tables.
This is the definition-of-done for Track A.

---

## Track B — Accounts (after A is advisor-clean)

Confirmed schema (7/17): `profiles` = `id`, **`full_name` NOT NULL, `email` NOT NULL**, `role`
`pipeline_user_role` (enum: `salesman`/`manager`, default `salesman`). `org_members.role` CHECK =
`owner`/`admin`/`office`/`field`/`client_portal_viewer`/`agency_admin`/`member`. **No trigger exists
on `auth.users` today** (why `jacobaw1995` has no profile). Post-Track-A, nothing references
`is_pipeline_user()`/`is_pipeline_manager()` — a profile alone grants nothing.

**B1. Guarantee a profile per auth user (the flagged prerequisite).** `handle_new_user()`
SECURITY DEFINER, `SET search_path=public`, `AFTER INSERT ON auth.users FOR EACH ROW` → insert
`profiles(id, full_name, email)` with `full_name = coalesce(nullif(raw_user_meta_data->>'full_name',''),
nullif(raw_user_meta_data->>'name',''), email)` (never NULL), `email = new.email`, role default;
`ON CONFLICT (id) DO NOTHING`. **Backfill generically** (not hardcoded): insert profiles for every
`auth.users` with no matching row (covers the one orphan). Reconciles auth.users↔profiles. `jacobaw1995`
has no org membership, so a profile is harmless — but flag to Jacob: keep or delete that stray login.

**B2. Seed Isaac — as a member, never as staff.** Order: (1) apply B1. (2) **Jacob invites Isaac from
the Supabase Auth dashboard** (Authentication → Users → Invite) — creates the auth user + fires B1 →
profile auto-created; not a raw `auth.users` insert. (3) SQL inserts one `org_members` row: Isaac →
BMR org (`9d32b5a9-e11e-401b-8fa7-969065b004ce`), role **`owner`** (look up his id by email). (4) Set
his `profiles.role = 'manager'` (BMR owner needs manager-level pipeline access for Track C). **Never
add him to `staff_users`** — that's StructTech platform-admin and grants cross-tenant access. BMR-only
scope then flows from `my_org_ids()`. (5) Verify: `my_org_ids()` for Isaac = [BMR only]; probe that he
reads BMR deals but 0 StructTech rows. Needs from Jacob: **Isaac's email + full name.** Crew logins
deferred (crew stays free-text `crew_name` for now).

---

## Track C — Ownership & attribution (after B; the CRM-depth substance)

**C1. Owner assignment.** Confirm/add `owner_id` on `deals`; wire the existing `OwnerSelect`
component to real org members (now that profiles are guaranteed). Claim / assign / reassign.

**C2. Actor identity on every mutation.** `add_deal_note` already stamps `created_by` from
`profiles` (Stage 4). Extend the same auth.uid()→profile stamping to deal edits, stage changes,
and the activity log — "*who* changed it," not just when.

**C3. Edit-by-ownership.** Enforce in the mutating RPCs: a salesman edits leads they own;
manager/owner edits any lead in their org. Map to SCOPE §5 roles (owner / manager·office /
salesman). Role check lives in the security-definer RPCs, not just the UI.

---

## Sequencing rule (non-negotiable)

**A (advisor-clean) → B1 (profiles trigger, anytime) → B2 (Isaac's login) → C.**
Track A must be fully verified before B2, because the instant Isaac can authenticate, every
`true` / `is_pipeline_user()` policy becomes live cross-tenant exposure. Build and review Track A
as its own commit + advisor run; do not bundle Isaac's account into the same push.
