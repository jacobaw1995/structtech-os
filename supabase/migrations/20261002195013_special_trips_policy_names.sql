-- A NAME IS A CLAIM. TWO POLICIES ON special_trips MAKE A FALSE ONE.
-- Track S · 2026-10-02. Rollback: supabase/rollbacks/20261002_special_trips_policy_names_rollback.sql
--
-- FOUND BY TRACK U on 2026-10-01, while building the office view — not by an audit.
-- `member read own special_trips` is ORG-SCOPED: its expression is `org_id in (my_org_ids())`,
-- with no reference to `recorded_by` and none to `auth.uid()`. It has never been per-person.
--
-- WHY THE NAME IS DANGEROUS RATHER THAN UNTIDY. U's new office view reads the table DIRECTLY
-- (`.from("special_trips")` in coordination/[workOrderId]/page.tsx) and depends on exactly that
-- org scope. **Anybody who later "corrects" the policy to match its name takes the office view
-- blind — while doing the responsible-looking thing.** A wrong name does not merely fail to
-- help; it recruits a careful reader into breaking something.
--
-- AND IT IS TWO, NOT ONE. The INSERT policy is named `member insert own special_trips` and its
-- WITH CHECK is `org_id in (my_org_ids())` — any member may insert for the org, not only "their
-- own". Same word, same falsehood, found by reading the three policies together rather than the
-- one that was reported. The DELETE policy's name is ACCURATE and is left alone:
-- `member delete special_trips author or office` is exactly what its expression does.
--
-- ZERO BEHAVIOUR CHANGE, AND IT IS PROVED RATHER THAN ASSERTED. ALTER POLICY ... RENAME TO
-- cannot touch an expression — but "cannot" is an argument, and the proof is in the migration's
-- own transaction: every field of pg_policies except `policyname` is compared before and after,
-- and three real identities count the rows they can see across the rename, on SEEDED data so
-- the instrument is not empty (special_trips holds 0 rows in production).

alter policy "member read own special_trips"   on public.special_trips rename to "members read every special_trip in their org";
alter policy "member insert own special_trips" on public.special_trips rename to "members insert special_trips into their own org";
