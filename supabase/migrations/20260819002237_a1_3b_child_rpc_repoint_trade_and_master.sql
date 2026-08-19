-- A1.3b — RPC re-pointing: children (§5.1)
--
-- APPLIED TO PRODUCTION 2026-08-19 via MCP `apply_migration`, recorded in
-- supabase_migrations.schema_migrations as version 20260819002237,
-- name `a1_3b_child_rpc_repoint_trade_and_master`. Function bodies below are
-- reproduced from `pg_get_functiondef()` on the live database and verified
-- byte-identical (md5 + length), not written from memory.
--
-- SCOPE: FUNCTION DDL ONLY. No table created, altered or dropped; no row
-- inserted, updated or deleted. One function dropped (the A1.2 shim), two
-- helpers created, nine re-pointed. Every one of the nine keeps its exact
-- name, argument list and return type, so each CREATE OR REPLACE is a true
-- replacement and not an overload (rule 1) — verified at 1 overload each
-- against pg_proc after applying (rule 3).
--
-- ROLLBACK. Every affected child table (material_items, schedule_blocks,
-- check_ins, production_packets, work_order_agreements, work_order_activity)
-- is at ZERO rows, so there is no data to restore — only definitions. The
-- pre-migration definitions of all ten touched functions were captured to
-- `backups/a1_3b_pre_migration_functions_20260819.sql`, but NOTE that
-- `/backups/` is gitignored, so that file exists only on the machine that ran
-- this migration. The durable recovery path is this repo's history: the prior
-- definitions live in 20260713120000_coordination_schema_and_rpcs.sql,
-- 20260713150000_field_schema_and_rpcs.sql,
-- 20260726130000_work_order_post_signoff_activity_log.sql,
-- 20260730010405 (agreements) and 20260817151709 (the shim).
--
-- FIVE THINGS THIS MIGRATION DOES BEYOND ADDING A KIND CHECK, each because the
-- re-point would otherwise have broken something silently:
--
-- 1. THE AFTER-SIGN-OFF AUDIT TRAIL WOULD HAVE GONE DEAD. The §4.3 change
--    audit keyed off the work order's own `sign_off_at`. After the re-point
--    that column is only ever set on a master, while materials live on trades
--    — so a trade's `sign_off_at` is permanently null and every
--    `*_after_signoff` branch would have stopped firing WITHOUT ERRORING.
--    `job_master_sign_off()` resolves the master through `job_id` instead.
--
-- 2. ACTIVITY IS LOGGED AGAINST THE MASTER, NOT THE TRADE. What goes stale
--    when a material changes after sign-off is the MASTER's signed agreement,
--    and the master is where a human looks for "what changed since I signed".
--    The trade is named in the logged value so the detail is not lost.
--
-- 3. THE AGREEMENT SNAPSHOT WOULD HAVE BEEN EMPTY. `create_work_order_agreement`
--    gathered materials and schedule with `where work_order_id = <the master>`.
--    Those rows now live on trades, so every signed agreement would have
--    snapshotted `[]` — the document silently losing its content. It now
--    gathers across the job's live trades, each entry labelled with its trade.
--    Safe to reshape rather than version: `work_order_agreements` is at zero
--    rows and nothing in the UI reads `snapshot` (verified by grep), so
--    rule 5b does not bite.
--
-- 4. `update_material_item` / `delete_material_item` TAKE A CHILD ID AND KEEP
--    IT. Their level resolves through the parent work order; adding a
--    work-order argument would let a caller name a level different from the one
--    the row actually sits on. Their org path was re-verified while in there:
--    previously only the material item's own `org_id` was checked, so a row
--    whose org had drifted from its parent's would have passed on the item's
--    org alone. Both orgs are now checked and must match.
--
-- 5. `add_schedule_block`'s BLOCKING LOOKUP STAYS SCOPED TO ITS OWN TRADE.
--    A trade's schedule is gated by that trade's materials, not by a sibling
--    trade's — widening it to the job would have blocked the roof on the
--    gutters' delivery date. Cross-trade sequencing is what `predecessor_id`
--    is for.
--
-- Note on `assert_work_order_level`: the `coalesce(v_kind, '')` is rule 5 —
-- a null kind makes a bare `<>` comparison null, and PL/pgSQL reads a null IF
-- as false, which would let the wrong level straight through.

