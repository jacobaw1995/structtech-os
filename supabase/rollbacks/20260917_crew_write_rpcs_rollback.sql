-- ROLLBACK for 20260917 crew_write_rpcs. Drops the write path; the tables and their rows are untouched.
drop function if exists public.fetch_crew_roster(uuid);
drop function if exists public.unassign_crew_from_work_order(uuid);
drop function if exists public.assign_crew_to_work_order(uuid, uuid, text);
drop function if exists public.delete_crew_person_unavailability(uuid);
drop function if exists public.add_crew_person_unavailability(uuid, date, date, text);
drop function if exists public.remove_crew_member(uuid, uuid);
drop function if exists public.add_crew_member(uuid, uuid, boolean);
drop function if exists public.delete_crew(uuid);
drop function if exists public.set_crew_archived(uuid, boolean);
drop function if exists public.rename_crew(uuid, text);
drop function if exists public.create_crew(uuid, text);
drop function if exists public.delete_crew_person(uuid);
drop function if exists public.set_crew_person_archived(uuid, boolean);
drop function if exists public.update_crew_person(uuid, jsonb);
drop function if exists public.create_crew_person(uuid, text, text, text, text[], boolean, text, uuid);
drop function if exists public.crew_check_login(uuid, uuid, uuid);
drop function if exists public.crew_assert_can_manage(uuid);
