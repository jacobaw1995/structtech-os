-- StructTech OS — Chunk 5 bug fix: present_estimate() must snapshot the
-- FULL total (subtotal + tax), not subtotal alone.
--
-- Found live during Chunk 5 verification (the "PDF vs on-screen, prove it"
-- pass turned this up): presented_total only ever captured `subtotal`,
-- never tax_amount, since the RPC was first written (Chunk 1). Estimate
-- Document's "editedSincePresented" check (Chunk 2) compares presented_total
-- against the LIVE total (subtotal + tax) — so any estimate with a nonzero
-- tax_rate falsely showed "— edited since" in front of the customer in
-- Present Mode, even with zero edits made after presenting. Same signature,
-- no overload risk (CREATE OR REPLACE is safe) — only what gets captured
-- changes.

create or replace function public.present_estimate(p_estimate_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_status text;
  v_subtotal numeric;
  v_tax_amount numeric;
begin
  select org_id, status, subtotal, tax_amount into v_org_id, v_status, v_subtotal, v_tax_amount
  from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  if v_status in ('signed', 'void') then
    raise exception 'estimate % cannot be presented from status %', p_estimate_id, v_status;
  end if;

  update public.estimates
  set status = 'presented',
      presented_total = v_subtotal + coalesce(v_tax_amount, 0),
      presented_at = now()
  where id = p_estimate_id;
end;
$$;
