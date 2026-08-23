-- StructTech OS — org_id backfill on existing CRM tables
--
-- NOT APPLIED. Separate file from the foundation migration, on purpose: this
-- one touches existing business data (deals, deal_notes, deal_activity,
-- follow_ups, audit_leads), so it gets its own review and its own
-- verification before applying, same as every other migration in this repo.
--
-- CORRECTED (2026-07-13) — the original version of this file derived a
-- deal's org_id from `organizations.deal_id -> deals.id`, on the assumption
-- that link meant "which tenant this deal belongs to." It doesn't:
-- `organizations.deal_id` tags the CLIENT org a StructTech deal WON (e.g.
-- Brothers Metal Roofing's own organizations row points back to the
-- StructTech sales deal that signed BMR up). Using it for ownership would
-- have assigned that one StructTech sales deal to BMR's tenant — leaking a
-- StructTech-internal sales record into a client org's data. `deals.org_id`
-- means "which tenant's pipeline this deal is in," a different axis
-- entirely.
--
-- Correct model: every row in these 5 tables today was created before the
-- org_id concept existed, through StructTech's own internal sales funnel
-- (audit.structtek.com scan -> deals, per EXISTING_CRM_SCHEMA.md: "V1 CRM
-- layer... V1 serves STRUCTTECH's internal funnel"). BMR has never had a
-- deal, note, activity row, follow-up, or lead of its own in these tables —
-- BMR's own pipeline (its homeowner sales funnel) starts fresh once Stage 1
-- lands. So every existing row backfills to StructTech's own internal org,
-- unconditionally — not derived from any join.
--
-- `organizations.deal_id` itself is untouched by this migration — it still
-- correctly means "the deal that won this client," nothing here repurposes
-- or removes it.
--
-- Going forward (Stage 1, not this migration): auto_create_deal() stamps
-- org_id = StructTech's org id on every new scan-sourced deal; a new
-- create_deal() RPC stamps org_id = the caller's active org (BMR's, when
-- called from BMR's workspace) for deals created directly in a pipeline.

-- ============================================================================
-- 0. Guard — this migration is meaningless without StructTech's own internal
-- org already seeded (Week 1's bootstrap seed). Fail loudly rather than
-- silently backfilling nothing if run out of order.
-- ============================================================================
do $$
begin
  if not exists (select 1 from public.organizations where tenant_type = 'internal') then
    raise exception 'backfill_org_id_crm: no internal-type organization found — run the Week 1 bootstrap seed first';
  end if;
end $$;

-- ============================================================================
-- 1. deals — every existing row is StructTech's own internal-funnel deal.
-- ============================================================================
alter table public.deals
  add column if not exists org_id uuid references public.organizations(id);

update public.deals
set org_id = (
  select id from public.organizations
  where tenant_type = 'internal'
  order by created_at asc
  limit 1
)
where org_id is null;

-- ============================================================================
-- 2. deal_notes, deal_activity, follow_ups — inherit org_id from their deal
-- (which is now StructTech's org for every existing row, per step 1).
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
-- 3. audit_leads — every existing row came through the public StructTech
-- scan intake (audit.structtek.com), which only ever produces StructTech
-- leads (scan/roadmap are internal-only modules, per SCOPE.md §4 — BMR has
-- no public intake of its own). Backfills unconditionally, same as deals,
-- not via the deals join this file originally used (that approach silently
-- left any lead that never produced a deal at org_id = null forever).
-- ============================================================================
alter table public.audit_leads
  add column if not exists org_id uuid references public.organizations(id);

update public.audit_leads
set org_id = (
  select id from public.organizations
  where tenant_type = 'internal'
  order by created_at asc
  limit 1
)
where org_id is null;

-- ============================================================================
-- Deliberately NOT done here (out of scope for a backfill migration):
--   * No RLS policy changes on these 5 tables — that's
--     20260712120000_org_scoped_rls_crm.sql, a separate reviewed migration.
--   * No changes to organizations.deal_id — it keeps its existing meaning
--     ("the deal that won this client"), untouched by this migration.
--   * No NOT NULL constraint on the new org_id columns. Every existing row
--     backfills to a non-null value under the corrected model above, but a
--     future BMR-side deal created before Stage 1's create_deal() RPC lands
--     could in principle still be inserted with a null org_id directly —
--     NOT NULL is a Stage 1 concern once that RPC is the only insert path.
-- ============================================================================
