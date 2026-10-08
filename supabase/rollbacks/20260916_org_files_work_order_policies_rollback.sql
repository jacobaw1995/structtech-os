-- ROLLBACK for the org-files work order policies (2026-09-16). Returns org-files to NO POLICY — closed to every
-- API caller, which is the state before. Remove any objects uploaded under these policies first if they must
-- not be orphaned (they stay in the bucket, unreadable).

-- ═══ SCOPED 2026-10-08 (Track S), AND THE REASON IS WHAT `IF EXISTS` HIDES ═══
--
-- `storage.objects` IS A SHARED TABLE. Measured 2026-10-08: it carries **10
-- policies and only 3 are ours** — `org-files work order files read/insert/
-- delete`. The other seven belong to Material Matrix and to the catalog:
-- `pdf-files staff read`, `product-photos public read/role delete/role insert/
-- role update`, `spec-files customer upload`, `spec-files staff read`.
--
-- THE PROBLEM WITH `DROP POLICY IF EXISTS … ON storage.objects` IS NOT THAT IT
-- MIGHT DROP SOMEBODY ELSE'S POLICY BY NAME — these three names are ours. It is
-- that **`IF EXISTS` makes "already gone" and "never mine" indistinguishable**,
-- and this file is what runs in a panic. A renamed policy, a typo, or a policy
-- somebody recreated under one of these names with a different predicate all
-- produce the same silent success. That is CLAUDE.md rule 2's trap — `IF EXISTS`
-- suppressing the no-match error — applied to policies instead of functions.
--
-- SO EACH DROP NOW ASSERTS THE POLICY IS OURS FIRST: it must exist, and its
-- expression must carry our own `bucket_id = 'org-files'` term. Three outcomes,
-- all three distinguishable in the output:
--   · present and ours      → dropped, and said so
--   · absent                → NOTICE "already gone", nothing done
--   · present but NOT ours  → **RAISE**, and the whole rollback aborts
-- The third is the one `IF EXISTS` could not express, and it is the one that
-- would matter: a policy wearing our name over somebody else's bucket is not
-- ours to drop, and a rollback that drops it has done harm while reporting
-- success.

do $$
declare
  v_name text;
  v_expr text;
  v_dropped int := 0;
  v_absent  int := 0;
begin
  foreach v_name in array array[
    'org-files work order files read',
    'org-files work order files insert',
    'org-files work order files delete'
  ] loop
    select coalesce(qual,'') || coalesce(with_check,'') into v_expr
    from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = v_name;

    if v_expr is null then
      raise notice 'ALREADY GONE: %  (nothing dropped)', v_name;
      v_absent := v_absent + 1;
    elsif v_expr not like '%org-files%' then
      raise exception 'REFUSING TO DROP: a policy named "%" exists on storage.objects but its expression does not mention org-files, so it is not the one this rollback created. Nothing has been dropped. Read it before deciding.', v_name;
    else
      execute format('drop policy %I on storage.objects', v_name);
      raise notice 'DROPPED (verified ours): %', v_name;
      v_dropped := v_dropped + 1;
    end if;
  end loop;

  -- Print the SIZE of what was examined beside the result (CLAUDE.md 26):
  -- "0 dropped" means something different when 3 were absent than when 3 were
  -- refused, and only this line can tell them apart.
  raise notice 'org-files policy rollback: 3 examined, % dropped, % already gone', v_dropped, v_absent;
end $$;

-- Unchanged: this one is ours by name and by schema, and nothing else in the
-- database defines it. `IF EXISTS` is appropriate for a function we own outright.
drop function if exists public.can_reach_work_order_files(uuid);

-- VERIFY, rather than trusting the notices above (rule 3). Expect 0 ours, and
-- the other seven untouched.
select count(*) filter (where policyname like 'org-files%') as ours_remaining,
       count(*) filter (where policyname not like 'org-files%') as not_ours_untouched,
       count(*) as total
from pg_policies where schemaname = 'storage' and tablename = 'objects';
