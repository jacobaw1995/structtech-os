-- A RESENT SPECIAL TRIP IS THE SAME TRIP, NOT A SECOND ONE.
-- 2026-10-04, Track S. A DELIBERATE MIRROR of 20261004213144, applied two hours
-- earlier the same evening: same column, same shape CHECK, same partial unique
-- index, same trailing defaulted parameter, same two-layer function, same
-- revoke. One idea, one shape — a second shape for the same idea is a second
-- thing to remember.
--
-- MEASURED FIRST, and Track U's reading is confirmed: `special_trips` holds
-- **0 rows**, carries **3 indexes of which exactly 1 is unique**, and that one
-- is `special_trips_pkey` on a `gen_random_uuid()` default. A key over a value
-- generated per row cannot collide, so every insert was accepted. There is no
-- trigger on the table and no function returns `SETOF special_trips`.
--
-- AND THE EDGE THAT IS SHARPER HERE THAN ON CHECK-INS. `record_special_trip`
-- coalesces a null `p_occurred_on` to New York's today — correctly, because a
-- trip recorded now happened now and the database is the one that knows that
-- (§7.1 RULE 22). The consequence is that a resend whose answer was lost does
-- not need a date to collide: it lands a SECOND trip, same day, same reason,
-- same work order, straight into the count the panel exists to produce. On
-- check-ins a duplicate is a visible extra row in a list; here it is a silent
-- +1 in a number somebody will quote at a customer.
--
-- A NATURAL KEY WAS REJECTED FOR THE SAME REASONS AS ON check_ins, AND ONE MORE
-- THAT IS SPECIFIC TO THIS TABLE. (work_order_id, reason_code, occurred_on) is
-- almost tempting, because `special_trips_org_reason` already indexes those
-- columns. But TWO SPECIAL TRIPS TO THE SAME JOB ON THE SAME DAY FOR THE SAME
-- REASON ARE A REAL THING — two runs for the wrong material is the example the
-- reason code `material_wrong` exists to count — and a unique key would refuse
-- the second one, scoring it as one trip. That is not a near-miss: it makes the
-- count WRONG IN THE DIRECTION THAT FLATTERS US, which is the worst direction
-- for a number whose whole purpose is to show what the job really cost. SCOPE
-- §2.8 forbids the refusal; the arithmetic forbids it twice.
--
-- SO: A REPEAT CALL CARRYING THE SAME TOKEN IS SILENTLY IGNORED AND REPORTED AS
-- SUCCESS. The call returns the id of the row the first attempt wrote, so a
-- deduplicated trip reads as "recorded", never as an error, and the count moves
-- by exactly one. A DELIBERATE second trip carries a new token and is accepted.
--
-- RULE 5b — NOTHING IS ENFORCED UNTIL A CALLER OPTS IN. The column is NULLABLE,
-- the index is PARTIAL (`where client_token is not null`), and the parameter is
-- TRAILING with a default. Production serves 6a85e6a (live 18:49:10 EDT today),
-- whose special-trip panel sends four named arguments and no token: that call
-- resolves unchanged and writes NULL, which this function documents as "never
-- deduplicated". Both src readers of this table enumerate their columns
-- explicitly, so an added column cannot widen a row they project.
--
-- RULE 1 — the signature CHANGES, so the old one is DROPPED, not replaced; the
-- identity argument list below was copied verbatim from
-- pg_get_function_identity_arguments() at 2026-10-04 18:52 EDT, not retyped
-- (rule 2). Overloads before: 1. Expected after: 1.


-- 1 · THE COLUMN. Nullable, and NORMALISED TO NULL WHEN BLANK, in the function
-- and at the table. The blank case is the dangerous one: a panel that always
-- sends the field, empty, would hand every special trip in an org the SAME
-- token and silently collapse the second onwards onto the first — the count the
-- table exists to produce, stuck at 1. That is rule 15's last paragraph (a
-- resubmitted value is not a deliberate write) pointed at a number.
alter table public.special_trips add column if not exists client_token text;

alter table public.special_trips drop constraint if exists special_trips_client_token_shape;
alter table public.special_trips add constraint special_trips_client_token_shape
  check (client_token is null or (btrim(client_token) = client_token and length(client_token) between 8 and 200));

