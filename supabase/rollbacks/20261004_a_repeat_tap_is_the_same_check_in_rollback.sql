-- ROLLBACK for 20261004213144_a_repeat_tap_is_the_same_check_in.sql
-- Written BEFORE the migration was written, let alone applied.
--
-- Takes `create_check_in` back to its 8-argument form, VERBATIM from
-- pg_get_function_identity_arguments() as it stood at 2026-10-04 17:31 EDT
-- (migration rule 2 — a retyped signature drops nothing and reports success),
-- drops the partial unique index, and drops the column.
--
-- SAFE TO RUN WHILE THE NEW UI IS DEPLOYED? NO, and say so rather than discover it.
-- A deployed caller sending p_client_token would fail to resolve against the
-- 8-arg function. Roll the UI back first, or accept that check-in creation
-- refuses until you do. Dropping the column DISCARDS every recorded token; the
-- check-in rows themselves are untouched.

begin;

drop function if exists public.create_check_in(p_work_order_id uuid, p_crew_name text, p_schedule_block_id uuid, p_check_in_date date, p_hours numeric, p_materials_used text, p_blockers text, p_crew_id uuid, p_client_token text);

create or replace function public.create_check_in(
  p_work_order_id uuid,
  p_crew_name text,
  p_schedule_block_id uuid default null::uuid,
  p_check_in_date date default null::date,
  p_hours numeric default null::numeric,
  p_materials_used text default null::text,
  p_blockers text default null::text,
  p_crew_id uuid default null::uuid
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_check_in_id uuid;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');

  if p_crew_id is null and nullif(btrim(p_crew_name), '') is null then
    raise exception 'choose a crew, or type who is doing the work' using hint = 'crew_required';
  end if;

  -- The date is New York's, never the session's (2026-09-16). A blank hours field is "not recorded" (NULL),
  -- never 0. With a crew, crew_name is derived by check_ins_crew_name.
  insert into public.check_ins
    (org_id, work_order_id, schedule_block_id, crew_id, crew_name, check_in_date, hours, materials_used, blockers)
  values
    (v_org_id, p_work_order_id, p_schedule_block_id, p_crew_id, coalesce(nullif(btrim(p_crew_name), ''), '(crew)'),
     coalesce(p_check_in_date, (now() at time zone 'America/New_York')::date),
     p_hours, p_materials_used, p_blockers)
  returning id into v_check_in_id;

  return v_check_in_id;
end;
$function$;

-- RULE 7, AND ITS MECHANISM. A function recreated in `public` is born holding the
-- built-in grant to PUBLIC, which shows up in proacl as a leading `=X/postgres`
-- with no grantee before the `=`. Naming only `anon` is a no-op. `authenticated`
-- is NOT revoked: every check-in the app writes is this call, made as
-- `authenticated`, so that grant IS the call path (rule 7's carve-out, answered
-- for this function: yes, something outside the database calls it).
revoke execute on function public.create_check_in(p_work_order_id uuid, p_crew_name text, p_schedule_block_id uuid, p_check_in_date date, p_hours numeric, p_materials_used text, p_blockers text, p_crew_id uuid) from public, anon;
grant execute on function public.create_check_in(p_work_order_id uuid, p_crew_name text, p_schedule_block_id uuid, p_check_in_date date, p_hours numeric, p_materials_used text, p_blockers text, p_crew_id uuid) to authenticated;

drop index if exists public.check_ins_client_token_uniq;
alter table public.check_ins drop constraint if exists check_ins_client_token_shape;
alter table public.check_ins drop column if exists client_token;

-- VERIFY, do not trust the success response (rule 3).
select p.proname, pg_get_function_identity_arguments(p.oid) as args,
       coalesce(array_to_string(p.proacl,' | '),'(null = PUBLIC HAS EXECUTE — WRONG)') as acl
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'create_check_in';
select count(*) as should_be_zero from information_schema.columns
where table_schema='public' and table_name='check_ins' and column_name='client_token';

commit;
