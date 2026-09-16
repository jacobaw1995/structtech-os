-- ROLLBACK for 2026-09-15 crew_model_spine. Every object below was created by that migration; nothing
-- pre-existing was altered by it (work_orders, schedule_blocks and check_ins are untouched).
-- DATA LOSS: every crew person, crew, membership, unavailability window and crew assignment.
drop view if exists public.crew_assignment_states;
drop table if exists public.work_order_crew_assignments;
drop table if exists public.crew_person_unavailability;
drop table if exists public.crew_memberships;
drop table if exists public.crews;
drop table if exists public.crew_people;
drop function if exists public.work_order_crew_assignments_validate();
drop function if exists public.crew_touch_updated_at();
drop function if exists public.crew_trim_names();
