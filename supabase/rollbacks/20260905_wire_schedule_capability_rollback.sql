-- ROLLBACK for 20260905 wire_schedule_capability.
-- Captured from pg_proc / pg_policy on the LIVE database 2026-09-05 BEFORE the
-- change (§7.1 Rule 1 — restore what RAN, not present intent).
--
-- NOTE the policies below are restored TO public, which is their PRE-CHANGE
-- shape and is the old convention (CLAUDE.md rule 8 wants TO authenticated).
-- That is deliberate: a rollback reproduces what was there, not what we wish
-- had been there.

drop policy if exists "scheduler insert own schedule_blocks" on public.schedule_blocks;
drop policy if exists "scheduler update own schedule_blocks" on public.schedule_blocks;
drop policy if exists "scheduler delete own schedule_blocks" on public.schedule_blocks;
drop policy if exists "member read own schedule_blocks" on public.schedule_blocks;

create policy "member read own schedule_blocks" on public.schedule_blocks
  for select to public using ((org_id IN ( SELECT my_org_ids() AS my_org_ids)));
create policy "member insert own schedule_blocks" on public.schedule_blocks
  for insert to public with check (((org_id IN ( SELECT my_org_ids() AS my_org_ids)) AND work_order_is_my_trade(work_order_id)));
create policy "member update own schedule_blocks" on public.schedule_blocks
  for update to public using (((org_id IN ( SELECT my_org_ids() AS my_org_ids)) AND work_order_is_my_trade(work_order_id)))
  with check (((org_id IN ( SELECT my_org_ids() AS my_org_ids)) AND work_order_is_my_trade(work_order_id)));
create policy "member delete own schedule_blocks" on public.schedule_blocks
  for delete to public using ((org_id IN ( SELECT my_org_ids() AS my_org_ids)));

CREATE OR REPLACE FUNCTION public.delete_schedule_block(p_schedule_block_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_org_id uuid; v_work_order_id uuid;
begin
  select org_id, work_order_id into v_org_id, v_work_order_id
  from public.schedule_blocks where id = p_schedule_block_id;
  if v_org_id is null then raise exception 'schedule block not found or not accessible: %', p_schedule_block_id; end if;
  if public.assert_work_order_level(v_work_order_id, 'trade') <> v_org_id then
    raise exception 'schedule block not found or not accessible: %', p_schedule_block_id; end if;
  delete from public.schedule_blocks where id = p_schedule_block_id;
end;
$function$;

-- add_schedule_block / update_schedule_block: restore the 2026-09-03 bodies from
-- supabase/migrations/20260903213105_a2_3_ready_by_conflict_rename_and_tenant_stage_gating.sql
-- (their PART 3 definitions, verbatim) — they are unchanged by this migration
-- except for the capability guard added at the top of each.
