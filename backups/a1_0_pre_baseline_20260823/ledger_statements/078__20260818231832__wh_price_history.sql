-- CP3 step 3 (CP11 clause) — effective-dated pricing.
-- Design: CP3-AUDIT.md §E.1.  STRICTLY ADDITIVE — no storefront-read table touched.
-- base_price on wh_products stays authoritative for the storefront and keeps being
-- dual-written, so the live shop needs zero changes for this migration.

create extension if not exists btree_gist;

create table if not exists public.wh_price_history (
  id             uuid primary key default gen_random_uuid(),
  org_id         uuid not null default '1084baa8-0355-4298-9b98-b876a7581173'
                   references public.organizations(id) on delete cascade,
  variation_id   uuid not null references public.wh_product_variations(id) on delete cascade,
  price          numeric(10,2) not null,
  price_unit     text,
  effective_from timestamptz not null default now(),
  effective_to   timestamptz,                      -- null = open-ended
  changed_by     uuid references auth.users(id),
  note           text,
  created_at     timestamptz not null default now(),
  constraint wh_price_history_interval_sane check (effective_to is null or effective_to > effective_from)
);

-- At most one open-ended row per variation.
create unique index if not exists wh_price_history_one_open
  on public.wh_price_history (variation_id) where effective_to is null;

-- No overlapping intervals for a variation — enforced by the database, not by convention.
alter table public.wh_price_history drop constraint if exists wh_price_no_overlap;
alter table public.wh_price_history add constraint wh_price_no_overlap
  exclude using gist (
    variation_id with =,
    tstzrange(effective_from, coalesce(effective_to, 'infinity'::timestamptz)) with &&
  );

create index if not exists wh_price_history_variation_idx
  on public.wh_price_history (variation_id, effective_from desc);

-- ── Current-price view ──────────────────────────────────────────────────────
-- DEVIATION FROM §E.1 (deliberate): the audit drafted `where effective_to is null`.
-- That is wrong once future-dating is allowed — a scheduled future row is the open
-- one, so the view would return a price that is not yet in force. Interval form is
-- correct in both cases and costs nothing. security_invoker=true so the base table's
-- RLS is enforced through the view (default view semantics would bypass it).
drop view if exists public.wh_current_prices;
create view public.wh_current_prices with (security_invoker = true) as
  select variation_id, price, price_unit, effective_from, effective_to
  from public.wh_price_history
  where effective_from <= now()
    and (effective_to is null or effective_to > now());

-- ── RLS ─────────────────────────────────────────────────────────────────────
-- Deliberately NARROWER than the catalog pattern: no anon read. Price history is
-- commercially sensitive and the storefront does not need it (it reads base_price).
alter table public.wh_price_history enable row level security;

drop policy if exists "wh_price_history auth read"    on public.wh_price_history;
drop policy if exists "wh_price_history role insert"  on public.wh_price_history;
drop policy if exists "wh_price_history role update"  on public.wh_price_history;
drop policy if exists "wh_price_history admin delete" on public.wh_price_history;

create policy "wh_price_history auth read" on public.wh_price_history
  for select using (auth.role() = 'authenticated' and org_id in (select public.my_org_ids()));
create policy "wh_price_history role insert" on public.wh_price_history
  for insert with check (org_id in (select public.my_org_ids()) and public.my_wh_role() in ('admin','assistant'));
create policy "wh_price_history role update" on public.wh_price_history
  for update using (org_id in (select public.my_org_ids()) and public.my_wh_role() in ('admin','assistant'))
             with check (org_id in (select public.my_org_ids()) and public.my_wh_role() in ('admin','assistant'));
create policy "wh_price_history admin delete" on public.wh_price_history
  for delete using (org_id in (select public.my_org_ids()) and public.my_wh_role() = 'admin');

-- ── Backfill: one open row per variation, from the current variation price ──
-- effective_from = now(), NOT the product's created_at. We know today's price is in
-- force now; we have no evidence it was unchanged since creation, and asserting that
-- would fabricate history. Price-as-of before today therefore returns no row — by
-- design, and recorded in the note.
insert into public.wh_price_history (variation_id, price, price_unit, effective_from, note)
select v.id, v.price, v.price_unit, now(),
       'CP3 backfill 18 Aug 2026 — initial price capture; prior history not recorded'
from public.wh_product_variations v
where v.price is not null
  and not exists (select 1 from public.wh_price_history h where h.variation_id = v.id);
