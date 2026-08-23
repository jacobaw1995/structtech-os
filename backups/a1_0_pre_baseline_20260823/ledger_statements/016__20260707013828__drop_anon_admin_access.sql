
-- Cutover: staff now authenticate as real Supabase Auth users (verified working). Drop the
-- anon-key blanket-access policies used for admin's own read/write. Deliberately NOT touched:
--   audit_leads "Allow anon insert"   — public lead-capture form (audit.structtek.com), must stay anon-insertable
--   client_roadmaps "insert roadmap"  — separate, pre-existing, out of scope for this cutover
drop policy "anon update leads" on public.audit_leads;
drop policy "anon read leads" on public.audit_leads;
drop policy "anon all deal_activity" on public.deal_activity;
drop policy "anon all deal_notes" on public.deal_notes;
drop policy "anon all deals" on public.deals;
drop policy "anon all engagement_checkins" on public.engagement_checkins;
drop policy "anon all engagement_levels" on public.engagement_levels;
drop policy "anon all engagement_milestones" on public.engagement_milestones;
drop policy "anon all engagements" on public.engagements;
drop policy "anon all follow_ups" on public.follow_ups;
drop policy "anon all org_invites" on public.org_invites;
drop policy "anon all org_invoices" on public.org_invoices;
drop policy "anon all org_members" on public.org_members;
drop policy "anon all org_systems" on public.org_systems;
drop policy "anon all organizations" on public.organizations;
drop policy "anon all ticket_messages" on public.ticket_messages;
drop policy "anon all tickets" on public.tickets;
