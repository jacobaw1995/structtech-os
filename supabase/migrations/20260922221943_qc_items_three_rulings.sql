-- QC ITEMS — THREE CONTROLLER RULINGS OF 2026-09-22, IN ONE MIGRATION. Track S.
-- Rollback: supabase/rollbacks/20260922_qc_items_three_rulings_rollback.sql
--
-- BEFORE-MEASUREMENT (2026-09-22, whole database): qc_items 0 rows · 0 with a photo_ref · 0 live ·
-- check_ins 0 · photos on check-ins 0 · org_members 8, of which client_portal_viewer 0 · 2 trade work orders.
-- ** ALL THREE FIXES THEREFORE SHIP UNOBSERVED: nothing in production exercised any of them, and every
-- proof below is on synthetic rows in rolled-back transactions. Recorded as UNOBSERVED, not as proved live. **
--
-- RULE 15 / 16 / 18 CHECKS RUN FIRST, because this migration ADDS COLUMNS to a live table:
--   · supabase/sweeps/rowtype_reader_sweep.sql, derived from the catalog: 62 owned tables, 417 functions in
--     public, 13 return an owned table's row type — and **0 of them return qc_items' row type**. The only two
--     functions naming qc_items are record_qc_item (returns uuid) and clear_qc_item (returns integer); both
--     name their columns in INSERT/UPDATE, which a column add cannot break. 0 views read qc_items.
--   · POSITIVE CONTROL (rule 18), in a rolled-back transaction: a synthetic `returns setof qc_items` function
--     with a NAMED column list ran clean, then FAILED 42P13 the moment a column was added. The instrument was
--     shown the defect it exists to find before its zero was trusted.
--
-- RULING 1 — THE FIRST ATTESTATION AND THE LATEST ATTESTATION ARE TWO FACTS, NOT ONE FIELD.
-- Keeping history was right: a repeat is a real event (a second person attesting, or the same person
-- re-checking). What was wrong is that the LIVE row's provenance silently became the latest writer's, so
-- "who signed off" changed with nobody deciding it. The live row now carries BOTH: first_actor_id /
-- first_occurred_at (inherited from the attestation chain) and actor_id / occurred_at (the latest).
-- REACHABLE FROM THE TABLE: a BEFORE INSERT OR UPDATE trigger computes first_* on every path — the RPC, a
-- future policy, a service-role write, a direct INSERT by postgres — and OVERWRITES whatever was supplied,
-- so the first attestation cannot be forged or edited. Same shape as ready_by versus the PO promise.
--
-- RULING 2 — A CLIENT PORTAL VIEWER IS NOT AN ATTESTER. Closed AT THE TABLE by the same trigger, which
-- refuses the write for any signed-in caller whose role is not on the attester list, not only inside the two
-- RPCs. is_qc_attester() is an ALLOW-LIST (owner, admin, agency_admin, office, member, field), so a role added
-- later attests nothing until it is named — closed by default rather than by omission (rule 13).
-- A caller with no identity at all (auth.uid() null: migrations, service-role maintenance) is not blocked;
-- that path is already unrestricted by design and blocking it would break repair work, not an attacker.
--
-- RULING 3 — A REFERENCE THAT IS NOT VERIFIED AGAINST THE THING IT REFERENCES IS A NAME, AND A NAME IS NOT A
-- CONTROL. photo_ref is the first 16 hex of sha256 of the photo's data URL (src/lib/field/qc-data.ts:14).
-- Postgres computes the same value, so the reference can be RESOLVED rather than trusted: the trigger refuses
-- any photo_ref that does not match a photo on a check-in OF THIS WORK ORDER. The controller's case — the
-- hash of a real photo from a DIFFERENT roof — is refused by that test, which is the whole point of a
-- required-photo requirement.
-- WHAT THIS DOES AND DOES NOT PROMISE: it is a WRITE-TIME resolution. If the crew deletes the photo later the
-- reference stops matching and the app reads "photo removed" (X's design, unchanged) — a state, not a false
-- pass. It does not prove the photo shows the right intersection; no database can.

-- ---- the tests, as functions, so the trigger and the RPCs cannot disagree ----------------------------------
create function public.is_qc_attester(p_org_id uuid)
returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select exists (
    select 1 from public.org_members m
    where m.org_id = p_org_id
      and m.user_id = auth.uid()
      and m.role in ('owner', 'admin', 'agency_admin', 'office', 'member', 'field')
  );
$function$;
revoke execute on function public.is_qc_attester(uuid) from public, anon;
grant execute on function public.is_qc_attester(uuid) to authenticated;

create function public.qc_photo_on_work_order(p_work_order_id uuid, p_photo_ref text)
returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select exists (
    select 1
    from public.check_ins c, lateral unnest(c.photos) as photo
    where c.work_order_id = p_work_order_id
      and left(encode(sha256(convert_to(photo, 'UTF8')), 'hex'), 16) = p_photo_ref
  );
$function$;
revoke execute on function public.qc_photo_on_work_order(uuid, text) from public, anon;
grant execute on function public.qc_photo_on_work_order(uuid, text) to authenticated;

-- ---- ruling 1: the two facts ------------------------------------------------------------------------------
alter table public.qc_items add column first_actor_id uuid;
alter table public.qc_items add column first_occurred_at timestamptz;

create function public.qc_items_carry_first_attestation()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
declare prev record;
begin
  if tg_op = 'UPDATE' then
    -- The first attestation is a fact about a moment; nothing edits it.
    new.first_actor_id := old.first_actor_id;
    new.first_occurred_at := old.first_occurred_at;
    return new;
  end if;

  select q.first_actor_id, q.first_occurred_at, q.actor_id, q.occurred_at into prev
  from public.qc_items q
  where q.work_order_id = new.work_order_id
    and q.requirement_key = new.requirement_key
  order by q.occurred_at asc, q.id asc
  limit 1;

  -- Computed, never taken from the caller: a forged first_* is overwritten here.
  new.first_actor_id := coalesce(prev.first_actor_id, prev.actor_id, new.actor_id);
  new.first_occurred_at := coalesce(prev.first_occurred_at, prev.occurred_at, new.occurred_at);
  return new;
end;
$function$;
revoke execute on function public.qc_items_carry_first_attestation() from public, anon, authenticated;

create trigger qc_items_carry_first_attestation
  before insert or update on public.qc_items
  for each row execute function public.qc_items_carry_first_attestation();

-- The table was empty at this point (0 rows, measured above), so there is nothing to backfill and the
-- columns can carry NOT NULL from the start: every row is written through the trigger above.
alter table public.qc_items alter column first_actor_id set not null;
alter table public.qc_items alter column first_occurred_at set not null;

-- ---- rulings 2 and 3: refused at the table, on every path -------------------------------------------------
create function public.qc_items_guard_write()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
begin
  -- Ruling 2. A caller with no identity (migration, service-role maintenance) is out of scope; a signed-in
  -- caller must be an attester in the row's own workspace.
  if auth.uid() is not null and not coalesce(public.is_qc_attester(new.org_id), false) then
    raise exception 'your role cannot record quality-control evidence in this workspace'
      using hint = 'not_an_attester';
  end if;

  -- Ruling 3. The reference must resolve to a photo on THIS work order.
  if new.photo_ref is not null
     and (tg_op = 'INSERT' or new.photo_ref is distinct from old.photo_ref)
     and not coalesce(public.qc_photo_on_work_order(new.work_order_id, new.photo_ref), false) then
    raise exception 'that photo is not on this work order — take or pick a photo from this job'
      using hint = 'photo_not_on_work_order';
  end if;

  return new;
end;
$function$;
revoke execute on function public.qc_items_guard_write() from public, anon, authenticated;

create trigger qc_items_guard_write
  before insert or update on public.qc_items
  for each row execute function public.qc_items_guard_write();

-- ---- the two RPCs say the same thing in words, before doing any work ---------------------------------------
create or replace function public.record_qc_item(
  p_work_order_id uuid,
  p_requirement_key text,
  p_kind text,
  p_photo_ref text default null,
  p_count_value integer default null
) returns uuid
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_actor uuid := auth.uid();
  v_org uuid;
  v_kind text;
  v_id uuid;
begin
  if v_actor is null then
    raise exception 'not signed in';
  end if;

  -- The work order must be one this caller can reach: their org, and either a
  -- trade work order or a master they are allowed to see.
  select w.org_id, w.kind into v_org, v_kind
  from public.work_orders w
  where w.id = p_work_order_id
    and w.org_id in (select public.my_org_ids())
    and (w.kind = 'trade' or public.can_view_master_work_order(w.org_id));
  if v_org is null then
    raise exception 'that work order is not one you can record against';
  end if;

  -- Ruling 2 (2026-09-22), said here in words; the table refuses it either way.
  if not coalesce(public.is_qc_attester(v_org), false) then
    raise exception 'your role cannot record quality-control evidence in this workspace'
      using hint = 'not_an_attester';
  end if;

  -- Ruling 3 (2026-09-22): the reference is resolved against this work order's photos, not trusted.
  if p_photo_ref is not null and not coalesce(public.qc_photo_on_work_order(p_work_order_id, p_photo_ref), false) then
    raise exception 'that photo is not on this work order — take or pick a photo from this job'
      using hint = 'photo_not_on_work_order';
  end if;

  -- Re-recording a requirement replaces it: the previous row is cleared, not
  -- edited, so the history of what was recorded when survives. The LIVE row keeps the FIRST attestation
  -- alongside this latest one (ruling 1) — carried by qc_items_carry_first_attestation.
  update public.qc_items
     set cleared_at = now(), cleared_by = v_actor
   where work_order_id = p_work_order_id
     and requirement_key = p_requirement_key
     and cleared_at is null;

  insert into public.qc_items (org_id, work_order_id, requirement_key, kind, photo_ref, count_value, actor_id)
  values (v_org, p_work_order_id, p_requirement_key, p_kind, p_photo_ref, p_count_value, v_actor)
  returning id into v_id;
  return v_id;
end;
$function$;

create or replace function public.clear_qc_item(p_work_order_id uuid, p_requirement_key text)
returns integer
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_actor uuid := auth.uid();
  v_rows integer := 0;
  v_org uuid;
begin
  if v_actor is null then
    raise exception 'not signed in';
  end if;

  select w.org_id into v_org from public.work_orders w
  where w.id = p_work_order_id
    and w.org_id in (select public.my_org_ids())
    and (w.kind = 'trade' or public.can_view_master_work_order(w.org_id));
  if v_org is not null and not coalesce(public.is_qc_attester(v_org), false) then
    raise exception 'your role cannot change quality-control evidence in this workspace'
      using hint = 'not_an_attester';
  end if;

  update public.qc_items q
     set cleared_at = now(), cleared_by = v_actor
   where q.work_order_id = p_work_order_id
     and q.requirement_key = p_requirement_key
     and q.cleared_at is null
     and q.org_id in (select public.my_org_ids())
     and exists (
       select 1 from public.work_orders w
       where w.id = q.work_order_id
         and (w.kind = 'trade' or public.can_view_master_work_order(w.org_id))
     );
  get diagnostics v_rows = row_count;
  return v_rows;
end;
$function$;
