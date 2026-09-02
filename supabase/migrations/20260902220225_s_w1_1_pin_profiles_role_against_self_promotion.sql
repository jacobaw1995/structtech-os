-- S-W1.1 · migration 2 of 2 · 2026-09-02 (America/New_York)
-- Closes finding 3 of docs/CROSS_TENANT_AUDIT_20260901.md §8: any authenticated
-- user could `update profiles set role='manager' where id = auth.uid()` and make
-- is_pipeline_manager() return true for themselves.
--
-- `pipeline_profiles_update_own` was FOR UPDATE TO authenticated USING
-- (id = auth.uid()) with NO with_check, so the USING expression served as the
-- check and `role` -- an ordinary writable column -- was self-writable.
--
-- WHY A DEFINER HELPER AND NOT A PLAIN SUBSELECT. The obvious one-liner,
-- `with check (... and role = (select p.role from public.profiles p where
-- p.id = auth.uid()))`, was written, tested on 2026-09-02, and REJECTED: it
-- raises `42P17 infinite recursion detected in policy for relation "profiles"`.
-- That is CLAUDE.md rule 7's org_members trap on a different table. It is
-- recorded here because the failure is deceptive -- the self-promotion probe
-- "passed" (refused) while EVERY positive control also failed, i.e. the policy
-- blocked all profile updates, not just the role change. Only the controls
-- distinguished a fix from an outage.
--
-- my_pipeline_role() is SECURITY DEFINER for the same reason my_org_ids() is:
-- it reads the caller's own row without re-entering the policy.
-- authenticated KEEPS execute -- the policy is scoped TO authenticated and is
-- evaluated as that role, so revoking it would make the policy unevaluable and
-- lock the table (the A1.5 storefront precedent, in reverse). anon never
-- evaluates this policy and is revoked.
--
-- Rule 13 -- what would have to change for this to reopen: somebody grants a
-- write path to profiles.role, or drops this WITH CHECK. Both are edits to
-- this policy, visible in the diff that makes them.
--
-- NOTE, deliberate and symmetric: role becomes immutable through this path in
-- BOTH directions. A manager cannot self-demote either. Nothing in src/ or in
-- any function writes profiles.role today (measured 2026-09-02: zero src/
-- references outside generated types, zero functions updating it), so there is
-- no caller to break. handle_new_user sets role on INSERT, which this policy
-- does not govern.

create or replace function public.my_pipeline_role()
returns public.pipeline_user_role
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

comment on function public.my_pipeline_role() is
  'The calling user''s own profiles.role, read as definer so that pipeline_profiles_update_own can compare against it without recursing into the profiles policy. S-W1.1, 2026-09-02.';

drop policy "pipeline_profiles_update_own" on public.profiles;

create policy "pipeline_profiles_update_own" on public.profiles
  for update
  to authenticated
  using (id = auth.uid())
  with check (
    id = auth.uid()
    and role = public.my_pipeline_role()
  );

revoke execute on function public.my_pipeline_role() from public, anon;