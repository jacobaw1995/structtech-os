-- StructTech OS — CRM Depth Stage 5, Track B1: guarantee a profile per auth user.
--
-- Context: docs/reference/STAGE5_GOLIVE_GATE.md, Track B. Independent of B2
-- (seeding Isaac) — this just makes profile creation automatic and backfills
-- the one known orphan (jacobaw1995@gmail.com, confirmed 7/17: auth user with
-- no profiles/org_members row). Does NOT touch org_members or create any new
-- membership — a profile alone grants no org access (RLS on every domain
-- table gates through org_members via my_org_ids(), not profiles).
--
-- ============================================================================
-- 1. handle_new_user() — SECURITY DEFINER so it can write to public.profiles
--    regardless of RLS, search_path pinned per the Track A hardening pattern.
--    full_name falls back user_meta_data.full_name -> .name -> email, so it's
--    never null (profiles.full_name is NOT NULL). ON CONFLICT DO NOTHING makes
--    it idempotent — safe if a profile somehow already exists for that id.
--    role is omitted; profiles.role already defaults to 'salesman'.
-- ============================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'full_name', ''),
             nullif(new.raw_user_meta_data->>'name', ''),
             new.email),
    new.email
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- ============================================================================
-- 2. Trigger — fires after every new auth.users row (signup, invite, admin
--    create), so every future user gets a profile automatically. This is the
--    prerequisite Track B2 (Isaac's invite) depends on.
-- ============================================================================
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================================
-- 3. Backfill — covers every existing auth.users row with no matching
--    profile (the 1 known orphan today, but written generically so it's
--    correct regardless of count).
-- ============================================================================
insert into public.profiles (id, full_name, email)
select
  u.id,
  coalesce(nullif(u.raw_user_meta_data->>'full_name', ''),
           nullif(u.raw_user_meta_data->>'name', ''),
           u.email),
  u.email
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null;