-- =====================================================================
-- FIRST STATEMENT: DROP THE A1.2 SHIM.
-- Signature copied verbatim from pg_get_function_identity_arguments()
-- ('p_estimate_id uuid'), never retyped (rule 2). Not IF EXISTS: a bare DROP
-- fails loudly on a wrong signature, where IF EXISTS silently succeeds and
-- drops nothing. Repo grep confirmed zero callers before applying.
-- =====================================================================
drop function public.create_work_order_from_estimate(p_estimate_id uuid);

-- =====================================================================
-- Helpers. Neither is granted to anon/authenticated: nothing outside these
-- SECURITY DEFINER functions should call them, and a definer function owned
-- by postgres calls them regardless. That keeps §6.9's anon-EXECUTE surface
-- from growing while A1.5's revoke sweep is still pending.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.assert_work_order_level(p_work_order_id uuid, p_expected_kind text)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_kind   text;
begin
  select w.org_id, w.kind into v_org_id, v_kind
  from public.work_orders w
  where w.id = p_work_order_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'work order not found or not accessible: %', p_work_order_id;
  end if;

  if coalesce(v_kind, '') <> p_expected_kind then
    raise exception 'work order % is kind=% — this action requires a % work order (%)',
      p_work_order_id,
      coalesce(v_kind, '(null)'),
      p_expected_kind,
      case p_expected_kind
        when 'trade'  then 'materials, schedule blocks, check-ins and production packets attach to trades, not to the master'
        when 'master' then 'sign-off and agreements are recorded once on the master, not per trade'
        else 'unexpected level'
      end;
  end if;

  return v_org_id;
end;
$function$
;

