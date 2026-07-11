-- StructTech OS — org_id backfill on existing CRM tables
--
-- NOT APPLIED. Separate file from the foundation migration, on purpose: this
-- one touches existing business data (deals, deal_notes, deal_activity,
-- follow_ups, audit_leads), so it gets its own review and its own
-- branch-test before deciding branch vs. direct apply.
--
-- The backfill is mechanical, derived from relationships that already exist
-- in the live schema — not a guess at business meaning:
--   organizations.deal_id  -> deals.id           (an org's originating deal)
--   deals.lead_id          -> audit_leads.id
--   deal_notes / deal_activity / follow_ups.deal_id -> deals.id
--
-- A deal only gets an org_id once it has actually produced an organization
-- (i.e. after closed_won, per SCOPE.md's journey). Deals still in the
-- pipeline correctly stay org_id = null — they don't have a tenant yet.

-- ============================================================================
-- 1. deals
-- ============================================================================
alter table public.deals
  add column if not exists org_id uuid references public.organizations(id);

update public.deals d
set org_id = o.id
from public.organizations o
where o.deal_id = d.id
  and d.org_id is distinct from o.id;

-- ============================================================================
-- 2. deal_notes, deal_activity, follow_ups — inherit org_id from their deal
-- ============================================================================
alter table public.deal_notes
  add column if not exists org_id uuid references public.organizations(id);

update public.deal_notes dn
set org_id = d.org_id
from public.deals d
where d.id = dn.deal_id
  and d.org_id is not null
  and dn.org_id is distinct from d.org_id;

alter table public.deal_activity
  add column if not exists org_id uuid references public.organizations(id);

update public.deal_activity da
set org_id = d.org_id
from public.deals d
where d.id = da.deal_id
  and d.org_id is not null
  and da.org_id is distinct from d.org_id;

alter table public.follow_ups
  add column if not exists org_id uuid references public.organizations(id);

update public.follow_ups f
set org_id = d.org_id
from public.deals d
where d.id = f.deal_id
  and d.org_id is not null
  and f.org_id is distinct from d.org_id;

-- ============================================================================
-- 3. audit_leads — inherit org_id via the deal(s) it produced
-- ============================================================================
-- A lead can, in principle, produce more than one deal (re-engagement) — if
-- so this takes the most recently created matching deal's org. In practice
-- (CRM v1 is StructTech's own internal funnel) this is expected to be 1:1.
alter table public.audit_leads
  add column if not exists org_id uuid references public.organizations(id);

update public.audit_leads al
set org_id = sub.org_id
from (
  select distinct on (d.lead_id) d.lead_id, d.org_id
  from public.deals d
  where d.org_id is not null
  order by d.lead_id, d.created_at desc
) sub
where sub.lead_id = al.id
  and al.org_id is distinct from sub.org_id;

-- ============================================================================
-- Deliberately NOT done here (out of scope for a backfill migration):
--   * No RLS policy changes on these 5 tables. They stay on
--     `staff all <table>` (is_staff()) only, matching
--     EXISTING_CRM_SCHEMA.md: "V1 serves STRUCTTECH's internal funnel, not
--     client sales processes." Adding member-read policies here would be a
--     real RLS/security change — CLAUDE.md says ask before that, separately,
--     not fold it into a backfill migration.
--   * No NOT NULL constraint on the new org_id columns — most deals/leads
--     still in the pipeline have no org yet, by design.
-- ============================================================================