comment on column public.special_trips.client_token is
  'Idempotency token for ONE attempt to record a trip. NULL means "no token sent" and is never deduplicated. Unique per org while not null. A resend carrying the same token returns the original row''s id and adds nothing to the count; a deliberate second trip carries a new one.';

-- 2 · THE CONSTRAINT. Partial, so the NULLs a tokenless caller writes do not
-- collide with each other. Scoped by org_id because a token is a client's and
-- two tenants must never be able to collide, deliberately or by accident.
create unique index if not exists special_trips_client_token_uniq
  on public.special_trips (org_id, client_token)
  where client_token is not null;

-- 3 · THE WRITE PATH. Everything above the token is UNCHANGED, including both
-- named refusals: an unsigned caller and a bad reason code are still refused BY
-- NAME, before the token is consulted. Deduplication must never be the thing
-- that answers an invalid call.
drop function if exists public.record_special_trip(p_work_order_id uuid, p_reason_code text, p_occurred_on date, p_note text);

create function public.record_special_trip(
  p_work_order_id uuid,
  p_reason_code text,
  p_occurred_on date default null::date,
  p_note text default null::text,
  p_client_token text default null::text
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_actor_id uuid;
  v_id uuid;
  v_token text;
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

  -- A BLANK TOKEN IS NO TOKEN. See the note on the column.
  v_token := nullif(btrim(p_client_token), '');

  -- THE FAST PATH, and the one that runs on a flaky connection: this attempt is
  -- already recorded, so hand back the row it made. No error, no second trip, no
  -- change to the count, and the caller cannot tell the difference.
  if v_token is not null then
    select id into v_id
    from public.special_trips
    where org_id = v_org_id and client_token = v_token;

    if v_id is not null then
      return v_id;
    end if;
  end if;

  begin
    insert into public.special_trips (org_id, work_order_id, reason_code, occurred_on, note, recorded_by, client_token)
    values (
      v_org_id, p_work_order_id, p_reason_code,
      -- New York's calendar, never the session's. NOT AN ARGUMENT — MEASURED AT THE MOMENT THIS
      -- MIGRATION WAS WRITTEN, 2026-09-28 22:49 EDT: `current_date` returned **2026-09-29** and
      -- `(now() at time zone 'America/New_York')::date` returned **2026-09-28**. A trip recorded
      -- in that minute with a CURRENT_DATE default is dated TOMORROW. (The same trap, in the same
      -- hour, put "Tuesday 2026-09-29" on a directive written on Monday night.)
      coalesce(p_occurred_on, (now() at time zone 'America/New_York')::date),
      nullif(btrim(coalesce(p_note, '')), ''),
      v_actor_id,
      v_token
    )
    returning id into v_id;
  exception when unique_violation then
    -- THE RACE THE SELECT ABOVE CANNOT CLOSE. Two requests from one tap can both
    -- read "not there" and both try to insert; one wins, and the loser must still
    -- answer with the id that was written, not with an error. Re-read, never recurse.
    select id into v_id
    from public.special_trips
    where org_id = v_org_id and client_token = v_token;

    if v_id is null then
      -- Not our index: something else is unique and genuinely conflicted. Do not
      -- swallow it — a defect that reports success is worse than one that raises.
      raise;
    end if;
  end;

  return v_id;
end;
$function$;

-- RULE 7, AND ITS MECHANISM. A function created in `public` is born holding
-- PostgreSQL's built-in grant to PUBLIC. It appears in proacl as the LEADING
-- `=X/postgres` with no grantee name before the `=`; it is NOT a grant to
-- `anon`, so a revoke naming only `anon` removes a grant that was never there,
-- reports success, and leaves `anon` executing through its PUBLIC membership.
-- The `public` in this statement is the part that works.
-- The `authenticated` carve-out, answered FOR THIS FUNCTION: the crew's special
-- trip panel calls it as `authenticated`, so that grant is the application's own
-- path and revoking it would break the product, not an attacker.
revoke execute on function public.record_special_trip(p_work_order_id uuid, p_reason_code text, p_occurred_on date, p_note text, p_client_token text) from public, anon;
grant execute on function public.record_special_trip(p_work_order_id uuid, p_reason_code text, p_occurred_on date, p_note text, p_client_token text) to authenticated;

