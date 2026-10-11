-- THE LEDGER WATCH, ON THE PATH INSTEAD OF BESIDE IT.
-- 2026-10-11, Track S. Design by Track X, accepted whole and implemented as
-- specified; every deviation below is a measurement, not a preference.
--
-- ═══ WHY ═══
-- On 2026-10-07 a migration applied during an agreed freeze and we learned 34
-- hours later from a message. Material Matrix described their own half exactly:
-- the notification was the entire control, and it sat outside the path. Track S
-- did the same thing the same night with the runbook's Rule One. BOTH WERE NOTES
-- AND NEITHER WAS A STEP (CLAUDE.md 38). This reads the ledger on a schedule, so
-- it needs nobody to send anything.
--
-- ═══ THE SQL SIDE HOLDS EXACTLY ONE COMPARISON, AND PERFORMS NO ATTRIBUTION ═══
-- max(version) against a stored watermark. That is all. It does NOT decide whose
-- migration a row is.
--
-- THE REASON IS LOAD-BEARING AND IS WRITTEN HERE RATHER THAN IN A DOC, because a
-- doc is not read by the person editing this function: ATTRIBUTION REQUIRES
-- READING THE FILESYSTEM — a row is OURS when a file with that version exists in
-- supabase/migrations/ or _archive_pre_baseline/ — AND SQL CANNOT SEE THE
-- FILESYSTEM. `created_by` looks like the answer and is not: 258 of 267 rows
-- carried one address, Material Matrix's wh_ rows included, because both tracks
-- apply under one account (measured by Track X, 2026-10-08).
--
-- SO THE TWO SIDES CANNOT CONTRADICT EACH OTHER, AND THAT PROPERTY IS THE POINT.
-- The Node monitor (scripts/pilot/migration-watch.mjs) attributes three ways and
-- can be wrong about whose row it is. This one only ever says a row APPEARED,
-- which is a fact it can establish alone. **The moment somebody teaches this
-- function to classify, that property is gone** — there would be two classifiers,
-- they would disagree eventually, and the disagreement would surface at 3 a.m.
-- in whichever one fired. Alerts say [UNATTRIBUTED] for this reason, and the
-- word is a statement about the INSTRUMENT, not about the row.
--
-- ═══ WHY `http` AND NOT `pg_net` ═══
-- Track X's reason, adopted: inside a background worker there is no request path
-- to block, so a synchronous call is fine, and pg_net would be an install for no
-- gain. `http` 1.6 is already installed (schema `extensions`); pg_net is
-- available and not installed, and stays that way.
--
-- ═══ THE TIMEOUT IS MANDATORY, AND THIS IS THE SAME STALL TWICE ═══
-- `http_set_curlopt('CURLOPT_TIMEOUT', …)` is set on every run. UNSET, libcurl
-- waits indefinitely and a hung endpoint PINS A BACKGROUND WORKER — which is the
-- stall that disqualified doing this from a trigger in the first place. A control
-- that can wedge the database it protects is worse than no control.
--
-- ═══ THE WATERMARK ADVANCES ONLY ON HTTP 2xx ═══
-- A failed POST must not lose the row. If delivery fails the watermark stays put,
-- the consecutive-failure count rises, and the NEXT run re-reports the same
-- version with that count in the body. An alerting path that forgets what it
-- could not deliver is indistinguishable from one with nothing to say.
--
-- ═══ THE SECRET IS READ BY NAME ═══
-- From vault.decrypted_secrets, keyed on name='migration_watch_webhook'. THE JOB
-- DEFINITION AND THIS FILE CONTAIN ONLY THE NAME. The row was created by Jacob
-- at 2026-10-11 00:36:04 EDT and this migration neither writes nor prints it.

begin;

-- ── 1 · THE WATERMARK ───────────────────────────────────────────────────────
-- Singleton, enforced by a one-row CHECK on a constant primary key rather than
-- by convention. A second row here would mean two watermarks and a silent race.
create table if not exists public.migration_watch_state (
  id                   boolean primary key default true check (id),
  watermark            text        not null,
  consecutive_failures integer     not null default 0,
  last_ok_at           timestamptz,
  last_attempt_at      timestamptz,
  updated_at           timestamptz not null default now()
);

comment on table public.migration_watch_state is
  'One row. The highest supabase_migrations.schema_migrations version already reported, plus the consecutive delivery-failure count. Advanced only on HTTP 2xx.';

-- RULE 8, AND THE HOUSE STANDARD MEASURED OVER 51 TABLES: authenticated gets
-- SELECT/INSERT/UPDATE/DELETE and anon nothing. THIS TABLE DEVIATES DELIBERATELY
-- AND NARROWER: nothing outside the database touches it — no src/ caller, no
-- PostgREST path, only the cron job running as its owner — so authenticated gets
-- NOTHING EITHER. The deviation is written here because rule 8 requires any
-- departure from the standard to be stated in the migration.
revoke all on table public.migration_watch_state from anon, authenticated;

