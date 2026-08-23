-- CP3 step 4 — product type as a stored entity. Design: CP3-AUDIT.md §E.2.
-- STRICTLY ADDITIVE. Touches no storefront-read table. type_id is nullable with no
-- default, so nothing reads or depends on it until CP3 step 8 teaches it to.
--
-- THREE DELIBERATE DEVIATIONS FROM §E.2, each with evidence:
--
--  1. SEED IS DERIVED FROM LIVE DATA, NOT THE AUDIT'S KEY LIST.
--     §E.2 proposed 8 keys including 'closure' and 'clip'. Live wh_products.product_type
--     has 6 non-null values only: trim, accessory, panel, fastener, sealant, underlayment.
--     'closure' exists solely as a catalog_section (3 rows); 'clip' exists nowhere.
--     Seeding invented keys would be fabricating catalog data, so we seed the 6 real ones.
--     Finer catalog_section grain (ridge_cap/hip_cap/valley) is left for CP3 step 8.
--
--  2. wizard_stage IS OMITTED. §E.2 drafted it as a plain int. wh_stages is keyed by
--     system_id — Standing Seam has 4 stages, Exposed Fastener 5, with different ids.
--     A single global int on a global type cannot express per-system staging. Step 7
--     owns stage wiring; modelling it wrong here would be the expensive mistake.
--
--  3. CP13-OWNED COEFFICIENTS ARE CREATED BUT LEFT NULL AND UNSEEDED.
--     input_mode / unit_factor / waste_factor / coverage_mult / pack_qty are the
--     measurement->quantity coefficients owned by Checkpoint 13. The columns exist so
--     CP13 is a backfill and not a rebuild, but copying today's code constants into
--     them would fork CP13's numbers into a second source of truth. NULL here means
--     "not yet owned", which is deliberately distinguishable from a real 1.0.
--     Supporting evidence: unit_type is mixed WITHIN a type (trim spans each /
--     linear_foot / square), so no single input_mode is derivable without judgement.

create table if not exists public.wh_product_types (
  id             uuid primary key default gen_random_uuid(),
  org_id         uuid not null default '1084baa8-0355-4298-9b98-b876a7581173'
                   references public.organizations(id) on delete cascade,
  key            text not null,
  name           text not null,

  -- CP3-owned catalog attributes, derived from live data below
  takes_color    boolean not null default false,
  takes_finish   boolean not null default false,
  takes_gauge    boolean not null default false,
  sold_in_packs  boolean not null default false,

  -- CP13-owned coefficients: intentionally nullable, no default, unseeded
  input_mode     text check (input_mode is null or input_mode in ('area','linear','each','panel_run')),
  unit_factor    numeric,
  waste_factor   numeric,
  coverage_mult  numeric,
  pack_qty       int,

  attributes     jsonb not null default '{}',
  display_order  int   not null default 0,
  created_at     timestamptz not null default now(),
  unique (org_id, key)
);

comment on column public.wh_product_types.input_mode    is 'CP13-owned. NULL = not yet assigned; do not populate outside Checkpoint 13.';
comment on column public.wh_product_types.unit_factor   is 'CP13-owned. NULL = not yet assigned; do not populate outside Checkpoint 13.';
comment on column public.wh_product_types.waste_factor  is 'CP13-owned. NULL = not yet assigned; NULL is NOT equivalent to 1.0.';
comment on column public.wh_product_types.coverage_mult is 'CP13-owned. NULL = not yet assigned; NULL is NOT equivalent to 1.0.';
comment on column public.wh_product_types.pack_qty      is 'CP13-owned. NULL = not yet assigned.';

-- ── RLS — mirrors the catalog pattern (migration 12/15) ─────────────────────
alter table public.wh_product_types enable row level security;

drop policy if exists "wh_product_types anon read"    on public.wh_product_types;
drop policy if exists "wh_product_types auth read"    on public.wh_product_types;
drop policy if exists "wh_product_types role insert"  on public.wh_product_types;
drop policy if exists "wh_product_types role update"  on public.wh_product_types;
drop policy if exists "wh_product_types admin delete" on public.wh_product_types;

create policy "wh_product_types anon read" on public.wh_product_types
  for select to anon using (true);
create policy "wh_product_types auth read" on public.wh_product_types
  for select using (auth.role() = 'authenticated');
create policy "wh_product_types role insert" on public.wh_product_types
  for insert with check (org_id in (select public.my_org_ids()) and public.my_wh_role() in ('admin','assistant'));
create policy "wh_product_types role update" on public.wh_product_types
  for update using (org_id in (select public.my_org_ids()) and public.my_wh_role() in ('admin','assistant'))
             with check (org_id in (select public.my_org_ids()) and public.my_wh_role() in ('admin','assistant'));
create policy "wh_product_types admin delete" on public.wh_product_types
  for delete using (org_id in (select public.my_org_ids()) and public.my_wh_role() = 'admin');

-- ── Seed: the 6 live product_type values, attributes derived by observation ──
insert into public.wh_product_types (key, name, takes_color, takes_finish, takes_gauge, sold_in_packs, display_order)
select p.product_type,
       initcap(replace(p.product_type, '_', ' ')),
       bool_or(pc.product_id is not null),
       bool_or(p.finish is not null),
       bool_or(p.gauge  is not null),
       bool_or(p.unit_type = 'bag'),
       row_number() over (order by count(distinct p.id) desc, p.product_type)
from public.wh_products p
left join public.wh_product_colors pc on pc.product_id = p.id
where p.product_type is not null
group by p.product_type
on conflict (org_id, key) do nothing;

-- ── Nullable linkage on families and variations ─────────────────────────────
alter table public.wh_product_families  add column if not exists type_id uuid references public.wh_product_types(id);
alter table public.wh_product_variations add column if not exists type_id uuid references public.wh_product_types(id);

create index if not exists wh_product_families_type_idx  on public.wh_product_families  (type_id);
create index if not exists wh_product_variations_type_idx on public.wh_product_variations (type_id);

-- ── Backfill type_id by matching the existing text product_type ─────────────
update public.wh_product_families f
   set type_id = t.id
  from public.wh_product_types t
 where t.key = f.product_type
   and f.type_id is null;

update public.wh_product_variations v
   set type_id = t.id
  from public.wh_products p
  join public.wh_product_types t on t.key = p.product_type
 where p.id = v.source_product_id
   and v.type_id is null;
