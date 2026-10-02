-- ROLLBACK for 20261002*_special_trips_policy_names. Written before the migration applied.
--
-- READ THIS BEFORE RUNNING IT: it restores two names that make a FALSE CLAIM. Both policies
-- are org-scoped (`org_id in (my_org_ids())`); neither has ever been per-person. The office
-- view of special trips reads the table directly and depends on that org scope, so restoring
-- the word "own" re-arms the trap: the next person who "corrects" the policy to match its name
-- takes the office view blind while doing the responsible-looking thing.
-- Behaviour is identical either way — only the claim changes.

alter policy "members read every special_trip in their org"   on public.special_trips rename to "member read own special_trips";
alter policy "members insert special_trips into their own org" on public.special_trips rename to "member insert own special_trips";
