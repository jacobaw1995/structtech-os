-- StructTech OS — Phase A Week 1: assistant capability role, chunk 1 of 5.
--
-- NOT APPLIED. Author-only migration file — ask before applying, same as
-- every other migration in this repo. This one touches org_members, so
-- treat it with the same care as an auth/RLS change per CLAUDE.md.
--
-- Context: docs/BACKLOG.md "(c) Admin-assistant role — granular capability
-- flags" + Isaac's employee (real seat, 7/24). Full design + the 3 resolved
-- interactions live in the in-app Build Tracker, "Assistant role —
-- capability flags (hide $)" (Phase A / Roles & access) — notes empty at
-- time of writing, nothing beyond BACKLOG.md to fold in.
--
-- This chunk adds ONLY the mechanism (column + resolver) — no enforcement
-- yet. Nothing live changes: no caller reads permissions until chunks 2-5
-- (financials strip, estimates gate, edit-scope widen, UI) land. Verified
-- immediately before writing this file: neither org_members.permissions nor
-- has_capability() exist yet (pg_proc / information_schema checked live),
-- so this is a plain CREATE, not an overload risk.
--
-- ============================================================================
-- 1. org_members.permissions — per-tenant, per-user capability overrides.
-- ============================================================================
alter table public.org_members
  add column if not exists permissions jsonb not null default '{}'::jsonb;

comment on column public.org_members.permissions is
  'Capability overrides for member-tier users. Keys: view_financials, view_estimates, '
  'create_estimates, edit_leads, add_notes, schedule, manage_users, view_field. Absent key '
  '= role default (see has_capability()). Ignored for manager-tier roles '
  '(owner/admin/agency_admin) — they are unrestricted regardless of this column.';

-- ============================================================================
-- 2. has_capability(org_id, capability) — the single resolver every
-- enforcement point (chunks 2-5) will call. Same shape as is_org_manager:
-- SQL, STABLE, SECURITY DEFINER, search_path pinned at creation.
--
-- Precedence (locked in the roadmap design, don't re-litigate):
--   - Manager tier (role in owner/admin/agency_admin) -> true for
--     everything. Managers are unaffected by this whole feature.
--   - Member tier -> permissions->>capability if that key is PRESENT;
--     otherwise the capability's own default. Defaults reproduce today's
--     behavior for every existing plain member (no permissions row set):
--     view_financials / view_estimates / view_field / add_notes / schedule
--     default TRUE; edit_leads / create_estimates / manage_users default
--     FALSE. Only a user with an explicit permissions entry (the
--     assistant) is ever restricted below today's baseline.
--   - No membership row, or an unrecognized capability key -> false
--     (fail closed; callers can probe without catching an exception).
--
-- Pure SQL (no IF), so there's no PL/pgSQL NULL-as-false trap (CLAUDE.md
-- migration discipline #5) to begin with — the outer coalesce just keeps
-- the return type NOT NULL for every input, including a caller with zero
-- org_members rows in this org.
-- ============================================================================
create or replace function public.has_capability(p_org_id uuid, p_capability text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    case
      when public.is_org_manager(p_org_id) then true
      else (
        select coalesce(
          (m.permissions ->> p_capability)::boolean,
          p_capability = any(array[
            'view_financials', 'view_estimates', 'view_field', 'add_notes', 'schedule'
          ])
        )
        from public.org_members m
        where m.org_id = p_org_id
          and m.user_id = auth.uid()
      )
    end,
    false
  );
$$;

comment on function public.has_capability(uuid, text) is
  'Capability resolver for the assistant/member permission model. Manager-tier roles '
  '(owner/admin/agency_admin) always true. Member tier reads org_members.permissions, '
  'falling back to per-capability defaults that preserve legacy plain-member behavior. '
  'No membership row or unknown capability key resolves false, never an error.';
