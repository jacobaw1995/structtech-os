-- The first ticket-bot draft put four tables in `public` and even stamped them with the
-- tenant's org_id. That coupling is exactly what the standalone design removes. Carry the
-- one real row across into bmr_tickets, then drop the public tables for good.

insert into bmr_tickets.ticket
  (job_id, job_label, title, severity, status, phase,
   reporter_tg_id, reporter_label, topic_id, resolution, resolved_at, resolved_by, created_at)
select null, coalesce(t.address_text, 'Unspecified'), t.title, t.severity, t.status, t.phase,
       t.reporter_tg_id, t.reporter_label, null, t.resolution, t.resolved_at, t.resolved_by,
       t.created_at
from public.bmr_ticket t;

insert into bmr_tickets.comment (ticket_id, author_tg_id, author_label, body, source, created_at)
select nt.id, m.author_tg_id, m.author_label, m.body, 'migrated', m.created_at
from public.bmr_ticket_message m
join public.bmr_ticket ot on ot.id = m.ticket_id
join bmr_tickets.ticket nt on nt.title = ot.title and nt.reporter_tg_id = ot.reporter_tg_id;

insert into bmr_tickets.person (tg_user_id, label, is_manager)
select mgr.tg_user_id, coalesce(mgr.label, 'Manager'), true
from public.bmr_ticket_manager mgr
on conflict (tg_user_id) do update set is_manager = true;

drop table if exists public.bmr_ticket_photo cascade;
drop table if exists public.bmr_ticket_message cascade;
drop table if exists public.bmr_ticket_manager cascade;
drop table if exists public.bmr_ticket cascade;
