begin;

-- ── 1. my_wh_role(): explicit team role, else org-owner => admin, else null ──
create or replace function public.my_wh_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    -- (a) the caller's active WH team role for their org, if a row exists
    (select role
     from public.wh_team_members
     where user_id = auth.uid()
       and status = 'active'
       and org_id in (select public.my_org_ids())
     order by (role = 'admin') desc, (role = 'assistant') desc
     limit 1),
    -- (b) else 'admin' if the caller is the org owner of a WH org they belong to
    (select 'admin'
     from public.org_members
     where user_id = auth.uid()
       and role = 'owner'
       and org_id in (select public.my_org_ids())
     limit 1)
    -- (c) else null (coalesce yields null)
  );
$$;

-- ── 2. Ensure signed-in users can call it (single source of truth w/ the app) ─
grant execute on function public.my_wh_role() to authenticated;

-- ── 3. Remove the hardcoded admin seed (owner fallback now covers jacob) ─────
-- Driver rows (is_driver=true, backfilled from wh_drivers) are NOT touched.
delete from public.wh_team_members
where lower(email) = 'jacob@structtek.com';

commit;
