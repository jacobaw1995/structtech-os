
drop policy "staff read staff_users" on public.staff_users;
drop policy "staff read staff_invites" on public.staff_invites;

create policy "staff read staff_users" on public.staff_users for select to authenticated
  using (public.is_staff());
create policy "staff read staff_invites" on public.staff_invites for select to authenticated
  using (public.is_staff());
