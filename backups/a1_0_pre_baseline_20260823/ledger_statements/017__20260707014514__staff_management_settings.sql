
alter table public.staff_users add column email text;
update public.staff_users su set email = u.email from auth.users u where u.id = su.user_id and su.email is null;

-- Was SELECT-only ("managed by service role"); admin now needs to invite/revoke from the UI.
drop policy "staff read staff_users" on public.staff_users;
drop policy "staff read staff_invites" on public.staff_invites;
create policy "staff all staff_users" on public.staff_users for all to authenticated using (is_staff()) with check (is_staff());
create policy "staff all staff_invites" on public.staff_invites for all to authenticated using (is_staff()) with check (is_staff());

create or replace function public.accept_staff_invite(p_token text, p_full_name text default null)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare inv record; u_email text;
begin
  select * into inv from public.staff_invites where token = p_token and accepted_at is null;
  if not found then raise exception 'invalid or used invite'; end if;
  if auth.uid() is null then raise exception 'not signed in'; end if;

  select email into u_email from auth.users where id = auth.uid();

  insert into public.staff_users (user_id, role, full_name, email)
  values (auth.uid(), inv.role, p_full_name, u_email)
  on conflict (user_id) do nothing;

  update public.staff_invites set accepted_at = now() where id = inv.id;
end;
$function$;
