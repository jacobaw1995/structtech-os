-- THE SIGNING TOKEN GRANTS ONLY THE COPY, AND NO ESTIMATE IS SENT FOR SIGNATURE WITHOUT A PRICE.
-- Track S · 2026-09-17. Controller rulings 1b and 1c. Rollback: supabase/rollbacks/20260917_signing_copy_narrow_and_no_total_rollback.sql
--
-- (1b) THE STATED PROPERTY WAS "THE LINK GRANTS NOTHING ELSE" AND IT WAS NOT TRUE. Found by Track U. For up to
-- 24 hours after signing, until the copy is sent, the token opened signed_copy_by_link(), which returned the
-- WHOLE estimates row and line rows and the tenant's whole estimating config.
-- BEFORE-MEASUREMENT: 0 sign links exist, 0 inside the copy window (no remote signature has happened). PROVED
-- BEFORE (synthetic tenant, rolled back): the payload carried 23 estimate columns incl. id, org_id, created_at,
-- updated_at, build_mode; line rows with id, org_id, estimate_id, product_id; the signature row with id, org_id,
-- estimate_id, pdf_url; and `estimating_config` — the tenant's config object, whatever it holds.
-- THE SHAPE, DERIVED FROM WHAT THE COPY RENDERS (Track U's composeAndSendSignedCopy → buildDocumentLayout →
-- renderEstimatePdf on track-u 1285f0f, and parseEstimateBranding): the document fields the layout reads, the
-- five branding fields the copy prints, the signer block, and the address it is sent to. NOTHING ELSE:
--   · no row ids (the one id kept is signature_id: it is the send's idempotency key, and the same caller was
--     already handed it by sign_estimate_by_link);
--   · no org_id, deal_id, product_id, timestamps other than those printed, build_mode, pdf_url;
--   · the branding sub-object, not the tenant config.
-- The customer's phone and email stay: the copy prints them in the customer block, exactly as the in-person
-- copy does, they are the signer's own details on the signer's own document, and `to` is that email.
-- A line's scope_key becomes `scope_generated` (a boolean): the layout only asks whether one exists.
-- ROUTED TO TRACK U: composeAndSendSignedCopy's link path must read this shape (estimate/line_items/signature
-- are named-field objects, not table rows; `branding` replaces estimating_config + org_name). Nothing on main
-- calls signed_copy_by_link today, so no deployed caller breaks (rule 5b).
--
-- (1c) A CUSTOMER MUST NEVER SIGN A DOCUMENT WITH NO PRICE ON IT. MEASURED: of 4 live estimates, 0 have a NULL
-- presented_total (3 signed, 1 void); the only function that sets status 'presented' is present_estimate(),
-- which prices it. The hole is a row put into 'presented' any other way. PROVED BEFORE (synthetic, rolled back):
-- with presented_total NULL, create_estimate_sign_link() CREATED a link and the signer's document read
-- total = NULL. Now refused, with a NAMED reason Track U can render: HINT = 'no_presented_total'.
-- A link issued before a total went NULL cannot be signed either: the document hash changes and
-- signing_link_resolve() answers `document_changed` (unchanged).

create or replace function public.signed_copy_by_link(p_token text)
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
  -- ONLY WHAT THE COPY RENDERS (2026-09-17). Adding a key here widens what a customer's token grants.
  return (
    select jsonb_build_object(
      'state', 'ready',
      'signature_id', v_sig,
      'copy_state', (select c.state from public.signed_copy_records c where c.signature_id = v_sig),
      'to', e.email,
      'branding', jsonb_build_object(
        'company_name', coalesce(nullif(btrim(b.branding ->> 'company_name'), ''), o.name),
        'address', b.branding ->> 'address',
        'phone', b.branding ->> 'phone',
        'email', b.branding ->> 'email',
        'terms', b.branding ->> 'terms'),
      'estimate', jsonb_build_object(
        'estimate_number', e.estimate_number, 'estimate_date', e.estimate_date, 'valid_until', e.valid_until,
        'status', e.status, 'presented_at', e.presented_at, 'presented_total', e.presented_total,
        'subtotal', e.subtotal, 'tax_rate', e.tax_rate, 'tax_amount', e.tax_amount,
        'company', e.company, 'contact_name', e.contact_name, 'phone', e.phone, 'email', e.email,
        'site_address', e.site_address, 'squares', e.squares, 'pitch', e.pitch, 'notes_terms', e.notes_terms),
      'line_items', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'description', l.description, 'quantity', l.quantity, 'unit', l.unit,
                 'unit_price', l.unit_price, 'line_total', l.line_total, 'sort_order', l.sort_order,
                 'scope_generated', l.scope_key is not null)
               order by l.sort_order, l.id)
        from public.estimate_line_items l where l.estimate_id = e.id), '[]'::jsonb),
      'signature', (select jsonb_build_object('signer_name', s.signer_name, 'signer_role', s.signer_role,
                                              'signed_at', s.signed_at, 'signature_data', s.signature_data)
                    from public.signatures s where s.id = v_sig))
    from public.estimates e
    join public.organizations o on o.id = e.org_id
    left join lateral (
      select case when jsonb_typeof(tm.config -> 'branding') = 'object' then tm.config -> 'branding' end as branding
      from public.tenant_modules tm
      where tm.org_id = e.org_id and tm.module_key = 'estimating'
      limit 1) b on true
    where e.id = v_est);
end;
$function$;

create or replace function public.create_estimate_sign_link(p_estimate_id uuid, p_valid_days integer)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_org uuid; v_status text; v_total numeric; v_token text; v_id uuid; v_expires timestamptz; v_revoked int;
begin
  select org_id, status, presented_total into v_org, v_status, v_total from public.estimates where id = p_estimate_id;
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
  -- 1c (2026-09-17): a customer never signs a document with no price on it. Named for the UI by its HINT.
  if v_total is null then
    raise exception 'this estimate has no total, so it cannot be sent for signature — present it again to price it'
      using hint = 'no_presented_total';
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
