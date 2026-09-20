-- ============================================================================
-- X-W1.20 · qc_items — WHICH REQUIRED CHECKS WERE DONE. PROPOSAL FOR TRACK S.
-- NOT APPLIED BY TRACK X. Proved on a local fixture:
--   bash scripts/pilot/qc-items-fixture/run.sh   (loads THIS file verbatim)
-- ============================================================================
-- A4.3: "Required photo by intersection type, countable checks, sweep
-- confirmations; blocking vs advisory." Pilot 2026-10-07.
--
-- A REQUIRED CHECK THAT WAS NOT DONE IS A STATE, NOT AN ABSENCE. The app renders
-- one row per requirement for the trade, so "no photo yet" and "not required on
-- this trade" are different sentences on the screen. That is only possible if the
-- DONE ones are recorded as rows — which is this table. An empty table therefore
-- means "nothing done yet", never "nothing required".
--
-- THE PHOTO ITSELF IS NOT HERE. It stays where crew photos already go:
-- check_ins.photos, written by add_check_in_photo() through the client-side
-- shrink Track U added on 2026-09-16 (a data URL over 1 MiB was silently
-- truncated to 1,048,576 characters before it). This table stores a 16-hex
-- `photo_ref` — sha256 of that data URL, computed server-side — so a QC row
-- points at a photo without copying it, and without ever holding a filename.
-- If the crew later deletes that photo, the reference stops matching and the app
-- says so ("photo removed") rather than showing the requirement as satisfied.
--
-- NO MONEY, NO CUSTOMER DATA, BY TYPE. As in field_events: no column can hold
-- free text. A requirement key and a kind are lower-case codes; a photo is a hex
-- hash; a count is a bounded integer. There is nowhere to put a name, an address
-- or a price.
--
-- ADVISORY, NOT BLOCKING (SCOPE §2.8). Nothing here refuses a check-in because a
-- requirement is outstanding. `blocking` lives in the app's catalog and decides
-- how loudly the row reads. Enforcement ("the day cannot close") is a later
-- per-tenant switch, default OFF, and it is Jacob's decision, not this file's.

create table public.qc_items (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null references public.organizations(id),
  work_order_id   uuid not null references public.work_orders(id) on delete cascade,
  requirement_key text not null check (requirement_key ~ '^[a-z_]{1,40}$'),
  kind            text not null check (kind in ('photo', 'count', 'confirm')),
  photo_ref       text null check (photo_ref ~ '^[0-9a-f]{16}$'),
  count_value     integer null check (count_value between 0 and 100000),
  actor_id        uuid not null,
  occurred_at     timestamptz not null default now(),
  cleared_at      timestamptz null,
  cleared_by      uuid null,
  -- A photo requirement is satisfied by a photo; a count by a number. Neither is
  -- satisfied by an empty row, so the shape is checked here rather than trusted.
  constraint qc_items_evidence_matches_kind check (
    (kind = 'photo'   and photo_ref is not null and count_value is null) or
    (kind = 'count'   and count_value is not null and photo_ref is null) or
    (kind = 'confirm' and photo_ref is null and count_value is null)
  ),
  constraint qc_items_cleared_together check ((cleared_at is null) = (cleared_by is null))
);

-- One LIVE row per requirement per work order; cleared rows stay as history.
create unique index qc_items_one_live_per_requirement
  on public.qc_items (work_order_id, requirement_key) where cleared_at is null;
create index qc_items_work_order on public.qc_items (work_order_id, occurred_at);

alter table public.qc_items enable row level security;
revoke all on table public.qc_items from anon;
revoke insert, update, delete, truncate, references, trigger, maintain on table public.qc_items from authenticated;
grant select on table public.qc_items to authenticated;

-- The crew MUST read this one — it is their own checklist. Reachability follows
-- the work order through its own RLS, so a crew member who cannot see a master
-- work order cannot see its QC rows either, with no second copy of that rule.
create policy "member reads qc items for reachable work orders" on public.qc_items
  for select to authenticated
  using (
    org_id in (select my_org_ids())
    and exists (select 1 from public.work_orders w where w.id = work_order_id and w.org_id = qc_items.org_id)
  );

create function public.record_qc_item(
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

  -- Re-recording a requirement replaces it: the previous row is cleared, not
  -- edited, so the history of what was recorded when survives.
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

-- Undo, because everything a user can make a user can remove (SCOPE §2.6).
create function public.clear_qc_item(p_work_order_id uuid, p_requirement_key text)
returns integer
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_actor uuid := auth.uid();
  v_rows integer := 0;
begin
  if v_actor is null then
    raise exception 'not signed in';
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

-- Rule 7: closing revokes, and the EXECUTE the application needs.
revoke execute on function public.record_qc_item(uuid, text, text, text, integer) from public, anon;
revoke execute on function public.clear_qc_item(uuid, text) from public, anon;
grant execute on function public.record_qc_item(uuid, text, text, text, integer) to authenticated;
grant execute on function public.clear_qc_item(uuid, text) to authenticated;
