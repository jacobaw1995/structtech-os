-- A4.2 — THE SPECIAL-TRIP LOG. A REASON IS A CODE, NEVER FREE TEXT.
-- Track S · 2026-09-28. Track U built the surface on 2026-09-23 (U-W1.31) and left it
-- UNWIRED and unmounted, because no schema existed. This is the schema.
--
-- BEFORE-MEASUREMENT, and it is stronger than "prose in a box":
--   · NO table, NO column, NO function anywhere records a special trip. The only hits for
--     `trip` in the whole schema are `wh_orders.stripe_payment_intent_id` and its index —
--     s-TRIP-e, a substring false positive of exactly the kind CLAUDE.md rule 15 warns about.
--   · The current path U measured — 3-4 taps of prose into the check-in's "Anything
--     blocking?" box — has recorded ZERO special trips, because `check_ins` holds
--     **0 ROWS IN THE ENTIRE DATABASE**. Nobody has ever completed a check-in in production.
-- So the count of special trips recorded today by any means is **0 of 0**, and the 3-4 taps
-- is a measurement of the DESIGN, not of use. There is no prose to migrate and no existing
-- count to preserve — the cheapest possible moment to make the reason a code.
--
-- THE VOCABULARY IS TRACK U's, ADOPTED VERBATIM (src/lib/field/special-trip.ts), the same
-- call as taking U's state names on 2026-09-28. Seven codes and **deliberately no "other"**:
-- U's file gives the reason and it is right — *"a free-text escape hatch is where a code list
-- goes to die, because the hatch is always the fastest button to press."* The list is in a
-- CHECK rather than in tenant config because the point of the log is to be COUNTED ACROSS
-- TENANTS: "nine trips back for missing material last month" is a number only if every tenant
-- spells it the same way. A per-tenant extension later is additive, and rule 4 governs the
-- value change (DROP → UPDATE rows → ADD).
--
-- RULE 13 — what would have to change for a bad reason to get in? "Somebody alters this CHECK
-- constraint", which is a statement about this table, visible in the diff that makes it. Not
-- "somebody types anything".
--
-- TWO DATES, NEVER ONE. `occurred_on` is the day the crew came back; `recorded_at` is when
-- they tapped it. Conflating them is the defect closed on `check_ins.check_in_date` on
-- 2026-09-16. **`occurred_on` has NO COLUMN DEFAULT** — the RPC derives it, in New York's
-- calendar and never the session's, so the derivation is in one visible place instead of
-- hidden in a column default nobody reads (2026-09-25's silent-answer rule).
--
-- FULL CRUD (SCOPE §2.6). A mis-tapped trip is a number somebody will later defend in a
-- meeting, so it must be removable by the person who tapped it. Delete follows `check_ins`'
-- author-or-office rule exactly.

create table public.special_trips (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null references public.organizations(id) on delete cascade,
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  reason_code   text not null,
  occurred_on   date not null,
  note          text,
  recorded_by   uuid not null references public.profiles(id),
  recorded_at   timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  constraint special_trips_reason_code_check check (reason_code in (
    'material_missing', 'material_wrong', 'access', 'weather',
    'customer_change', 'rework', 'equipment'
  ))
);

create index special_trips_work_order on public.special_trips (work_order_id, occurred_on desc);
create index special_trips_org_reason on public.special_trips (org_id, reason_code, occurred_on desc);

-- GRANTS — the house standard measured over 51 owned tables (rule 8 as amended 2026-09-14):
-- `authenticated` gets SELECT/INSERT/UPDATE/DELETE exactly, `anon` nothing. TRUNCATE is
-- revoked explicitly because RLS cannot mediate it — that is the hole the three purchase-order
-- tables carried from 2026-09-07 until 2026-09-15.
revoke all on table public.special_trips from anon;
revoke truncate, references, trigger, maintain on table public.special_trips from authenticated;
grant select, insert, update, delete on table public.special_trips to authenticated;

alter table public.special_trips enable row level security;

-- Policies scoped TO authenticated (rule 8): a policy left TO public must be EVALUATED for
-- anon, which is what took the Material Matrix storefront down on 2026-08-20.
create policy "member read own special_trips" on public.special_trips
  for select to authenticated
  using (org_id in (select my_org_ids()));

create policy "member insert own special_trips" on public.special_trips
  for insert to authenticated
  with check (org_id in (select my_org_ids()));

create policy "member delete special_trips author or office" on public.special_trips
  for delete to authenticated
  using (
    org_id in (select my_org_ids())
    and (
      coalesce(recorded_by = auth.uid(), false)
      or coalesce(public.can_view_master_work_order(org_id), false)
    )
  );

create function public.record_special_trip(
  p_work_order_id uuid,
  p_reason_code text,
  p_occurred_on date default null::date,
  p_note text default null::text
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

create function public.delete_special_trip(p_special_trip_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_recorded_by uuid;
begin
  select org_id, recorded_by into v_org_id, v_recorded_by
  from public.special_trips where id = p_special_trip_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'special trip not found or not accessible: %', p_special_trip_id
      using hint = 'special_trip_not_found';
  end if;

  -- Author or office, the same rule check_ins carries. coalesce because PL/pgSQL treats a
  -- NULL condition as FALSE and an unowned row would otherwise be deletable by nobody
  -- (rule 5, inverted: here the NULL would close rather than open, and it is still wrong).
  if not (coalesce(v_recorded_by = auth.uid(), false)
          or coalesce(public.can_view_master_work_order(v_org_id), false)) then
    raise exception 'only the person who recorded this trip, or the office, can remove it'
      using hint = 'delete_needs_author_or_office';
  end if;

  delete from public.special_trips where id = p_special_trip_id;
end;
$function$;

-- Rule 7: PostgreSQL grants EXECUTE on a new function to PUBLIC, and that grant shows up as
-- the leading `=X/postgres` entry. A revoke naming only `anon` is a NO-OP. `authenticated` is
-- KEPT for both — the test is "does anything outside the database call this?" and the answer
-- here is yes: U's SpecialTripPanel, through a server action.
revoke execute on function public.record_special_trip(uuid, text, date, text) from public, anon;
grant execute on function public.record_special_trip(uuid, text, date, text) to authenticated;
revoke execute on function public.delete_special_trip(uuid) from public, anon;
grant execute on function public.delete_special_trip(uuid) to authenticated;
