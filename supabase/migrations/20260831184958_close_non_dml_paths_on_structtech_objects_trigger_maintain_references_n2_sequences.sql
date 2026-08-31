-- A-PATH.1 · 2026-08-31 (America/New_York) · StructTech OS
-- Close the destructive/structural paths RLS does not mediate, on OUR objects only.
--
-- WHY: A-PATH.0 enumerated the paths RLS never sees. TRIGGER, MAINTAIN and REFERENCES
-- are stock GRANT ALL residue from pg_default_acl (defaclrole=postgres, defaclnamespace=public,
-- defaclobjtype='r' => anon/authenticated born with arwdDxtm). Nothing in src/ and no
-- StructTech function body consumes any of them -- measured, not assumed: the only two
-- function bodies in public referencing these verbs are Material Matrix's.
--
-- MEASURED BEFORE APPLYING, as `authenticated` in a rolled-back transaction:
--   CREATE TRIGGER on public.products  -> SUCCEEDED (the capability was real, not merely catalog-present)
--   ANALYZE public.deals               -> SUCCEEDED
--   temp-table FK -> public.deals      -> 42P16 (REFERENCES is unreachable: no CREATE on any schema,
--                                        and temp constraints may reference only temp tables)
--
-- SELECT/INSERT/UPDATE/DELETE on the 52 are deliberately NOT touched. They are load-bearing and
-- the barrier there is deliberately RLS (CLAUDE.md rule 11, amendment).
--
-- NOT INCLUDED, DELIBERATELY:
--   * public.wh_current_prices -- the only object holding TRUNCATE, and a Material Matrix VIEW. Reported, not actioned.
--   * public.wh_order_number_seq -- Material Matrix's sequence; also the only object holding an anon SELECT
--     among sequences, and it is read by their SECURITY DEFINER create_wh_order(). Reported, not actioned.
--   * anything in storage / owned by supabase_storage_admin or supabase_admin
--   * any ALTER DEFAULT PRIVILEGES / pg_default_acl change

-- 4.1 + 4.2 + 4.3 -- one identical list of 52; every one of them carries all three privileges.
revoke trigger, maintain, references on
  public.audit_leads,
  public.audits,
  public.check_ins,
  public.client_roadmaps,
  public.deal_activity,
  public.deal_notes,
  public.deals,
  public.engagement_checkins,
  public.engagement_levels,
  public.engagement_milestones,
  public.engagements,
  public.estimate_line_items,
  public.estimate_number_counters,
  public.estimates,
  public.follow_ups,
  public.jobs,
  public.lead_activity,
  public.lead_appointments,
  public.lead_notes,
  public.leads,
  public.material_items,
  public.migration_bmr_activity_raw,
  public.migration_bmr_id_map,
  public.migration_bmr_leads_raw,
  public.migration_bmr_notes_raw,
  public.migration_bmr_users_raw,
  public.org_invites,
  public.org_invoices,
  public.org_members,
  public.org_systems,
  public.organizations,
  public.pipeline_invites,
  public.production_packets,
  public.products,
  public.profiles,
  public.proposals,
  public.prospects,
  public.roadmap_items,
  public.roadmap_projects,
  public.schedule_blocks,
  public.signatures,
  public.staff_invites,
  public.staff_users,
  public.structtech_state,
  public.tenant_modules,
  public.ticket_messages,
  public.tickets,
  public.tracker_items,
  public.tracker_projects,
  public.work_order_activity,
  public.work_order_agreements,
  public.work_orders
from authenticated;

-- 4.4 -- the 7 N2 tables: RLS on, ZERO policies, live authenticated DML grant.
-- 8/29 applied this same revoke to anon on these tables and did not apply it to authenticated.
-- Closure here was "nobody has written a policy yet" -- an absence with no owner (rule 13).
-- After this, the reopening change is "somebody grants authenticated this table," which is a
-- statement about the table, reviewable in the diff that makes it.
--
-- PROVED SAFE BEFORE APPLYING, in a rolled-back transaction with a real BMR owner JWT:
--   create_estimate_from_deal() is the ONLY reader of estimate_number_counters anywhere
--   (0 non-generated references in src/; 1 function body). It is SECURITY DEFINER, so it reads
--   as the definer and not through this grant. After the revoke it still produced EST-9.
--   Positive control in the same transaction: 192 deals visible. Nothing in src/ reads any of the 7.
revoke select, insert, update, delete on
  public.estimate_number_counters,
  public.structtech_state,
  public.migration_bmr_activity_raw,
  public.migration_bmr_id_map,
  public.migration_bmr_leads_raw,
  public.migration_bmr_notes_raw,
  public.migration_bmr_users_raw
from authenticated;

-- 4.6 -- sequences. UPDATE is what permits setval(); USAGE is what permits nextval().
-- VERIFIED AGAINST THE SERVER, not against the sentence, in a rolled-back transaction:
--   after `revoke update`, setval() -> 42501 permission denied for sequence (form 1, target)
--   and nextval() still returned a value (positive control in the same transaction).
-- The first attempt at this probe was INVALID and was re-run: the probe sequence was born
-- holding authenticated=rwU from pg_default_acl, so "grant usage, select" had not withheld
-- UPDATE at all and setval appeared to succeed without it. The contaminant was the very
-- default-ACL mechanism this file exists downstream of.
-- anon holds nothing on either of these (revoked 2026-08-28); only UPDATE is left to remove.
revoke update on sequence
  public.tg_agenda_card_id_seq,
  public.tg_agenda_contact_id_seq
from authenticated;