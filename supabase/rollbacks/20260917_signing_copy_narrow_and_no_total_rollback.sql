-- ROLLBACK for 20260917 signing_copy_narrow_and_no_total. Restores both bodies as they were (the whole-row copy
-- payload and link creation with no total check). Signatures and grants are unchanged by the migration.
CREATE OR REPLACE FUNCTION public.signed_copy_by_link(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

CREATE OR REPLACE FUNCTION public.create_estimate_sign_link(p_estimate_id uuid, p_valid_days integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
