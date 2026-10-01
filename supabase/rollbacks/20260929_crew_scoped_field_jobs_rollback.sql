-- ROLLBACK for 20260929_crew_scoped_field_jobs. Written BEFORE the migration applied,
-- from the live pg_get_functiondef captured the same session.
--
-- READ THIS BEFORE RUNNING IT. It restores three defects at once:
--   · every member of an org sees every unfinished trade job in it again;
--   · `p_today` goes back to DEFAULT CURRENT_DATE — the SESSION's date, which is UTC, so
--     from 8 PM EDT a caller that omits it asks for TOMORROW and a job ending today
--     disappears off the crew screen that evening;
--   · a foreign org_id goes back to returning `[]`, which a crew screen renders as
--     "no jobs" — "cannot see" shown as "does not exist".
-- It does NOT drop tenant_scopes_field_jobs_to_crew, and it does not clear
-- `organizations.policy -> 'scope_field_jobs_to_crew'`. If any tenant has the switch ON,
-- CLEAR IT FIRST or the key silently stops meaning anything:
--   update public.organizations set policy = policy - 'scope_field_jobs_to_crew';

drop function if exists public.fetch_field_jobs(p_org_id uuid, p_today date);

CREATE OR REPLACE FUNCTION public.fetch_field_jobs(p_org_id uuid, p_today date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'schedule_block_id', j.id,
        'work_order_id', j.work_order_id,
        'crew_name', j.crew_name,
        'start_date', j.start_date,
        'end_date', j.end_date,
        'ready_by_conflict', j.ready_by_conflict,
        'ready_by_conflict_reason', j.ready_by_conflict_reason,
        'job_title', coalesce(nullif(j.company, ''), j.contact_name),
        'site_address', j.site_address,
        'squares', j.squares,
        'pitch', j.pitch
      ) order by j.start_date, j.created_at
    ), '[]'::jsonb)
  from (
    select sb.id, sb.work_order_id, sb.crew_name, sb.start_date, sb.end_date,
           sb.ready_by_conflict, sb.ready_by_conflict_reason, sb.created_at,
           e.company, e.contact_name, e.site_address, e.squares, e.pitch
    from public.schedule_blocks sb
    join public.work_orders w on w.id = sb.work_order_id
    join public.estimates e on e.id = w.estimate_id
    where sb.org_id = p_org_id
      and p_org_id in (select my_org_ids())
      and w.kind = 'trade'
      and w.voided_at is null
      and sb.end_date >= p_today
    order by sb.start_date, sb.created_at
    limit 20
  ) j;
$function$

;

revoke execute on function public.fetch_field_jobs(uuid, date) from public, anon;
grant execute on function public.fetch_field_jobs(uuid, date) to authenticated;
