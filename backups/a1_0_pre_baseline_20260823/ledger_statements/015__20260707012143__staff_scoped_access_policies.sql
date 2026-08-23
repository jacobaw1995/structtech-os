
-- Staff (authenticated, is_staff()) get full access to admin-side tables. Additive: existing
-- anon-all policies are left in place for now so nothing breaks before Jacob's real staff
-- account is confirmed; they'll be dropped in a follow-up once that's verified.
create policy "staff all deals" on public.deals for all to authenticated using (is_staff()) with check (is_staff());
create policy "staff all deal_notes" on public.deal_notes for all to authenticated using (is_staff()) with check (is_staff());
create policy "staff all deal_activity" on public.deal_activity for all to authenticated using (is_staff()) with check (is_staff());
create policy "staff all follow_ups" on public.follow_ups for all to authenticated using (is_staff()) with check (is_staff());
create policy "staff all organizations" on public.organizations for all to authenticated using (is_staff()) with check (is_staff());
create policy "staff all org_invites" on public.org_invites for all to authenticated using (is_staff()) with check (is_staff());
create policy "staff all org_members" on public.org_members for all to authenticated using (is_staff()) with check (is_staff());
create policy "staff all org_systems" on public.org_systems for all to authenticated using (is_staff()) with check (is_staff());
create policy "staff all org_invoices" on public.org_invoices for all to authenticated using (is_staff()) with check (is_staff());
create policy "staff all tickets" on public.tickets for all to authenticated using (is_staff()) with check (is_staff());
create policy "staff all ticket_messages" on public.ticket_messages for all to authenticated using (is_staff()) with check (is_staff());
create policy "staff all audit_leads" on public.audit_leads for all to authenticated using (is_staff()) with check (is_staff());
create policy "staff all engagements" on public.engagements for all to authenticated using (is_staff()) with check (is_staff());
create policy "staff all engagement_levels" on public.engagement_levels for all to authenticated using (is_staff()) with check (is_staff());
create policy "staff all engagement_milestones" on public.engagement_milestones for all to authenticated using (is_staff()) with check (is_staff());
create policy "staff all engagement_checkins" on public.engagement_checkins for all to authenticated using (is_staff()) with check (is_staff());
