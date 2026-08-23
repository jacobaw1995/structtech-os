-- StructTech OS — management controls retrofit (SCOPE.md §2.6 / BACKLOG.md)
--
-- NOT APPLIED. Author-only migration file — ask before applying, same as
-- every other migration in this repo. Backfills user-facing edit +
-- delete/void/archive onto three entities that shipped create-and-advance
-- only: deals, estimates, work_orders. No new tables — two new nullable
-- columns (deals.archived_at, work_orders.voided_at) plus RPCs.
--
-- Soft where history matters, hard delete only where nothing downstream
-- exists yet — the same split for all three entities:
--
--   * deals — ARCHIVE only (archived_at), never hard delete. A deal always
--     has deal_activity/deal_notes/follow_ups hanging off it by the time
--     anyone would want to remove it; hard-deleting would either orphan
--     that history or require cascading it away, and "Isaac fat-fingered a
--     lead" should never be able to erase a paper trail. archive_deal()
--     also cancels pending follow_ups (mirrors deal_stage_side_effects'
--     existing cancel-on-stage-change behavior) so an archived deal doesn't
--     keep emailing someone. restore_deal() undoes it — pure UI mistake,
--     not meant to be permanent.
--
--   * estimates — VOID (existing status enum, no UI path today) for
--     anything downstream, DELETE only for drafts nothing depends on yet.
--     delete_estimate() explicitly checks for signatures or a work_order
--     before allowing the delete — signatures.estimate_id is ON DELETE
--     CASCADE (Week 2 migration), so without this guard a "delete my draft"
--     click could silently destroy a signed legal document. work_orders
--     has no cascade at all (plain FK), so that half would fail loudly
--     rather than silently — still worth the friendlier error message.
--     void_estimate() has no such guard — voiding a signed job (client
--     backed out after signing) is exactly the case that needs to work.
--     update_estimate_contact() is deliberately separate from the existing
--     update_estimate_details() — that RPC advances preliminary->validated
--     as a side effect of being called at all (Stage 3 migration, section
--     5c); reusing it for a contact-typo fix would wrongly mark a
--     preliminary estimate "validated" for editing an email address.
--
--   * work_orders — VOID (new voided_at, mirrors the estimates pattern) for
--     anything with real children, DELETE only if it has none.
--     delete_work_order() checks material_items/schedule_blocks/
--     check_ins/production_packets — all four are ON DELETE CASCADE onto
--     work_orders (coordination + field migrations), so an unguarded delete
--     would silently wipe a crew's logged hours and photos. void_work_order()
--     has no such guard; it's the "this job is cancelled" path and is
--     expected to work on a work order with real history. Field's Today
--     list filters voided work orders out client-side (small result set,
--     no PostgREST embedded-filter complexity) so a cancelled job stops
--     showing up for a crew to check into.
--
-- All RPCs security-definer, org-scoped from the caller's own membership,
-- per every migration so far — no exceptions here.

-- ============================================================================
-- 1. Schema additions
-- ============================================================================
alter table public.deals
  add column archived_at timestamptz;

comment on column public.deals.archived_at is
  'Soft-delete. Archived deals drop off the pipeline board but stay fetchable (fetch_deal) so restore_deal() can undo a mistake. See migration header.';

alter table public.work_orders
  add column voided_at timestamptz;

comment on column public.work_orders.voided_at is
  'Soft-cancel ("this job is off"), distinct from delete_work_order()''s hard delete. See migration header.';

-- ============================================================================
-- 2. Deals — edit + archive/restore
-- ============================================================================
create or replace function public.update_deal_details(
  p_deal_id uuid,
  p_contact_name text default null,
  p_company text default null,
  p_email text default null,
  p_phone text default null,
  p_value numeric default null,
  p_trade text default null,
  p_crew_size int default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  update public.deals
  set contact_name = coalesce(p_contact_name, contact_name),
      company = coalesce(p_company, company),
      email = coalesce(p_email, email),
      phone = coalesce(p_phone, phone),
      value = coalesce(p_value, value),
      trade = coalesce(p_trade, trade),
      crew_size = coalesce(p_crew_size, crew_size),
      updated_at = now()
  where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action)
  values (p_deal_id, v_org_id, 'details_updated');
end;
$$;

create or replace function public.archive_deal(p_deal_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  update public.deals set archived_at = now() where id = p_deal_id;

  update public.follow_ups set status = 'cancelled'
  where deal_id = p_deal_id and status = 'pending';

  insert into public.deal_activity (deal_id, org_id, action)
  values (p_deal_id, v_org_id, 'archived');
end;
$$;

create or replace function public.restore_deal(p_deal_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  update public.deals set archived_at = null where id = p_deal_id;

  insert into public.deal_activity (deal_id, org_id, action)
  values (p_deal_id, v_org_id, 'restored');
end;
$$;

-- ============================================================================
-- 3. Estimates — contact edit + void + guarded delete
-- ============================================================================
create or replace function public.update_estimate_contact(
  p_estimate_id uuid,
  p_contact_name text default null,
  p_company text default null,
  p_phone text default null,
  p_email text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  -- No status lock, unlike update_estimate_details — correcting a contact
  -- typo doesn't touch pricing or the signed/presented content, so it's
  -- safe at any status including signed. See migration header.
  update public.estimates
  set contact_name = coalesce(p_contact_name, contact_name),
      company = coalesce(p_company, company),
      phone = coalesce(p_phone, phone),
      email = coalesce(p_email, email),
      updated_at = now()
  where id = p_estimate_id;
end;
$$;

create or replace function public.void_estimate(p_estimate_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  update public.estimates
  set status = 'void',
      updated_at = now()
  where id = p_estimate_id;
end;
$$;

create or replace function public.delete_estimate(p_estimate_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_has_signature boolean;
  v_has_work_order boolean;
begin
  select org_id into v_org_id from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  select exists(select 1 from public.signatures where estimate_id = p_estimate_id)
    into v_has_signature;
  select exists(select 1 from public.work_orders where estimate_id = p_estimate_id)
    into v_has_work_order;

  if v_has_signature or v_has_work_order then
    raise exception 'estimate % has a signature or work order and cannot be deleted — void it instead', p_estimate_id;
  end if;

  delete from public.estimates where id = p_estimate_id;
end;
$$;

-- ============================================================================
-- 4. Work orders — void/restore + guarded delete
-- ============================================================================
create or replace function public.void_work_order(p_work_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.work_orders where id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  update public.work_orders set voided_at = now() where id = p_work_order_id;
end;
$$;

create or replace function public.restore_work_order(p_work_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from public.work_orders where id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  update public.work_orders set voided_at = null where id = p_work_order_id;
end;
$$;

create or replace function public.delete_work_order(p_work_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_has_children boolean;
begin
  select org_id into v_org_id from public.work_orders where id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  select
    exists(select 1 from public.material_items where work_order_id = p_work_order_id)
    or exists(select 1 from public.schedule_blocks where work_order_id = p_work_order_id)
    or exists(select 1 from public.check_ins where work_order_id = p_work_order_id)
    or exists(select 1 from public.production_packets where work_order_id = p_work_order_id)
  into v_has_children;

  if v_has_children then
    raise exception 'work order % has materials, a schedule, check-ins, or a production packet and cannot be deleted — void it instead', p_work_order_id;
  end if;

  delete from public.work_orders where id = p_work_order_id;
end;
$$;
