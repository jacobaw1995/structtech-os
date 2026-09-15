-- REMOTE SIGNING — THE SPINE. Track S · 2026-09-14.
-- Rollback: supabase/rollbacks/20260914_remote_signing_spine_rollback.sql
--
-- THE PROPERTY (controller): A CUSTOMER WHO IS NOT A USER OF THIS SYSTEM MUST BE ABLE TO OPEN ONE
-- DOCUMENT, SIGN IT, AND HAVE THAT SIGNATURE LAND ON THE SAME RECORD AN IN-PERSON SIGNATURE WOULD —
-- AND THE LINK MUST GRANT NOTHING ELSE.
--
-- WHAT ALREADY EXISTED, MEASURED 2026-09-14 — half built, and the half that existed was the wrong half:
--   · 4 estimates (3 signed, 1 void), 4 signatures (one per estimate — including the void one),
--     0 work_order_agreements.
--   · signatures.sign_token: TEXT, UNIQUE, NULL on all 4 rows, referenced by 0 functions. It is a
--     PLAINTEXT token on the SIGNATURE row — a row that only exists AFTER signing, so a pre-signing
--     capability can never live there, and a stored plaintext token is a sent token.
--   · work_order_agreements.sign_token_hash: a HASH, on the DOCUMENT. That is the right shape, and it
--     is the one kept: the token belongs to the thing being signed and only its hash is stored.
--     signatures.sign_token is DROPPED, not kept beside it.
--   · sign_estimate (in person): checks status = 'presented' WITHOUT a row lock and has no uniqueness,
--     so two concurrent signatures on one estimate were possible; a signature row had no immutability;
--     "member insert own signatures" let a member insert a signature on an estimate never presented.
--
-- THE SHAPE
--   estimate_sign_links   one row per link issued: token_hash (sha256 of the sent token — the token
--                         itself is returned once and never stored), document_hash (what was sent),
--                         expires_at, revoked_at, used_at, signature_id.
--   signatures.sign_link_id   which signatures arrived by link (NULL = in person). The SAME row, the
--                         SAME estimate status change, either way.
--   Table triggers (condition 6): one signature per estimate, the estimate row locked while signing,
--   status must be 'presented', a referenced link must be live, for this estimate, and for the
--   document as it stands; the estimate is marked signed and the link consumed by the insert itself;
--   a signature is immutable except for attaching its PDF.
--   signing_link_view(token) / sign_estimate_by_link(token, …)   the ONLY anon-callable surface. They
--   take a token and nothing else — no estimate id, no org id, no list.
--
-- STATES A TOKEN HOLDER SEES: ready · expired · already_signed · document_changed · signed.
-- AN UNKNOWN, MALFORMED OR REVOKED TOKEN, OR ONE WHOSE ESTIMATE IS NO LONGER PRESENTED, answers the
-- single identical body {"state":"unavailable"} — no business name, no dates, no ids (condition 5).

-- ---------------------------------------------------------------------------------------------
-- 1. The link
-- ---------------------------------------------------------------------------------------------
create table public.estimate_sign_links (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  estimate_id uuid not null references public.estimates(id) on delete cascade,
  token_hash text not null,
  document_hash text not null,
  created_by uuid null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz null,
  revoked_by uuid null,
  used_at timestamptz null,
  signature_id uuid null,
  constraint estimate_sign_links_token_hash_key unique (token_hash),
  constraint estimate_sign_links_token_hash_shape check (token_hash ~ '^[0-9a-f]{64}$'),
  constraint estimate_sign_links_expires_after_created check (expires_at > created_at),
  constraint estimate_sign_links_used_together check ((used_at is null) = (signature_id is null)),
  constraint estimate_sign_links_not_revoked_and_used check (revoked_at is null or used_at is null)
);

comment on table public.estimate_sign_links is
  'A capability to sign ONE estimate. Only the sha256 of the sent token is stored; the token is returned
   once by create_estimate_sign_link and never again. document_hash is the estimate as sent: if the
   estimate changes afterwards the link answers document_changed and cannot sign.';

alter table public.estimate_sign_links enable row level security;
revoke all on table public.estimate_sign_links from anon;
revoke insert, update, delete, truncate, references, trigger, maintain on table public.estimate_sign_links from authenticated;
grant select on table public.estimate_sign_links to authenticated;
create policy "member read own estimate_sign_links" on public.estimate_sign_links
  for select to authenticated
  using (org_id in (select my_org_ids()) and has_capability(org_id, 'view_estimates'));