-- Seed at the CURRENT max, so installing this does not immediately alert about
-- every migration ever applied. The first genuinely new row is the first alert.
insert into public.migration_watch_state (id, watermark)
select true, coalesce(max(version), '0') from supabase_migrations.schema_migrations
on conflict (id) do nothing;

-- ── 2 · THE TICK ────────────────────────────────────────────────────────────
create or replace function public.migration_watch_tick()
returns text
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_url        text;
  v_watermark  text;
  v_failures   integer;
  v_max        text;
  v_total      bigint;
  v_body       text;
  v_target     text;
  v_status     integer;
  v_alerting   boolean;
begin
  -- The secret, BY NAME. Never logged, never returned.
  select decrypted_secret into v_url
  from vault.decrypted_secrets where name = 'migration_watch_webhook';

  if v_url is null or btrim(v_url) = '' then
    -- No endpoint means no control. Say so loudly in the one place a human will
    -- look (cron.job_run_details) rather than returning a cheerful nothing.
    raise exception 'migration_watch: vault secret migration_watch_webhook is absent or empty — this monitor cannot deliver and is not a control';
  end if;

  select watermark, consecutive_failures into v_watermark, v_failures
  from public.migration_watch_state where id;

  -- THE ONE COMPARISON. No attribution — see the header.
  select max(version), count(*) into v_max, v_total from supabase_migrations.schema_migrations;

  v_alerting := v_max is not null and v_max > v_watermark;

  if v_alerting then
    v_target := rtrim(v_url, '/') || '/fail';
    v_body   := 'MIGRATION ' || v_max || ' [UNATTRIBUTED] ledger=' || v_total;
  else
    v_target := v_url;
    v_body   := 'quiet ledger=' || v_total || ' watermark=' || v_watermark;
  end if;

  if v_failures > 0 then
    v_body := v_body || ' consecutive_failures=' || v_failures;
  end if;

  -- MANDATORY. See the header: unset, a hung endpoint pins a worker.
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '10');
  perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT', '5');

  begin
    select status into v_status
    from extensions.http_post(v_target, v_body, 'text/plain');
  exception when others then
    v_status := null;   -- a transport failure is a delivery failure, not a crash
  end;

  if v_status between 200 and 299 then
    update public.migration_watch_state
       set watermark            = coalesce(v_max, watermark),   -- advance ONLY here
           consecutive_failures = 0,
           last_ok_at           = now(),
           last_attempt_at      = now(),
           updated_at           = now()
     where id;
    return case when v_alerting then 'alerted ' || v_max else 'quiet' end
           || ' http=' || v_status;
  end if;

  -- NOT 2xx: the watermark stays, so the next run re-reports the same version.
  update public.migration_watch_state
     set consecutive_failures = consecutive_failures + 1,
         last_attempt_at      = now(),
         updated_at           = now()
   where id;
  return 'DELIVERY FAILED http=' || coalesce(v_status::text, 'transport')
         || ' watermark held at ' || v_watermark
         || ' failures=' || (v_failures + 1);
end;
$function$;

-- RULE 7, WITH ITS CARVE-OUT TEST ANSWERED FOR THIS FUNCTION. Does anything
-- outside the database call it? NO — only the cron job below, which runs as its
-- owner. So `authenticated` is revoked too, the same answer and the same reason
-- as default_permissions_for_role and derive_catalog_price. `public` is the part
-- that removes PostgreSQL's built-in grant; `anon` is belt-and-braces.
revoke execute on function public.migration_watch_tick() from public, anon, authenticated;

-- ── 3 · THE SCHEDULE ────────────────────────────────────────────────────────
-- `* * * * *`. Minute granularity is the whole reason pg_cron was chosen over the
-- GitHub Actions cron, whose measured drift over 09-06..10-10 produced six alert
-- windows and a worst gap of 21.71h against an 8h threshold. A watch with a
-- one-minute cadence has no drift budget to spend.
--
-- THE JOB DEFINITION CONTAINS ONLY A FUNCTION CALL. No URL, no secret, no
-- comparison — all three live in the function, where this file can be committed
-- to a PUBLIC repository without leaking anything. cron.job is readable by the
-- postgres role and a command string is not a place to put a credential.
--
-- Guarded rather than `IF EXISTS`-suppressed, so re-running this file reports
-- which of the two things happened (rule 2's shape applied to a scheduler).
do $$
declare v_jobid bigint;
begin
  if exists (select 1 from cron.job where jobname = 'migration-watch') then
    raise notice 'ALREADY SCHEDULED: migration-watch (left alone, not re-created)';
  else
    select cron.schedule('migration-watch', '* * * * *', 'select public.migration_watch_tick();')
      into v_jobid;
    raise notice 'SCHEDULED: migration-watch as jobid %', v_jobid;
  end if;
end $$;

commit;
