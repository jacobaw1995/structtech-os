-- CP3 step 2 — per-variation colour links, mirroring wh_product_colors.
-- STRICTLY ADDITIVE. Reads wh_product_colors / wh_colors (ACCESS SHARE only) and
-- writes neither. Expected backfill: exactly 831, matching wh_product_colors 1:1,
-- because all 121 products are bridged 1:1 to variations by migration 15.
--
-- Note: wh_product_colors has no surrogate key (it is (product_id, color_id,
-- price_modifier)). The new table adds one, plus the uniqueness the old table
-- expressed only by convention.

create table if not exists public.wh_variation_colors (
  id             uuid primary key default gen_random_uuid(),
  org_id         uuid not null default '1084baa8-0355-4298-9b98-b876a7581173'
                   references public.organizations(id) on delete cascade,
  variation_id   uuid not null references public.wh_product_variations(id) on delete cascade,
  color_id       uuid not null references public.wh_colors(id) on delete cascade,
  price_modifier numeric,
  created_at     timestamptz not null default now(),
  unique (variation_id, color_id)
);

create index if not exists wh_variation_colors_variation_idx on public.wh_variation_colors (variation_id);
create index if not exists wh_variation_colors_color_idx     on public.wh_variation_colors (color_id);

-- ── RLS — anon read required: this is the colour picker's eventual source ────
alter table public.wh_variation_colors enable row level security;

drop policy if exists "wh_variation_colors anon read"    on public.wh_variation_colors;
drop policy if exists "wh_variation_colors auth read"    on public.wh_variation_colors;
drop policy if exists "wh_variation_colors role insert"  on public.wh_variation_colors;
drop policy if exists "wh_variation_colors role update"  on public.wh_variation_colors;
drop policy if exists "wh_variation_colors admin delete" on public.wh_variation_colors;

create policy "wh_variation_colors anon read" on public.wh_variation_colors
  for select to anon using (true);
create policy "wh_variation_colors auth read" on public.wh_variation_colors
  for select using (auth.role() = 'authenticated');
create policy "wh_variation_colors role insert" on public.wh_variation_colors
  for insert with check (org_id in (select public.my_org_ids()) and public.my_wh_role() in ('admin','assistant'));
create policy "wh_variation_colors role update" on public.wh_variation_colors
  for update using (org_id in (select public.my_org_ids()) and public.my_wh_role() in ('admin','assistant'))
             with check (org_id in (select public.my_org_ids()) and public.my_wh_role() in ('admin','assistant'));
create policy "wh_variation_colors admin delete" on public.wh_variation_colors
  for delete using (org_id in (select public.my_org_ids()) and public.my_wh_role() = 'admin');

-- ── Backfill from the flattened product->colour links ───────────────────────
insert into public.wh_variation_colors (variation_id, color_id, price_modifier)
select v.id, pc.color_id, pc.price_modifier
from public.wh_product_colors pc
join public.wh_product_variations v on v.source_product_id = pc.product_id
on conflict (variation_id, color_id) do nothing;