revoke all on function public.assert_work_order_level(uuid, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.job_master_sign_off(p_work_order_id uuid)
 RETURNS TABLE(master_id uuid, sign_off_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select m.id, m.sign_off_at
  from public.work_orders w
  join public.work_orders m on m.job_id = w.job_id and m.kind = 'master'
  where w.id = p_work_order_id;
$function$
;

revoke all on function public.job_master_sign_off(uuid) from public, anon, authenticated;

-- =====================================================================
-- TRADE-LEVEL (4): refuse when the target is a master.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.add_material_item(p_work_order_id uuid, p_name text, p_quantity numeric DEFAULT 1, p_ready_by date DEFAULT NULL::date, p_sort_order integer DEFAULT 0)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_master_id uuid;
  v_sign_off_at timestamptz;
  v_trade text;
  v_item_id uuid;
  v_actor_id uuid;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');

  select w.trade into v_trade from public.work_orders w where w.id = p_work_order_id;
  select s.master_id, s.sign_off_at into v_master_id, v_sign_off_at
  from public.job_master_sign_off(p_work_order_id) s;

  insert into public.material_items (org_id, work_order_id, name, quantity, ready_by, sort_order)
  values (v_org_id, p_work_order_id, p_name, p_quantity, p_ready_by, p_sort_order)
  returning id into v_item_id;

  if v_sign_off_at is not null then
    select id into v_actor_id from public.profiles where id = auth.uid();
    insert into public.work_order_activity (work_order_id, org_id, action, to_value, actor_id)
    values (v_master_id, v_org_id, 'material_added_after_signoff',
            format('%s (%s)', p_name, coalesce(v_trade, 'trade')), v_actor_id);
  end if;

  return v_item_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.add_schedule_block(p_work_order_id uuid, p_crew_name text, p_start_date date, p_end_date date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_block_id uuid;
  v_blocking_name text;
  v_blocking_ready_by date;
  v_blocked boolean;
  v_reason text;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');

  select name, ready_by into v_blocking_name, v_blocking_ready_by
  from public.material_items
  where work_order_id = p_work_order_id and ready_by is not null
  order by ready_by desc
  limit 1;

  v_blocked := v_blocking_ready_by is not null and p_start_date < v_blocking_ready_by;
  v_reason := case when v_blocked
    then format('blocked on %s (ready %s)', v_blocking_name, v_blocking_ready_by)
    else null
  end;

  insert into public.schedule_blocks
    (org_id, work_order_id, crew_name, start_date, end_date, blocked, blocked_reason)
  values
    (v_org_id, p_work_order_id, p_crew_name, p_start_date, p_end_date, v_blocked, v_reason)
  returning id into v_block_id;

  return v_block_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.create_check_in(p_work_order_id uuid, p_crew_name text, p_schedule_block_id uuid DEFAULT NULL::uuid, p_check_in_date date DEFAULT CURRENT_DATE, p_hours numeric DEFAULT 0, p_materials_used text DEFAULT NULL::text, p_blockers text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_check_in_id uuid;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');

  insert into public.check_ins
    (org_id, work_order_id, schedule_block_id, crew_name, check_in_date, hours, materials_used, blockers)
  values
    (v_org_id, p_work_order_id, p_schedule_block_id, p_crew_name, coalesce(p_check_in_date, current_date), coalesce(p_hours, 0), p_materials_used, p_blockers)
  returning id into v_check_in_id;

  return v_check_in_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.get_or_create_production_packet(p_work_order_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_packet_id uuid;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');

  select id into v_packet_id
  from public.production_packets
  where work_order_id = p_work_order_id;

  if v_packet_id is not null then
    return v_packet_id;
  end if;

  insert into public.production_packets (org_id, work_order_id)
  values (v_org_id, p_work_order_id)
  returning id into v_packet_id;

  return v_packet_id;
end;
$function$
;

-- =====================================================================
-- MASTER-LEVEL (3): refuse when the target is a trade.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.record_work_order_sign_off(p_work_order_id uuid, p_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_was_signed_off boolean;
  v_old_notes text;
  v_actor_id uuid;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'master');

  select sign_off_at is not null, sign_off_notes
  into v_was_signed_off, v_old_notes
  from public.work_orders where id = p_work_order_id;

  update public.work_orders
  set sign_off_at = coalesce(sign_off_at, now()),
      sign_off_notes = coalesce(p_notes, sign_off_notes),
      updated_at = now()
  where id = p_work_order_id;

  if v_was_signed_off and p_notes is not null and p_notes is distinct from v_old_notes then
    select id into v_actor_id from public.profiles where id = auth.uid();
    insert into public.work_order_activity (work_order_id, org_id, action, from_value, to_value, actor_id)
    values (p_work_order_id, v_org_id, 'signoff_notes_updated_after_signoff', coalesce(v_old_notes, '—'), p_notes, v_actor_id);
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.create_work_order_agreement(p_work_order_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_job_id uuid;
  v_existing_id uuid;
  v_snapshot jsonb;
  v_agreement_id uuid;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'master');

  select job_id into v_job_id from public.work_orders where id = p_work_order_id;

  select id into v_existing_id
  from public.work_order_agreements
  where work_order_id = p_work_order_id and status <> 'voided';

  if v_existing_id is not null then
    return v_existing_id;
  end if;

  select jsonb_build_object(
    'work_order', jsonb_build_object(
      'id', wo.id,
      'sign_off_notes', wo.sign_off_notes
    ),
    'estimate', jsonb_build_object(
      'id', e.id,
      'estimate_number', e.estimate_number,
      'contact_name', e.contact_name,
      'company', e.company,
      'phone', e.phone,
      'email', e.email,
      'site_address', e.site_address,
      'squares', e.squares,
      'pitch', e.pitch
    ),
    'materials', coalesce((
      select jsonb_agg(
        jsonb_build_object('trade', t.trade, 'name', mi.name, 'quantity', mi.quantity, 'ready_by', mi.ready_by)
        order by t.trade, mi.sort_order
      )
      from public.material_items mi
      join public.work_orders t on t.id = mi.work_order_id
      where t.job_id = v_job_id and t.kind = 'trade' and t.voided_at is null
    ), '[]'::jsonb),
    'schedule', coalesce((
      select jsonb_agg(
        jsonb_build_object('trade', t.trade, 'crew_name', sb.crew_name, 'start_date', sb.start_date, 'end_date', sb.end_date)
        order by sb.start_date
      )
      from public.schedule_blocks sb
      join public.work_orders t on t.id = sb.work_order_id
      where t.job_id = v_job_id and t.kind = 'trade' and t.voided_at is null
    ), '[]'::jsonb)
  )
  into v_snapshot
  from public.work_orders wo
  join public.estimates e on e.id = wo.estimate_id
  where wo.id = p_work_order_id;

  insert into public.work_order_agreements (org_id, work_order_id, snapshot)
  values (v_org_id, p_work_order_id, v_snapshot)
  returning id into v_agreement_id;

  return v_agreement_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.fetch_work_order_agreement(p_work_order_id uuid)
 RETURNS SETOF work_order_agreements
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.assert_work_order_level(p_work_order_id, 'master');

  return query
  select a.*
  from public.work_order_agreements a
  where a.work_order_id = p_work_order_id
    and a.status <> 'voided'
    and a.org_id in (select my_org_ids())
  order by a.created_at desc
  limit 1;
end;
$function$
;

-- =====================================================================
-- CHILD-ID (2): level resolves THROUGH THE PARENT. No work-order argument.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.update_material_item(p_material_item_id uuid, p_name text DEFAULT NULL::text, p_quantity numeric DEFAULT NULL::numeric, p_ready_by date DEFAULT NULL::date, p_sort_order integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_wo_org_id uuid;
  v_work_order_id uuid;
  v_trade text;
  v_master_id uuid;
  v_sign_off_at timestamptz;
  v_old_name text;
  v_old_quantity numeric;
  v_old_ready_by date;
  v_actor_id uuid;
begin
  select mi.org_id, wo.org_id, mi.work_order_id, wo.trade, mi.name, mi.quantity, mi.ready_by
  into v_org_id, v_wo_org_id, v_work_order_id, v_trade, v_old_name, v_old_quantity, v_old_ready_by
  from public.material_items mi
  join public.work_orders wo on wo.id = mi.work_order_id
  where mi.id = p_material_item_id;

  if v_org_id is null
     or v_org_id not in (select my_org_ids())
     or coalesce(v_wo_org_id, '00000000-0000-0000-0000-000000000000'::uuid) <> v_org_id then
    raise exception 'material item not found or not accessible: %', p_material_item_id;
  end if;

  select s.master_id, s.sign_off_at into v_master_id, v_sign_off_at
  from public.job_master_sign_off(v_work_order_id) s;

  update public.material_items
  set name = coalesce(p_name, name),
      quantity = coalesce(p_quantity, quantity),
      ready_by = coalesce(p_ready_by, ready_by),
      sort_order = coalesce(p_sort_order, sort_order),
      updated_at = now()
  where id = p_material_item_id;

  if v_sign_off_at is not null then
    select id into v_actor_id from public.profiles where id = auth.uid();
    insert into public.work_order_activity (work_order_id, org_id, action, from_value, to_value, actor_id)
    values (
      coalesce(v_master_id, v_work_order_id), v_org_id, 'material_updated_after_signoff',
      format('%s (qty %s%s)', v_old_name, v_old_quantity, case when v_old_ready_by is not null then ', ready ' || v_old_ready_by else '' end),
      format('%s (qty %s%s) [%s]', coalesce(p_name, v_old_name), coalesce(p_quantity, v_old_quantity), case when coalesce(p_ready_by, v_old_ready_by) is not null then ', ready ' || coalesce(p_ready_by, v_old_ready_by) else '' end, coalesce(v_trade, 'trade')),
      v_actor_id
    );
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.delete_material_item(p_material_item_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid;
  v_wo_org_id uuid;
  v_work_order_id uuid;
  v_trade text;
  v_master_id uuid;
  v_sign_off_at timestamptz;
  v_name text;
  v_actor_id uuid;
begin
  select mi.org_id, wo.org_id, mi.work_order_id, wo.trade, mi.name
  into v_org_id, v_wo_org_id, v_work_order_id, v_trade, v_name
  from public.material_items mi
  join public.work_orders wo on wo.id = mi.work_order_id
  where mi.id = p_material_item_id;

  if v_org_id is null
     or v_org_id not in (select my_org_ids())
     or coalesce(v_wo_org_id, '00000000-0000-0000-0000-000000000000'::uuid) <> v_org_id then
    raise exception 'material item not found or not accessible: %', p_material_item_id;
  end if;

  select s.master_id, s.sign_off_at into v_master_id, v_sign_off_at
  from public.job_master_sign_off(v_work_order_id) s;

  delete from public.material_items where id = p_material_item_id;

  if v_sign_off_at is not null then
    select id into v_actor_id from public.profiles where id = auth.uid();
    insert into public.work_order_activity (work_order_id, org_id, action, from_value, actor_id)
    values (coalesce(v_master_id, v_work_order_id), v_org_id, 'material_deleted_after_signoff',
            format('%s (%s)', v_name, coalesce(v_trade, 'trade')), v_actor_id);
  end if;
end;
$function$
;