create policy "no dollars in the field - estimate_sign_links" on public.estimate_sign_links
  as restrictive for select to authenticated using (public.can_view_financials(org_id));

create function public.estimate_sign_links_immutable()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
begin
  if (new.id, new.org_id, new.estimate_id, new.token_hash, new.document_hash, new.created_by, new.created_at, new.expires_at)
     is distinct from
     (old.id, old.org_id, old.estimate_id, old.token_hash, old.document_hash, old.created_by, old.created_at, old.expires_at) then
    raise exception 'a signing link cannot be altered — revoke it and send a new one';
  end if;
  if old.used_at is not null and (new.used_at, new.signature_id) is distinct from (old.used_at, old.signature_id) then
    raise exception 'a signing link that has been used cannot be changed';
  end if;
  if old.revoked_at is not null and (new.revoked_at, new.revoked_by) is distinct from (old.revoked_at, old.revoked_by) then
    raise exception 'a revoked signing link stays revoked';
  end if;
  return new;
end;
$function$;

create trigger estimate_sign_links_immutable
  before update on public.estimate_sign_links
  for each row execute function public.estimate_sign_links_immutable();

-- ---------------------------------------------------------------------------------------------
-- 2. The signature record: one per estimate, immutable, the plaintext token column retired
-- ---------------------------------------------------------------------------------------------
alter table public.signatures drop constraint signatures_sign_token_key;
alter table public.signatures drop column sign_token;
-- Both cross-references are NO ACTION, deliberately: SET NULL would null a used link's signature_id
-- (breaking used_together) or change a signature's sign_link_id (refused by signatures_immutable).
-- Deleting an estimate cascades to both rows in one statement, and NO ACTION is checked at its end.
alter table public.signatures add column sign_link_id uuid null references public.estimate_sign_links(id);
alter table public.estimate_sign_links
  add constraint estimate_sign_links_signature_id_fkey foreign key (signature_id) references public.signatures(id);
create unique index signatures_one_per_estimate on public.signatures (estimate_id);

-- What the signer sees — and what document_hash is taken over. No phone, no email, no ids.
create function public.estimate_signing_document(p_estimate_id uuid)
returns jsonb language sql stable security definer set search_path to 'public'
as $function$
  select jsonb_build_object(
    'business', o.name,
    'estimate_number', e.estimate_number,
    'estimate_date', e.estimate_date,
    'valid_until', e.valid_until,
    'contact_name', e.contact_name,
    'site_address', e.site_address,
    'notes_terms', e.notes_terms,
    'subtotal', e.subtotal,
    'tax_rate', e.tax_rate,
    'tax_amount', e.tax_amount,
    'total', e.presented_total,
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
               'description', l.description, 'quantity', l.quantity, 'unit', l.unit,
               'unit_price', l.unit_price, 'line_total', l.line_total)
             order by l.sort_order, l.id)
      from public.estimate_line_items l where l.estimate_id = e.id), '[]'::jsonb))
  from public.estimates e
  join public.organizations o on o.id = e.org_id
  where e.id = p_estimate_id
$function$;

create function public.signatures_guard_insert()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
declare v_status text; v_org uuid; v_link public.estimate_sign_links;
begin
  -- The estimate row is LOCKED: a concurrent second signature waits here, then sees 'signed'.
  select status, org_id into v_status, v_org from public.estimates where id = new.estimate_id for update;

  if v_status is null then
    raise exception 'estimate % not found', new.estimate_id;
  elsif v_status = 'signed' or exists (select 1 from public.signatures s where s.estimate_id = new.estimate_id) then
    raise exception 'estimate % is already signed — a second signature is not recorded', new.estimate_id;
  elsif v_status <> 'presented' then
    raise exception 'estimate % must be presented before it can be signed (current status: %)', new.estimate_id, v_status;
  end if;

  new.org_id := v_org;          -- a signature belongs to its estimate's tenant, whatever a writer sent
  new.signed_at := now();       -- and happened now; a writer cannot backdate it

  if new.sign_link_id is not null then
    select * into v_link from public.estimate_sign_links where id = new.sign_link_id for update;
    if v_link.id is null or v_link.estimate_id <> new.estimate_id
       or v_link.revoked_at is not null or v_link.used_at is not null or v_link.expires_at <= now() then
      raise exception 'that signing link is not valid for this estimate';
    end if;
    if v_link.document_hash <> encode(sha256(convert_to(public.estimate_signing_document(new.estimate_id)::text, 'UTF8')), 'hex') then
      raise exception 'the estimate has changed since the signing link was sent — send a new link';
    end if;
  end if;
  return new;
