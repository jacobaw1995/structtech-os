# StructTech OS — Go-Live Plan

**Owner:** Jacob · **Written:** 7/12/26
**What this is:** the track that takes StructTech OS from "Jacob's local dev against the live DB" to "BMR (and future clients) using it for real." Separate from the feature stages (Weeks 1–3) — this is the operational path to production.

**Sequence (do in this order):**
finish Week 2 (estimating) → **security workstream** → **BMR data migration** → **Vercel deploy + domain** → BMR go-live. Week 3 (coordination/field) can run in parallel or after; it's needed for full operational parity but not for the sales-side cutover.

---

## 1. Security workstream — the hard gate before ANY non-Jacob login

Nothing below matters until this is done, because today a logged-in non-staff user could read across tenants. **No client accounts get created until this passes.**

- [ ] **`audit_leads` permissive read.** Replace the pre-existing "Allow authenticated read" policy (`qual = true` — any logged-in user reads every lead) with org-scoped + staff-only read. (Flagged in SCOPE §11; the Week 2 RLS migration's org policy is a no-op until this lands.)
- [ ] **`structtech_state` RLS.** Currently disabled — exposed to the anon key. Enable RLS and scope it. (SCOPE §11.)
- [ ] **Legacy `is_staff()` tables.** Decide which of the legacy tables (`org_systems`, `tickets`, `org_invoices`, `engagements`, …) need org-scoped member policies added before client users exist, vs. which stay staff-only. (SCOPE §7.6 — the deferred membership-model migration.)
- [ ] **Full permissive-policy audit.** Sweep every table a client user can touch; confirm org-scoped RLS, no `qual = true` leaks.
- [ ] **Verification.** Create a throwaway BMR-only test user and prove it CANNOT read StructTech's data (explicit cross-tenant test). This is the sign-off criterion.

---

## 2. BMR data migration — one-time cross-project ETL

Brings BMR's existing pipeline into the OS as BMR-tenant data. This is the strangler cutover from SCOPE §7.4.

- **Source:** the old BMR app's separate Supabase project (`nxmrvtp…`) — `leads`, `lead_notes`, `lead_activity`, `profiles`.
- **Target:** the `structtech` project — `deals`, `deal_notes`, `deal_activity`, all stamped `org_id = BMR`.
- **Mappings to define before running:**
  - Field map: old `leads` columns → `deals` columns (contact_name, company, email, phone, value, trade, source, timestamps).
  - **Status map (confirm old vocabulary first):** old BMR lead statuses → new BMR stages `New Lead / Qualified / Site Visit / Estimate Presented / Won / Lost`.
- **Steps:** back up both projects → export old data → transform → insert into OS with `org_id = BMR` → verify row counts + spot-check → keep the old app read-only during a brief parallel period → decommission.
- **Timing:** after the security workstream (so client data lands in a locked-down schema). Pipeline (Stage 2) is already proven, so there's a real home for it.
- **Open:** confirm the old app's exact status values so the mapping is exact, not guessed.

---

## 3. Deployment — Vercel + domain

- [ ] Connect the `jacobaw1995/structtech-os` GitHub repo to Vercel.
- [ ] Set env vars in Vercel: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (server-only) — never committed.
- [ ] Deploy → confirm the `*.vercel.app` build works end to end.
- [ ] Add custom domain **`OS.structtek.com`** (DNS CNAME → Vercel).
- [ ] Supabase Auth → add the production URL to Site URL + allowed redirect URLs (else login redirects break in prod).
- [ ] Create BMR team accounts → BMR goes live.

**Per-tenant subdomains (e.g. `bmr.structtek.com`) — optional, later.** Current routing is path-based (`/w/[orgId]/…`). Subdomains would be a wildcard domain (`*.structtek.com` on Vercel) + middleware mapping subdomain → org. It's a **white-label enhancement** best reserved for client-facing surfaces (BMR's own portal); path-based stays the operator (StructTech) home, since cross-subdomain hopping complicates the agency tenant-switch UX and auth cookies.

---

## 4. Native mobile / app stores — future phase (see SCOPE §12D)

Not part of go-live, but the trajectory: the web app doesn't ship to app stores — a **React Native + Expo** client does (SCOPE §8 stack), reusing the same Supabase backend/RPCs. Field-first modules (estimating, field/crew) as a genuinely native, offline-first app → Apple App Store + Google Play via Expo EAS. One multi-tenant app; users log into their workspace. Distinct workstream after the web platform + go-live.

---

## Go-live checklist (ordered)

1. [ ] Week 2 estimating complete (Stage 4)
2. [ ] Security workstream complete + cross-tenant isolation test passes
3. [ ] BMR data migration (backup → ETL → verify)
4. [ ] Vercel deploy + `OS.structtek.com` + auth redirect URLs
5. [ ] BMR team accounts created → live
6. [ ] (parallel/after) Week 3 coordination + field for full operational parity
7. [ ] (future) native mobile / app-store phase
