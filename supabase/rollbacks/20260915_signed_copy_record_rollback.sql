-- ROLLBACK for 2026-09-15 signed_copy_record.
-- signatures_after_insert and sign_estimate_by_link restored verbatim from 20260915004736 (md5-verified;
-- prosrc md5 matched before applying). Signatures unchanged.
-- DATA LOSS: every signed_copy_records row (which copies were owed and what became of them).

drop function if exists public.record_signed_copy_outcome_by_link(text, text, text);
drop function if exists public.signed_copy_by_link(text);
drop function if exists public.record_signed_copy_outcome(uuid, text, text);
drop function if exists public.signed_copy_link_resolve(text);

create or replace function public.signatures_after_insert()
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

create or replace function public.sign_estimate_by_link(
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

revoke execute on function public.signatures_after_insert() from public, anon, authenticated;
revoke execute on function public.sign_estimate_by_link(text, text, text, text, text) from public;
grant execute on function public.sign_estimate_by_link(text, text, text, text, text) to anon, authenticated;

drop table if exists public.signed_copy_records;
