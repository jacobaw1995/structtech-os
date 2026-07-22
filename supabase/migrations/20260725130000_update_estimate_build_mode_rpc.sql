-- StructTech OS — Estimate builder rebuild, Chunk 4: build_mode toggle RPC
--
-- NOT APPLIED. Author-only migration file — ask before applying, same as
-- every other migration in this repo.
--
-- Small, deliberately separate from update_estimate_details: build_mode is
-- always explicitly provided by the Manual/Guided toggle (never a partial
-- coalesce-style update alongside other fields), and it's not a "one-way
-- door" like tax_rate/valid_until — there's no "no mode" state to protect,
-- switching back and forth is the entire point. Adding an 11th param to
-- update_estimate_details for this would just be scope creep onto an
-- already-large RPC; a two-argument setter is clearer.
--
-- Same signed/void gate as every other estimate-mutating RPC. Does NOT
-- touch line items — that's runScopeGeneration's job in the TS action
-- layer (src/lib/estimating/actions.ts), called separately right after
-- this when switching TO guided.

create or replace function public.update_estimate_build_mode(
  p_estimate_id uuid,
  p_build_mode text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_status text;
begin
  select org_id, status into v_org_id, v_status
  from public.estimates where id = p_estimate_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'estimate not found or not accessible: %', p_estimate_id;
  end if;

  if v_status in ('signed', 'void') then
    raise exception 'estimate % is locked (status: %)', p_estimate_id, v_status;
  end if;

  if p_build_mode not in ('manual', 'guided') then
    raise exception 'invalid build_mode: %', p_build_mode;
  end if;

  update public.estimates
  set build_mode = p_build_mode,
      updated_at = now()
  where id = p_estimate_id;
end;
$$;
