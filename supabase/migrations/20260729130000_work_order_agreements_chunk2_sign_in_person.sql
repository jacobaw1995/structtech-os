-- StructTech OS — Phase A Week 2, Chunk 2: in-person signing.
--
-- NOT APPLIED. Author-only migration file — ask before applying.
--
-- Adds ONE new RPC: sign_work_order_agreement. No schema changes — chunk 1
-- already added every column this needs (colors_finishes, signer_*,
-- signature_data, signed_at, status). Verified live before writing this
-- file: sign_work_order_agreement does not exist in pg_proc — clean
-- create, no overload risk.
--
-- colors_finishes shape (undecided at the chunk-1 schema level, decided
-- here since this is the form that produces it):
--   { description: string (required — the hard-requirement field),
--     shingle_color?: string, trim_color?: string, gutter_color?: string }
-- `description` is validated non-empty server-side below — that's the
-- actual "hard signature/initials requirement on colors & finishes"
-- (Jacob, COORDINATION_MODULE_SCOPE.md §7). The three named color fields
-- are optional structure on top, not individually required — kept generic
-- (a free-text confirmation) rather than hard-coding "shingle" as
-- mandatory, since this platform isn't roofing-only (CLAUDE.md tenant
-- model). Flag if BMR specifically wants shingle_color mandatory too.
--
-- Deliberate behavior change from the old stub (record_work_order_sign_off,
-- SignOffPanel's "Edit notes" disclosure): once an agreement is signed, it
-- is immutable — no more post-signoff editing of the signed content. That
-- was the notes-only stub's whole design; a REAL signature can't be
-- silently rewritten. Any post-sign-off change now needs a change order
-- (void + replace, later chunk), not an in-place edit. Materials/schedule
-- themselves stay editable per §2.6 — only the signed agreement content
-- (colors_finishes/signature) is now locked once signed.
--
-- Existing work orders that already have sign_off_at set from the OLD
-- notes-only stub have NO work_order_agreements row yet — the new UI will
-- prompt them to sign for real. Deliberate, not a bug: the old capture was
-- never a real signature, so re-prompting is correct behavior, not a
-- regression. Flagging in case Jacob wants those grandfathered instead.
create or replace function public.sign_work_order_agreement(
  p_agreement_id uuid,
  p_colors_finishes jsonb,
  p_signer_name text,
  p_signer_role text,
  p_signature_data text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_work_order_id uuid;
  v_status text;
begin
  select org_id, work_order_id, status
  into v_org_id, v_work_order_id, v_status
  from public.work_order_agreements
  where id = p_agreement_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'agreement not found or not accessible: %', p_agreement_id;
  end if;

  if v_status <> 'pending' then
    raise exception 'agreement % is not pending (current status: %)', p_agreement_id, v_status;
  end if;

  if not (
    p_colors_finishes ? 'description'
    and nullif(trim(p_colors_finishes ->> 'description'), '') is not null
  ) then
    raise exception 'colors & finishes must be confirmed before signing';
  end if;

  update public.work_order_agreements
  set colors_finishes = p_colors_finishes,
      signer_name = p_signer_name,
      signer_role = p_signer_role,
      signature_data = p_signature_data,
      signed_at = now(),
      status = 'signed',
      updated_at = now()
  where id = p_agreement_id;

  -- Mirror onto work_orders (chunk 1 design note) so coordinationStages()
  -- and every existing sign_off_at/sign_off_notes reader keeps working.
  -- sign_off_notes gets a short synthesized summary, not the full jsonb.
  update public.work_orders
  set sign_off_at = coalesce(sign_off_at, now()),
      sign_off_notes = concat('Signed by ', p_signer_name, ' (', p_signer_role, ')'),
      updated_at = now()
  where id = v_work_order_id;

  -- Deliberately NOT logged to work_order_activity: that table's
  -- documented purpose (its own migration filename) is the POST-sign-off
  -- change audit trail, not the signing event itself — every existing
  -- writer to it only fires for changes strictly after sign_off_at is
  -- already set. The signing event is already fully recorded on this row
  -- (signed_at/signer_name/signer_role). Logging it here too would break
  -- the "activity.length > 0 means something changed after signing"
  -- assumption the coordination UI already relies on.
end;
$$;

comment on function public.sign_work_order_agreement(uuid, jsonb, text, text, text) is
  'Signs a pending work order agreement — validates colors_finishes.description is non-empty (the hard requirement), records the signature, flips status to signed, mirrors sign_off_at/sign_off_notes onto work_orders. Rejects a non-pending agreement (already signed/voided). Does not write work_order_activity — that table is the post-sign-off change trail, not the signing event itself.';
