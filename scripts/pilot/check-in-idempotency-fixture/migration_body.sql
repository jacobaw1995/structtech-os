-- A REPEAT TAP IS THE SAME CHECK-IN, NOT A SECOND ONE.
-- 2026-10-04, Track S. Three days before the pilot.
--
-- MEASURED FIRST. The only unique constraint on `check_ins` was
-- `check_ins_pkey` on a `gen_random_uuid()` default — four unique indexes on the
-- table, one unique, and it can never collide. Track U's reading is confirmed.
-- Every insert was accepted. Jacob reached four identical rows at 16:51 EDT
-- today by tapping one button, and deleted three by hand.
--
-- WHY AN IDEMPOTENCY TOKEN AND NOT A NATURAL KEY. A natural key over
-- (work_order_id, crew, check_in_date) was considered and REJECTED, for four
-- reasons, in increasing order of how much they matter:
--
--   1. It legislates a product rule nobody has decided — "one check-in per crew
--      per job per day". Nothing in SCOPE says that. A crew splitting a day, a
--      second person logging separately, or a correction kept as its own row all
--      become impossible, and the decision gets made by a DDL statement instead
--      of by Jacob.
--   2. It breaks SCOPE §2.8. A legitimate second check-in would be refused
--      because of a row that already exists. That is the thing §2.8 forbids.
--   3. IT CANNOT BE BUILT ON THE COLUMNS THAT EXIST. The one live check-in has
--      `crew_id` NULL and `schedule_block_id` NULL, and `crew_name` falls back to
--      the literal '(crew)'. So the key would rest on `crew_name` — free text,
--      and MUTABLE BY AN UNRELATED ACTION: the trigger `crews_carry_name`
--      rewrites `check_ins.crew_name` whenever somebody renames a crew. That is
--      migration rule 10's defect exactly — a guard keyed on a mutable column
--      reproduces *a* row, not *the* row — and here the mutation is somebody
--      else's edit on a different screen.
--   4. THE FAILURE MODE IS THE WRONG ONE. A unique violation surfaces to the
--      crew as an error. The requirement is the opposite: a roofer must never be
--      told his check-in failed when it had already been recorded.
--
-- SO: TAPS 2, 3 AND 4 ARE SILENTLY IGNORED AND REPORTED AS SUCCESS. The call
-- returns the id of the row tap 1 created. One row, one confirmation, no error,
-- on any number of taps and by any path — a retried fetch, a resumed service
-- worker, two phones, a flaky connection coming back.
--
-- THE TOKEN IS PER SUBMISSION ATTEMPT, NOT PER FORM FIELD. A deliberate second
-- check-in carries a new token and is accepted, so nothing is blocked.
--
-- RULE 5b — BACKWARD COMPATIBLE WITH THE UI THAT IS DEPLOYED RIGHT NOW.
-- Production serves 48c30c7 (live 17:29:33 EDT today), whose `createCheckIn`
-- sends eight named arguments and no token. The column is NULLABLE, the unique
-- index is PARTIAL (`where client_token is not null`), and the new parameter is
-- TRAILING with a default — so today's deployed caller resolves and behaves
-- exactly as before, writing NULL. Nothing is enforced until the UI opts in by
-- sending a token. No value becomes illegal; sending one becomes deliberate.
--
-- RULE 1 — the signature CHANGES, so the old one is DROPPED, not replaced.
-- `create or replace` with an added trailing parameter creates an OVERLOAD, and
-- two overloads make the PostgREST call ambiguous. The identity argument list
-- below was copied verbatim from pg_get_function_identity_arguments() at
-- 2026-10-04 17:31 EDT and not retyped (rule 2).


-- 1 · THE COLUMN. Nullable, text, and NORMALISED TO NULL WHEN BLANK.
-- The blank case is not hypothetical and is the dangerous one: a form that
-- always sends the field, empty, would hand every check-in in an org the SAME
-- token, and the second one onwards would collapse onto the first. That is
-- rule 15's last paragraph — a resubmitted value is not a deliberate write —
-- and it is guarded in the function AND at the table.
alter table public.check_ins add column if not exists client_token text;

alter table public.check_ins drop constraint if exists check_ins_client_token_shape;
alter table public.check_ins add constraint check_ins_client_token_shape
  check (client_token is null or (btrim(client_token) = client_token and length(client_token) between 8 and 200));

comment on column public.check_ins.client_token is
  'Idempotency token for ONE submission attempt. NULL means "no token sent" and is never deduplicated. Unique per org while not null. A retry of the same attempt carries the same token and returns the original row''s id; a deliberate second check-in carries a new one.';

