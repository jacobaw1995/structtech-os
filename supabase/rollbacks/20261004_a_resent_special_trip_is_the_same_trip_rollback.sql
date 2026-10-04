-- ROLLBACK for 20261004225242_a_resent_special_trip_is_the_same_trip.sql
-- Written BEFORE the migration. Track S, 2026-10-04.
--
-- Mirrors 20261004_a_repeat_tap_is_the_same_check_in_rollback.sql, because the
-- forward migrations are mirrors. Takes `record_special_trip` back to its
-- 4-argument form, VERBATIM from pg_get_function_identity_arguments() as it
-- stood at 2026-10-04 18:52 EDT (rule 2 — a retyped signature drops nothing and
-- reports success), drops the partial unique index and the shape CHECK, then
-- drops the column.
--
-- SAFE WHILE A TOKEN-SENDING UI IS DEPLOYED? NO. A caller passing
-- p_client_token would fail to resolve against the 4-arg function. Roll the UI
-- back first, or accept that recording a special trip refuses until you do.
-- Dropping the column discards every recorded token; the trips themselves are
-- untouched.

begin;

drop function if exists public.record_special_trip(p_work_order_id uuid, p_reason_code text, p_occurred_on date, p_note text, p_client_token text);

create or replace function public.record_special_trip(p_work_order_id uuid, p_reason_code text, p_occurred_on date default null::date, p_note text default null::text)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_actor_id uuid;
  v_id uuid;
begin
  -- A trip belongs to a TRADE work order, the same level a check-in belongs to. The master is
  -- refused by assert_work_order_level with its own named message.
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');

  select id into v_actor_id from public.profiles where id = auth.uid();
  if v_actor_id is null then
    raise exception 'sign in before recording a special trip'
      using hint = 'not_signed_in';
  end if;

  -- The code is checked HERE as well as in the constraint, so the refusal is a sentence a
  -- person can read rather than a 23514 (the same call as org_members_portal_viewer_never_schedules).
  if p_reason_code is null or p_reason_code not in (
    'material_missing', 'material_wrong', 'access', 'weather',
    'customer_change', 'rework', 'equipment'
  ) then
    raise exception 'pick a reason from the list — a special trip is counted, so the reason has to be one of the codes'
      using hint = 'special_trip_reason_required';
  end if;

  insert into public.special_trips (org_id, work_order_id, reason_code, occurred_on, note, recorded_by)
  values (
    v_org_id, p_work_order_id, p_reason_code,
    -- New York's calendar, never the session's. NOT AN ARGUMENT — MEASURED AT THE MOMENT THIS
    -- MIGRATION WAS WRITTEN, 2026-09-28 22:49 EDT: `current_date` returned **2026-09-29** and
    -- `(now() at time zone 'America/New_York')::date` returned **2026-09-28**. A trip recorded
    -- in that minute with a CURRENT_DATE default is dated TOMORROW. (The same trap, in the same
    -- hour, put "Tuesday 2026-09-29" on a directive written on Monday night.)
    coalesce(p_occurred_on, (now() at time zone 'America/New_York')::date),
    nullif(btrim(coalesce(p_note, '')), ''),
    v_actor_id
  )
  returning id into v_id;

  return v_id;
end;
$function$;

-- RULE 7 AND ITS MECHANISM. A function recreated in `public` is born holding the
-- built-in grant to PUBLIC, which appears in proacl as a LEADING `=X/postgres`
-- with no grantee before the `=`; naming only `anon` is a no-op. `authenticated`
-- is kept: the crew's panel calls this as `authenticated`, so that grant IS the
-- call path (rule 7's carve-out, answered for this function).
revoke execute on function public.record_special_trip(p_work_order_id uuid, p_reason_code text, p_occurred_on date, p_note text) from public, anon;
grant execute on function public.record_special_trip(p_work_order_id uuid, p_reason_code text, p_occurred_on date, p_note text) to authenticated;

drop index if exists public.special_trips_client_token_uniq;
alter table public.special_trips drop constraint if exists special_trips_client_token_shape;
alter table public.special_trips drop column if exists client_token;

-- VERIFY, do not trust the success response (rule 3).
select p.proname, pg_get_function_identity_arguments(p.oid) as args,
       coalesce(array_to_string(p.proacl,' | '),'(null = PUBLIC HAS EXECUTE — WRONG)') as acl
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'record_special_trip';
select count(*) as should_be_zero from information_schema.columns
where table_schema='public' and table_name='special_trips' and column_name='client_token';

commit;
