-- ============================================================================
-- X-W1.19 · field_events — WHAT HAPPENED IN THE FIELD, DURABLY. PROPOSAL FOR TRACK S.
-- NOT APPLIED BY TRACK X. Proved on a local fixture:
--   bash scripts/pilot/field-events-fixture/run.sh   (loads THIS file verbatim)
-- ============================================================================
-- WHY. Pilot 2026-10-07. Runtime logs on this Vercel plan last one hour, and
-- auth.audit_log_entries holds 0 rows, so on the day after the pilot nobody could
-- say whether a crew member opened a work order, how long a job page took to become
-- usable, which pages rendered and never became usable, which files were opened, or
-- how many times anyone signed in. This table is the durable record of those facts.
--
-- NO DOLLARS AND NO CUSTOMER PERSONAL DATA — BY TYPE, NOT BY DISCIPLINE. There is no
-- column that can hold free text. Every value is a uuid, a lower-case code that
-- matches ^[a-z_]{1,40}$, a hex reference, a timestamp or a small integer. A price,
-- a name, an address or a filename cannot be stored because there is nowhere for it
-- to go — a file is referred to by a 16-hex hash of its path, since filenames arrive
-- from phones and carry whatever the customer or crew typed. Anyone later adding a
-- `text` or `jsonb` column here is removing the control, in a diff that shows it.
--
-- APPEND-ONLY. authenticated gets SELECT only (rule 8 house standard narrowed on
-- purpose: no INSERT/UPDATE/DELETE, no TRUNCATE/REFERENCES/TRIGGER/MAINTAIN); anon
-- gets nothing. The only write path is record_field_event(), which never updates
-- or deletes.
--
-- WHO READS IT. Office and managers (can_view_master_work_order), in their own orgs.
-- A crew member does not read the team's telemetry.
--
-- THE WRITE NEVER TRUSTS THE CALLER FOR IDENTITY OR TENANT. actor_id is auth.uid();
-- org_id must be one of my_org_ids(); a work_order_id must belong to that org. A
-- caller who is not a member of the org writes nothing and is told so.

create table public.field_events (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null references public.organizations(id),
  actor_id        uuid not null,
  event           text not null check (event in (
                    'signed_in', 'work_order_opened', 'packet_opened', 'page_ready',
                    'file_opened', 'file_added', 'file_removed',
                    'check_in_saved', 'check_in_failed')),
  work_order_id   uuid null,
  subject_ref     text null check (subject_ref ~ '^([0-9a-f]{16}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$'),
  outcome         text null check (outcome ~ '^[a-z_]{1,40}$'),
  duration_ms     integer null check (duration_ms between 0 and 600000),
  client_sent_at  timestamptz null,
  occurred_at     timestamptz not null default now()
);
-- work_order_id is deliberately NOT a foreign key: a history row must survive the
-- work order being deleted, and ON DELETE SET NULL would be an UPDATE of history.

create index field_events_org_time on public.field_events (org_id, occurred_at);
create index field_events_work_order on public.field_events (work_order_id, occurred_at);

alter table public.field_events enable row level security;
revoke all on table public.field_events from anon;
revoke insert, update, delete, truncate, references, trigger, maintain on table public.field_events from authenticated;
grant select on table public.field_events to authenticated;

create policy "office reads field events" on public.field_events
  for select to authenticated
  using (org_id in (select my_org_ids()) and public.can_view_master_work_order(org_id));

create function public.record_field_event(
  p_org_id uuid,
  p_event text,
  p_work_order_id uuid default null,
  p_subject_ref text default null,
  p_outcome text default null,
  p_duration_ms integer default null,
  p_client_sent_at timestamptz default null
) returns integer
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_actor uuid := auth.uid();
  v_rows integer := 0;
begin
  if v_actor is null then
    raise exception 'not signed in';
  end if;

  -- signed_in is recorded once per org the person belongs to: a sign-in is not
  -- about one workspace, and the office of each should see it.
  if p_event = 'signed_in' then
    insert into public.field_events (org_id, actor_id, event, client_sent_at)
    select o, v_actor, 'signed_in', p_client_sent_at from public.my_org_ids() o;
    get diagnostics v_rows = row_count;
    return v_rows;
  end if;

  if not coalesce(p_org_id in (select public.my_org_ids()), false) then
    raise exception 'not a member of that workspace';
  end if;
  if p_work_order_id is not null and not exists (
    select 1 from public.work_orders w where w.id = p_work_order_id and w.org_id = p_org_id
  ) then
    raise exception 'that work order is not in that workspace';
  end if;

  insert into public.field_events (org_id, actor_id, event, work_order_id, subject_ref, outcome, duration_ms, client_sent_at)
  values (p_org_id, v_actor, p_event, p_work_order_id, p_subject_ref, p_outcome, p_duration_ms, p_client_sent_at);
  return 1;
end;
$function$;

-- Rule 7: closing revoke, and the EXECUTE the application needs.
revoke execute on function public.record_field_event(uuid, text, uuid, text, text, integer, timestamptz) from public, anon;
grant execute on function public.record_field_event(uuid, text, uuid, text, text, integer, timestamptz) to authenticated;
