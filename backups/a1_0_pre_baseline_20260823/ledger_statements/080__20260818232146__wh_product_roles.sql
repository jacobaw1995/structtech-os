-- CP3 step 5 — linkage by stable ID. Design: CP3-PLAN.md §4.1.
-- STRICTLY ADDITIVE. Reads wh_products for the backfill (ACCESS SHARE only — readers
-- do not block readers), writes nothing the storefront reads.
--
-- SCOPE GUARD: this table stores WHICH PRODUCT PLAYS WHICH ROLE. It deliberately does
-- NOT store how many to order. PANEL_SCREWS_PER_FT / TRIM_SCREWS_PER_FT /
-- PANCAKE_SCREWS_PER_FT / RIDGE_SCREWS_PER_FT stay in code as Checkpoint 13 property.
--
-- system_slug uses NULLS NOT DISTINCT so a second global (null-system) row for the
-- same key is rejected rather than silently allowed, which plain UNIQUE would permit.

create table if not exists public.wh_product_roles (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null default '1084baa8-0355-4298-9b98-b876a7581173'
                references public.organizations(id) on delete cascade,
  key         text not null,
  name        text not null,
  product_id  uuid references public.wh_products(id) on delete set null,
  system_slug text,
  note        text,
  created_at  timestamptz not null default now(),
  unique nulls not distinct (org_id, key, system_slug)
);

create index if not exists wh_product_roles_product_idx on public.wh_product_roles (product_id);

-- ── RLS — anon read is required: the storefront must resolve roles at load time ──
alter table public.wh_product_roles enable row level security;

drop policy if exists "wh_product_roles anon read"    on public.wh_product_roles;
drop policy if exists "wh_product_roles auth read"    on public.wh_product_roles;
drop policy if exists "wh_product_roles role insert"  on public.wh_product_roles;
drop policy if exists "wh_product_roles role update"  on public.wh_product_roles;
drop policy if exists "wh_product_roles admin delete" on public.wh_product_roles;

create policy "wh_product_roles anon read" on public.wh_product_roles
  for select to anon using (true);
create policy "wh_product_roles auth read" on public.wh_product_roles
  for select using (auth.role() = 'authenticated');
create policy "wh_product_roles role insert" on public.wh_product_roles
  for insert with check (org_id in (select public.my_org_ids()) and public.my_wh_role() in ('admin','assistant'));
create policy "wh_product_roles role update" on public.wh_product_roles
  for update using (org_id in (select public.my_org_ids()) and public.my_wh_role() in ('admin','assistant'))
             with check (org_id in (select public.my_org_ids()) and public.my_wh_role() in ('admin','assistant'));
create policy "wh_product_roles admin delete" on public.wh_product_roles
  for delete using (org_id in (select public.my_org_ids()) and public.my_wh_role() = 'admin');

-- ── Backfill: resolve today's three code constants, once, at migration time ──
insert into public.wh_product_roles (key, name, product_id, system_slug, note)
select 'panel_screw', 'Panel screws (exposed fastener)', id, 'ag-panel',
       'Backfilled 18 Aug 2026 from PANEL_SCREW_SKU = M2W-SCREW-150'
  from public.wh_products where sku = 'M2W-SCREW-150'
union all
select 'trim_screw', 'Trim + ridge screws', id, 'ag-panel',
       'Backfilled 18 Aug 2026 from TRIM_SCREW_SKU = M2W-SCREW-200'
  from public.wh_products where sku = 'M2W-SCREW-200'
on conflict do nothing;

-- 'pancake_screw' is created UNASSIGNED (product_id null): no product carries
-- SS-PANCAKE-SCREW yet (verified again 18 Aug — still 0 rows). The row exists so the
-- admin has something to point at once the product is created. The storefront already
-- degrades visibly via missingScrewRow(), so an unassigned role is the safe state.
insert into public.wh_product_roles (key, name, product_id, system_slug, note)
values ('pancake_screw', 'Pancake screws (standing seam)', null, 'standing-seam',
        'UNASSIGNED — no product with SKU SS-PANCAKE-SCREW exists. Assign in admin once created.')
on conflict do nothing;