end;
$function$;

create trigger signatures_guard_insert
  before insert on public.signatures
  for each row execute function public.signatures_guard_insert();

create function public.signatures_after_insert()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
begin
  update public.estimates set status = 'signed', signed_at = new.signed_at, updated_at = now()
  where id = new.estimate_id;
  if new.sign_link_id is not null then
    update public.estimate_sign_links set used_at = now(), signature_id = new.id where id = new.sign_link_id;
  end if;
  return new;
end;
$function$;

create trigger signatures_after_insert
  after insert on public.signatures
  for each row execute function public.signatures_after_insert();

create function public.signatures_immutable()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
begin
  if (new.id, new.org_id, new.estimate_id, new.signer_name, new.signer_role, new.signature_data,
      new.signed_at, new.created_at, new.sign_link_id)
     is distinct from
     (old.id, old.org_id, old.estimate_id, old.signer_name, old.signer_role, old.signature_data,
      old.signed_at, old.created_at, old.sign_link_id) then
    raise exception 'a signature cannot be changed after signing — only its PDF can be attached';
  end if;
  return new;
end;
$function$;

create trigger signatures_immutable
  before update on public.signatures
  for each row execute function public.signatures_immutable();

-- ---------------------------------------------------------------------------------------------
-- 3. Issuing and revoking (members)
-- ---------------------------------------------------------------------------------------------
create function public.create_estimate_sign_link(p_estimate_id uuid, p_valid_days integer)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_org uuid; v_status text; v_token text; v_id uuid; v_expires timestamptz; v_revoked int;
begin
  select org_id, status into v_org, v_status from public.estimates where id = p_estimate_id;
  if v_org is null or v_org not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;
  if not coalesce(public.has_capability(v_org, 'create_estimates'), false) then
    raise exception 'your role cannot send estimates for signature in this workspace';
  end if;
  if not coalesce(public.can_view_financials(v_org), false) then
    raise exception 'a signing link shows the priced estimate, and your role cannot view financials';
  end if;
  if exists (select 1 from public.signatures where estimate_id = p_estimate_id) then
    raise exception 'estimate % is already signed', p_estimate_id;
  end if;
  if v_status is distinct from 'presented' then
    raise exception 'estimate % must be presented before a signing link can be sent (current status: %)', p_estimate_id, v_status;
  end if;
  if p_valid_days is null or p_valid_days < 1 or p_valid_days > 30 then
    raise exception 'choose how many days the link stays valid, from 1 to 30';
  end if;

  -- One live link per estimate: sending a new one revokes the old ones, as a recorded state.
  update public.estimate_sign_links set revoked_at = now(), revoked_by = auth.uid()
  where estimate_id = p_estimate_id and revoked_at is null and used_at is null;
  get diagnostics v_revoked = row_count;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_expires := now() + make_interval(days => p_valid_days);

  insert into public.estimate_sign_links (org_id, estimate_id, token_hash, document_hash, created_by, expires_at)
  values (v_org, p_estimate_id,
          encode(sha256(convert_to(v_token, 'UTF8')), 'hex'),
          encode(sha256(convert_to(public.estimate_signing_document(p_estimate_id)::text, 'UTF8')), 'hex'),
          auth.uid(), v_expires)
  returning id into v_id;

  -- The token leaves the database once, here. Only its hash stays.
  return jsonb_build_object('link_id', v_id, 'token', v_token, 'expires_at', v_expires, 'revoked_previous', v_revoked);
end;
$function$;

create function public.revoke_estimate_sign_link(p_link_id uuid)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare v_org uuid; v_used timestamptz; v_revoked timestamptz;
begin
  select org_id, used_at, revoked_at into v_org, v_used, v_revoked from public.estimate_sign_links where id = p_link_id;
  if v_org is null or v_org not in (select my_org_ids()) then
    raise exception 'signing link not found or not accessible: %', p_link_id;
  end if;
  if not coalesce(public.has_capability(v_org, 'create_estimates'), false) then
    raise exception 'your role cannot manage signing links in this workspace';
  end if;
  if v_used is not null then
    raise exception 'that link was already used to sign — it cannot be revoked';
  end if;
  if v_revoked is null then
    update public.estimate_sign_links set revoked_at = now(), revoked_by = auth.uid() where id = p_link_id;
  end if;
end;
$function$;

