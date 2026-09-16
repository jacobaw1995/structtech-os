-- THE SIGNED COPY — A RECORD, NOT AN OUTBOX. Track S · 2026-09-15.
-- Rollback: supabase/rollbacks/20260915_signed_copy_record_rollback.sql
--
-- CONTROLLER RULING on supabase/proposals/20260914_x_w1_14_signed_copy_outbox.md: BUILD THE RECORD, NOT
-- THE OUTBOX. Record that a copy was owed and whether it left. Four signatures do not justify retry
-- machinery. A missing state is not a wrong value; the fix is a state.
--
-- WHAT X NEEDED (read from the proposal, not guessed):
--   (1) "a copy is owed" written in the SAME transaction as the signature, on BOTH paths;
--   (2) the signature id returned from sign_estimate_by_link, so a send can be keyed to it;
--   (3) a way to load the signed document outside a member session, because the remote caller is anon.
-- WHAT IS DELIBERATELY NOT BUILT: a drain, a retry counter policy, a cron, a queue. `attempts` counts
-- what happened; nothing reads it to act.
--
-- BEFORE-MEASUREMENT (live, 2026-09-15): 4 signatures (all in person, 2026-07-22 .. 2026-07-31), 0 signing
-- links, 0 records of any copy. Whether a copy of any of those 4 ever left is UNANSWERABLE — nothing
-- recorded it — so they are backfilled as `predates_record`, not as `owed` and not as `sent`.
--
-- THE STATES: owed (written with the signature) · sent · no_email · not_configured · rejected ·
-- unavailable · render_failed (X's six outcomes, verbatim from src/lib/estimating/signed-copy.ts) ·
-- predates_record (the backfill). `sent_at` is set on the first `sent` and never cleared.

create table public.signed_copy_records (
  signature_id uuid primary key references public.signatures(id) on delete cascade,
  org_id uuid not null references public.organizations(id),
  estimate_id uuid not null references public.estimates(id) on delete cascade,
  owed_at timestamptz not null default now(),
  state text not null,
  attempts integer not null default 0,
  last_attempt_at timestamptz null,
  last_attempt_via text null,
  sent_at timestamptz null,
  provider_message_id text null,
  constraint signed_copy_records_state_valid check (state in
    ('owed', 'sent', 'no_email', 'not_configured', 'rejected', 'unavailable', 'render_failed', 'predates_record')),
  constraint signed_copy_records_via_valid check (last_attempt_via is null or last_attempt_via in ('member', 'link')),
  constraint signed_copy_records_attempt_consistent check ((attempts = 0) = (last_attempt_at is null)),
  constraint signed_copy_records_sent_consistent check (state <> 'sent' or sent_at is not null)
);

comment on table public.signed_copy_records is
  'One row per signature: a signed copy was owed, and what became of it. Written by the signatures insert
   trigger on BOTH signing paths, in the signature''s transaction. A record, not an outbox — nothing drains it.';

alter table public.signed_copy_records enable row level security;
revoke all on table public.signed_copy_records from anon;
revoke insert, update, delete, truncate, references, trigger, maintain on table public.signed_copy_records from authenticated;
grant select on table public.signed_copy_records to authenticated;
create policy "member read own signed_copy_records" on public.signed_copy_records
  for select to authenticated
  using (org_id in (select my_org_ids()) and has_capability(org_id, 'view_estimates'));
create policy "no dollars in the field - signed_copy_records" on public.signed_copy_records
  as restrictive for select to authenticated using (public.can_view_financials(org_id));

insert into public.signed_copy_records (signature_id, org_id, estimate_id, owed_at, state)
select s.id, s.org_id, s.estimate_id, s.signed_at, 'predates_record' from public.signatures s;

-- (1) Owed, in the signature's own transaction, on every path that creates a signature.
create or replace function public.signatures_after_insert()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
begin
  update public.estimates set status = 'signed', signed_at = new.signed_at, updated_at = now()
  where id = new.estimate_id;
  if new.sign_link_id is not null then
    update public.estimate_sign_links set used_at = now(), signature_id = new.id where id = new.sign_link_id;
  end if;
  insert into public.signed_copy_records (signature_id, org_id, estimate_id, owed_at, state)
  values (new.id, new.org_id, new.estimate_id, new.signed_at, 'owed');
  return new;
end;
$function$;

-- (2) The signature id comes back from the remote path.
create or replace function public.sign_estimate_by_link(
  p_token text, p_document_version text, p_signer_name text, p_signer_role text, p_signature_data text
)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare r jsonb; v_signed_at timestamptz; v_signature_id uuid;
begin
  r := public.signing_link_resolve(p_token);
  if r ->> 'state' <> 'ready' then
    return r - '_link_id' - '_estimate_id';
  end if;
  if p_document_version is distinct from r ->> 'document_version' then
    return jsonb_build_object('state', 'document_changed', 'business', r ->> 'business');
  end if;
  if nullif(btrim(coalesce(p_signer_name, '')), '') is null then
    raise exception 'enter the name of the person signing';
  end if;
  if nullif(btrim(coalesce(p_signer_role, '')), '') is null then
    raise exception 'say who is signing — for example, Homeowner';
  end if;
  if nullif(btrim(coalesce(p_signature_data, '')), '') is null then
    raise exception 'draw a signature before signing';
  end if;

  begin
    insert into public.signatures (org_id, estimate_id, signer_name, signer_role, signature_data, sign_link_id)
    select e.org_id, e.id, btrim(p_signer_name), btrim(p_signer_role), p_signature_data, (r ->> '_link_id')::uuid
    from public.estimates e where e.id = (r ->> '_estimate_id')::uuid
    returning id, signed_at into v_signature_id, v_signed_at;
  exception when others then
    r := public.signing_link_resolve(p_token);
    if r ->> 'state' <> 'ready' then
      return r - '_link_id' - '_estimate_id';
    end if;
    raise;
  end;

  return jsonb_build_object('state', 'signed', 'business', r ->> 'business', 'signed_at', v_signed_at,
                            'signature_id', v_signature_id);
end;
$function$;

-- The token, resolved for the COPY in exactly one place. A token authorises loading its one signed
-- document for the copy only while: the link was USED to sign (not revoked, not merely issued), the copy
-- has not been recorded `sent`, and the signature is under 24 hours old (Resend's idempotency window, per
-- X's proposal — a retry after that could deliver twice). Everything else answers the single identical
-- {"state":"unavailable"}, so a probe cannot tell unknown from revoked from expired from sent.
create function public.signed_copy_link_resolve(p_token text)
returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare v_link public.estimate_sign_links; v_rec public.signed_copy_records; v_signed_at timestamptz;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('state', 'unavailable');
  end if;
  select * into v_link from public.estimate_sign_links
  where token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex');
  if v_link.id is null or v_link.used_at is null or v_link.signature_id is null then
    return jsonb_build_object('state', 'unavailable');
  end if;
  select * into v_rec from public.signed_copy_records where signature_id = v_link.signature_id;
  select signed_at into v_signed_at from public.signatures where id = v_link.signature_id;
  if v_rec.signature_id is null or v_rec.state = 'sent' or v_signed_at < now() - interval '24 hours' then
    return jsonb_build_object('state', 'unavailable');
  end if;
  return jsonb_build_object('state', 'ready', '_signature_id', v_link.signature_id, '_estimate_id', v_link.estimate_id);
end;
$function$;

-- (3) The signed document, for the copy, outside a member session.
create function public.signed_copy_by_link(p_token text)
returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare r jsonb; v_sig uuid; v_est uuid;
begin
  r := public.signed_copy_link_resolve(p_token);
  if r ->> 'state' <> 'ready' then
    return r;
  end if;
  v_sig := (r ->> '_signature_id')::uuid;
  v_est := (r ->> '_estimate_id')::uuid;
  return (
    select jsonb_build_object(
      'state', 'ready',
      'signature_id', v_sig,
      'copy_state', (select c.state from public.signed_copy_records c where c.signature_id = v_sig),
      'to', e.email,
      'org_name', o.name,
      'estimating_config', (select tm.config from public.tenant_modules tm
                             where tm.org_id = e.org_id and tm.module_key = 'estimating' limit 1),
      'estimate', to_jsonb(e) - 'deal_id',
      'line_items', coalesce((select jsonb_agg(to_jsonb(l) order by l.sort_order, l.id)
                              from public.estimate_line_items l where l.estimate_id = e.id), '[]'::jsonb),
      'signature', (select to_jsonb(s) - 'sign_link_id' from public.signatures s where s.id = v_sig))
    from public.estimates e join public.organizations o on o.id = e.org_id
    where e.id = v_est);
end;
$function$;

-- What became of the copy — a member recording it.
create function public.record_signed_copy_outcome(p_signature_id uuid, p_state text, p_provider_message_id text default null)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_org uuid;
begin
  select org_id into v_org from public.signed_copy_records where signature_id = p_signature_id;
  if v_org is null or v_org not in (select my_org_ids()) then
    raise exception 'signed copy record not found or not accessible: %', p_signature_id;
  end if;
  if not coalesce(public.has_capability(v_org, 'view_estimates'), false)
     or not coalesce(public.can_view_financials(v_org), false) then
    raise exception 'your role cannot send the signed estimate in this workspace';
  end if;
  if p_state is null or p_state not in ('sent', 'no_email', 'not_configured', 'rejected', 'unavailable', 'render_failed') then
    raise exception '"%" is not an outcome of sending a signed copy', coalesce(p_state, 'nothing');
  end if;
  -- Each call is an attempt that happened — a real event, not a re-send of a value (rule 10).
  update public.signed_copy_records
     set state = p_state,
         attempts = attempts + 1,
         last_attempt_at = now(),
         last_attempt_via = 'member',
         sent_at = case when p_state = 'sent' then coalesce(sent_at, now()) else sent_at end,
         provider_message_id = coalesce(p_provider_message_id, provider_message_id)
   where signature_id = p_signature_id;
  return (select to_jsonb(c) - 'org_id' from public.signed_copy_records c where c.signature_id = p_signature_id);
end;
$function$;

-- What became of the copy — the remote path recording it, under the same gate as the load.
create function public.record_signed_copy_outcome_by_link(p_token text, p_state text, p_provider_message_id text default null)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare r jsonb; v_sig uuid;
begin
  r := public.signed_copy_link_resolve(p_token);
  if r ->> 'state' <> 'ready' then
    return r;
  end if;
  if p_state is null or p_state not in ('sent', 'no_email', 'not_configured', 'rejected', 'unavailable', 'render_failed') then
    raise exception '"%" is not an outcome of sending a signed copy', coalesce(p_state, 'nothing');
  end if;
  v_sig := (r ->> '_signature_id')::uuid;
  update public.signed_copy_records
     set state = p_state,
         attempts = attempts + 1,
         last_attempt_at = now(),
         last_attempt_via = 'link',
         sent_at = case when p_state = 'sent' then coalesce(sent_at, now()) else sent_at end,
         provider_message_id = coalesce(p_provider_message_id, provider_message_id)
   where signature_id = v_sig;
  return jsonb_build_object('state', 'recorded', 'copy_state', p_state);
end;
$function$;

revoke execute on function public.signatures_after_insert() from public, anon, authenticated;
revoke execute on function public.signed_copy_link_resolve(text) from public, anon, authenticated;
revoke execute on function public.record_signed_copy_outcome(uuid, text, text) from public, anon;
revoke execute on function public.sign_estimate_by_link(text, text, text, text, text) from public;
grant execute on function public.sign_estimate_by_link(text, text, text, text, text) to anon, authenticated;
-- THE DELIBERATE ANON SURFACE, extended by two token-in functions under the gate above.
revoke execute on function public.signed_copy_by_link(text) from public;
revoke execute on function public.record_signed_copy_outcome_by_link(text, text, text) from public;
grant execute on function public.signed_copy_by_link(text) to anon, authenticated;
grant execute on function public.record_signed_copy_outcome_by_link(text, text, text) to anon, authenticated;

do $$
begin
  if (select count(*) from public.signed_copy_records) <> (select count(*) from public.signatures) then
    raise exception 'a signature has no signed copy record';
  end if;
  if has_table_privilege('anon', 'public.signed_copy_records', 'SELECT')
     or has_table_privilege('authenticated', 'public.signed_copy_records', 'INSERT')
     or has_table_privilege('authenticated', 'public.signed_copy_records', 'TRUNCATE') then
    raise exception 'signed_copy_records grants do not match the house standard';
  end if;
end $$;