-- 2 · THE CONSTRAINT. Partial, so the NULLs that the deployed UI writes do not
-- collide with each other. Scoped by org_id because a token is a client's, and
-- two tenants must never be able to collide — deliberately or by accident.
create unique index if not exists check_ins_client_token_uniq
  on public.check_ins (org_id, client_token)
  where client_token is not null;

-- 3 · THE WRITE PATH.
drop function if exists public.create_check_in(p_work_order_id uuid, p_crew_name text, p_schedule_block_id uuid, p_check_in_date date, p_hours numeric, p_materials_used text, p_blockers text, p_crew_id uuid);

create function public.create_check_in(
  p_work_order_id uuid,
  p_crew_name text,
  p_schedule_block_id uuid default null::uuid,
  p_check_in_date date default null::date,
  p_hours numeric default null::numeric,
  p_materials_used text default null::text,
  p_blockers text default null::text,
  p_crew_id uuid default null::uuid,
  p_client_token text default null::text
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org_id uuid;
  v_check_in_id uuid;
  v_token text;
begin
  v_org_id := public.assert_work_order_level(p_work_order_id, 'trade');

  if p_crew_id is null and nullif(btrim(p_crew_name), '') is null then
    raise exception 'choose a crew, or type who is doing the work' using hint = 'crew_required';
  end if;

  -- A BLANK TOKEN IS NO TOKEN. See the note on the column.
  v_token := nullif(btrim(p_client_token), '');

  -- THE FAST PATH, and the one that runs on a flaky connection: the attempt is
  -- already recorded, so hand back the row it made. No error, no second row,
  -- and the caller cannot tell the difference — which is the whole point.
  if v_token is not null then
    select id into v_check_in_id
    from public.check_ins
    where org_id = v_org_id and client_token = v_token;

    if v_check_in_id is not null then
      return v_check_in_id;
    end if;
  end if;

  -- The date is New York's, never the session's (2026-09-16). A blank hours field is "not recorded" (NULL),
  -- never 0. With a crew, crew_name is derived by check_ins_crew_name.
  begin
    insert into public.check_ins
      (org_id, work_order_id, schedule_block_id, crew_id, crew_name, check_in_date, hours, materials_used, blockers, client_token)
    values
      (v_org_id, p_work_order_id, p_schedule_block_id, p_crew_id, coalesce(nullif(btrim(p_crew_name), ''), '(crew)'),
       coalesce(p_check_in_date, (now() at time zone 'America/New_York')::date),
       p_hours, p_materials_used, p_blockers, v_token)
    returning id into v_check_in_id;
  exception when unique_violation then
    -- THE RACE THE SELECT ABOVE CANNOT CLOSE. Two requests from the same tap can
    -- both read "not there" and both try to insert; one wins, and the loser must
    -- still answer the roofer with the id that was written, not with an error.
    -- Re-read rather than recurse.
    select id into v_check_in_id
    from public.check_ins
    where org_id = v_org_id and client_token = v_token;

    if v_check_in_id is null then
      -- Not our index: something else is unique and genuinely conflicted. Do not
      -- swallow it — a defect that reports success is worse than one that raises.
      raise;
    end if;
  end;

  return v_check_in_id;
end;
$function$;

-- RULE 7, AND ITS MECHANISM, NOT JUST THE STATEMENT. A function created in
-- `public` is born holding PostgreSQL's built-in grant to PUBLIC. It appears in
-- proacl as the LEADING `=X/postgres` with no grantee name before the `=`; it is
-- NOT a grant to `anon`, so a revoke naming only `anon` removes a grant that was
-- never there, reports success, and leaves `anon` executing through its PUBLIC
-- membership. The `public` in this statement is the part that works.
-- The `authenticated` carve-out, answered FOR THIS FUNCTION rather than assumed:
-- every check-in the crew writes is this call, made as `authenticated`, so that
-- grant is the application's own path and revoking it would break the product.
revoke execute on function public.create_check_in(p_work_order_id uuid, p_crew_name text, p_schedule_block_id uuid, p_check_in_date date, p_hours numeric, p_materials_used text, p_blockers text, p_crew_id uuid, p_client_token text) from public, anon;
grant execute on function public.create_check_in(p_work_order_id uuid, p_crew_name text, p_schedule_block_id uuid, p_check_in_date date, p_hours numeric, p_materials_used text, p_blockers text, p_crew_id uuid, p_client_token text) to authenticated;