-- ---------------------------------------------------------------------------------------------
-- 4. The token, resolved in exactly one place
-- ---------------------------------------------------------------------------------------------
create function public.signing_link_resolve(p_token text)
returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare v_link public.estimate_sign_links; v_status text; v_business text; v_signed_at timestamptz;
        v_doc jsonb; v_hash text;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('state', 'unavailable');
  end if;
  select * into v_link from public.estimate_sign_links
  where token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex');
  if v_link.id is null or v_link.revoked_at is not null then
    return jsonb_build_object('state', 'unavailable');
  end if;

  select e.status, o.name into v_status, v_business
  from public.estimates e join public.organizations o on o.id = e.org_id
  where e.id = v_link.estimate_id;
  select s.signed_at into v_signed_at from public.signatures s where s.estimate_id = v_link.estimate_id;

  if v_signed_at is not null or v_status = 'signed' then
    return jsonb_build_object('state', 'already_signed', 'business', v_business, 'signed_at', v_signed_at);
  end if;
  if v_status is distinct from 'presented' then
    return jsonb_build_object('state', 'unavailable');
  end if;
  if v_link.expires_at <= now() then
    return jsonb_build_object('state', 'expired', 'business', v_business, 'expired_at', v_link.expires_at);
  end if;

  v_doc := public.estimate_signing_document(v_link.estimate_id);
  v_hash := encode(sha256(convert_to(v_doc::text, 'UTF8')), 'hex');
  if v_hash <> v_link.document_hash then
    return jsonb_build_object('state', 'document_changed', 'business', v_business);
  end if;

  return jsonb_build_object('state', 'ready', 'business', v_business, 'expires_at', v_link.expires_at,
                            'document', v_doc, 'document_version', v_hash,
                            '_link_id', v_link.id, '_estimate_id', v_link.estimate_id);
end;
$function$;

-- ---------------------------------------------------------------------------------------------
-- 5. The public surface — a token in, one document's state out
-- ---------------------------------------------------------------------------------------------
create function public.signing_link_view(p_token text)
returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
begin
  return public.signing_link_resolve(p_token) - '_link_id' - '_estimate_id';
end;
$function$;

create function public.sign_estimate_by_link(
  p_token text, p_document_version text, p_signer_name text, p_signer_role text, p_signature_data text
)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare r jsonb; v_signed_at timestamptz;
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
    returning signed_at into v_signed_at;
  exception when others then
    -- Something landed between resolving and inserting (a concurrent signature, a revocation, the
    -- expiry, an edit). Answer with the state it produced — never a second signature, never a raw error.
    r := public.signing_link_resolve(p_token);
    if r ->> 'state' <> 'ready' then
      return r - '_link_id' - '_estimate_id';
    end if;
    raise;
  end;

  return jsonb_build_object('state', 'signed', 'business', r ->> 'business', 'signed_at', v_signed_at);
end;
$function$;

-- ---------------------------------------------------------------------------------------------
-- 6. Grants
-- ---------------------------------------------------------------------------------------------
revoke execute on function public.estimate_sign_links_immutable() from public, anon, authenticated;
revoke execute on function public.signatures_guard_insert() from public, anon, authenticated;
revoke execute on function public.signatures_after_insert() from public, anon, authenticated;
revoke execute on function public.signatures_immutable() from public, anon, authenticated;
revoke execute on function public.estimate_signing_document(uuid) from public, anon, authenticated;
revoke execute on function public.signing_link_resolve(text) from public, anon, authenticated;
revoke execute on function public.create_estimate_sign_link(uuid, integer) from public, anon;
revoke execute on function public.revoke_estimate_sign_link(uuid) from public, anon;
-- THE DELIBERATE ANON SURFACE (rule 13's answer: what would have to change for these to grant more is
-- a change to their bodies, which take a token and nothing else):
revoke execute on function public.signing_link_view(text) from public;
revoke execute on function public.sign_estimate_by_link(text, text, text, text, text) from public;
grant execute on function public.signing_link_view(text) to anon, authenticated;
grant execute on function public.sign_estimate_by_link(text, text, text, text, text) to anon, authenticated;

-- Rule 3: never trust the success response.
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'signatures' and column_name = 'sign_token')
    then raise exception 'signatures.sign_token still present'; end if;
  if not exists (select 1 from pg_indexes where indexname = 'signatures_one_per_estimate')
    then raise exception 'one-signature-per-estimate index missing'; end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.signatures'::regclass and not tgisinternal) <> 3
    then raise exception 'signatures triggers not attached'; end if;
  if has_table_privilege('anon', 'public.estimate_sign_links', 'SELECT')
    then raise exception 'anon can read estimate_sign_links'; end if;
end $$;